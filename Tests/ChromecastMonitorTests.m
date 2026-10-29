#import <AppKit/AppKit.h>
#import <libproc.h>
#import <stdatomic.h>
#import "ChromecastMonitor.h"
#import "ChromecastProcess.h"

static atomic_ulong Checks = 0;
#define CHECK(condition) do { atomic_fetch_add(&Checks, 1); if (!(condition)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); exit(1); \
} } while (0)

@interface ChromecastMonitor (TestSeams)
- (NSArray<NSDictionary *> *)browserProcesses;
- (BOOL)scanBrowserProcesses:(NSArray<NSDictionary *> *)browsers;
- (void)poll;
@end

@interface FakeMonitor : ChromecastMonitor
@property (nonatomic, copy) BOOL (^scan)(void);
@end
@implementation FakeMonitor
- (NSArray<NSDictionary *> *)browserProcesses {
    CHECK(NSThread.isMainThread);
    return @[];
}
- (BOOL)scanBrowserProcesses:(NSArray<NSDictionary *> *)browsers {
    (void)browsers;
    CHECK(!NSThread.isMainThread);
    return self.scan();
}
@end

static NSData *Arguments(NSArray<NSString *> *argv, NSArray<NSString *> *environment, NSString *executable) {
    NSMutableData *data = [NSMutableData data];
    int count = (int)argv.count;
    [data appendBytes:&count length:sizeof(count)];
    NSData *path = [executable dataUsingEncoding:NSUTF8StringEncoding];
    [data appendData:path];
    const char zeros[] = {0, 0, 0};
    [data appendBytes:zeros length:sizeof(zeros)];
    for (NSString *entry in [argv arrayByAddingObjectsFromArray:environment]) {
        [data appendData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
        [data appendBytes:zeros length:1];
    }
    return data;
}

static BOOL Detect(NSArray<NSString *> *argv, NSArray<NSString *> *environment, NSString *path) {
    NSData *data = Arguments(argv, environment, path);
    return ChromecastArgumentsIndicateMirroring(data.bytes, data.length);
}

static void TestArguments(void) {
    NSString *type = @"--type=utility";
    NSString *service = @"--utility-sub-type=mirroring.mojom.MirroringService";
    NSArray<NSString *> *valid = @[@"Chrome Helper", type, service];
    CHECK(Detect(valid, @[], @"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"));
    CHECK(Detect(@[@"Chrome Helper", service, @"", @"--lang=en", type], @[], @"/helper"));
    CHECK(!Detect(@[@"Google Chrome"], @[type, service], @"/chrome"));
    CHECK(!Detect(@[@"Chrome Helper", type], @[service], @"/helper"));
    CHECK(!Detect(@[@"Chrome Helper", @"--type=renderer", service], @[], @"/helper"));
    CHECK(!Detect(@[@"Chrome Helper", type, @"--utility-sub-type=network.mojom.NetworkService"], @[], @"/helper"));
    CHECK(!Detect(@[@"Chrome Helper", service], @[], @"/helper"));
    CHECK(!Detect(@[@"Chrome Helper", type], @[], service));
    CHECK(!Detect(@[service, type], @[], @"/helper"));
    CHECK(!Detect(@[@"Chrome Helper", type, [service stringByAppendingString:@"Extra"]], @[], @"/helper"));
    CHECK(!Detect(@[@"Chrome Helper", type, [@"/tmp/" stringByAppendingString:service]], @[], @"/helper"));
    CHECK(!Detect(@[@"Chrome Helper", @"--type=utilityExtra", service], @[], @"/helper"));
    CHECK(!Detect(@[@"Chrome Helper", @"--type", @"utility", service], @[], @"/helper"));
    CHECK(!Detect(@[@"Chrome Helper", @"--", type, service], @[], @"/helper"));
    CHECK(!Detect(@[@"Chrome Helper", type, service, @"--type=renderer"], @[], @"/helper"));
    CHECK(!Detect(@[@"Chrome Helper", type, service, type], @[], @"/helper"));
    CHECK(!Detect(@[@"Chrome Helper", type, service, service], @[], @"/helper"));
    CHECK(!Detect(@[], @[], @"/helper"));
    CHECK(!ChromecastArgumentsIndicateMirroring(NULL, 0));
    NSData *good = Arguments(valid, @[], @"/helper");
    for (NSUInteger length = 0; length < good.length; length++) {
        CHECK(!ChromecastArgumentsIndicateMirroring(good.bytes, length));
    }
    NSMutableData *bad = [good mutableCopy];
    int count = -1;
    memcpy(bad.mutableBytes, &count, sizeof(count));
    CHECK(!ChromecastArgumentsIndicateMirroring(bad.bytes, bad.length));
    count = INT_MAX;
    memcpy(bad.mutableBytes, &count, sizeof(count));
    CHECK(!ChromecastArgumentsIndicateMirroring(bad.bytes, bad.length));
    count = 4;
    memcpy(bad.mutableBytes, &count, sizeof(count));
    CHECK(!ChromecastArgumentsIndicateMirroring(bad.bytes, bad.length));
    CHECK(!Detect(valid, @[], @""));
    CHECK(!ChromecastArgumentsIndicateMirroring(good.bytes, 2 * 1024 * 1024 + 1));
}

static BOOL SpinUntil(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    return condition();
}

static void TestLifecycle(void) {
    __block atomic_int scans = 0;
    __block atomic_bool result = true;
    __block NSUInteger notifications = 0;
    FakeMonitor *monitor = [FakeMonitor new];
    monitor.scan = ^BOOL { atomic_fetch_add(&scans, 1); return atomic_load(&result); };
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:ChromecastMonitorDidChangeNotification object:monitor queue:nil usingBlock:^(NSNotification *note) {
        CHECK(NSThread.isMainThread);
        notifications++;
        // Integration may recursively stop on a stop notification.
        ChromecastMonitor *changedMonitor = note.object;
        if (!changedMonitor.isCasting) {
            [changedMonitor stop];
        }
    }];
    CHECK(!monitor.isCasting && atomic_load(&scans) == 0);
    [monitor stop];
    [monitor start];
    [monitor start];
    CHECK(SpinUntil(^BOOL { return monitor.isCasting; }, 1));
    CHECK(atomic_load(&scans) == 1 && notifications == 1);
    [monitor poll];
    CHECK(SpinUntil(^BOOL { return atomic_load(&scans) == 2; }, 1));
    // Wait for the main-queue completion of the repeated unchanged scan.
    CHECK(SpinUntil(^BOOL { return ![[monitor valueForKey:@"scanInProgress"] boolValue]; }, 1));
    CHECK(notifications == 1);
    [monitor stop];
    [monitor stop];
    CHECK(!monitor.isCasting && notifications == 2);
    [NSNotificationCenter.defaultCenter removeObserver:observer];

    dispatch_semaphore_t gate = dispatch_semaphore_create(0);
    atomic_store(&scans, 0);
    notifications = 0;
    monitor = [FakeMonitor new];
    monitor.scan = ^BOOL {
        int number = atomic_fetch_add(&scans, 1);
        if (number == 0) {
            dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
            return YES;
        }
        return NO;
    };
    observer = [NSNotificationCenter.defaultCenter addObserverForName:ChromecastMonitorDidChangeNotification object:monitor queue:nil usingBlock:^(NSNotification *note) {
        (void)note;
        notifications++;
    }];
    [monitor start];
    CHECK(SpinUntil(^BOOL { return atomic_load(&scans) == 1; }, 1));
    [monitor poll];
    [monitor poll];
    CHECK(atomic_load(&scans) == 1);
    [monitor stop];
    [monitor start];
    dispatch_semaphore_signal(gate);
    CHECK(SpinUntil(^BOOL { return atomic_load(&scans) == 2 && ![[monitor valueForKey:@"scanInProgress"] boolValue]; }, 1));
    CHECK(!monitor.isCasting && notifications == 0);
    [monitor stop];
    [NSNotificationCenter.defaultCenter removeObserver:observer];

    // Stop without restart must also discard an already-running positive scan.
    atomic_store(&scans, 0);
    monitor.scan = ^BOOL {
        atomic_fetch_add(&scans, 1);
        dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
        return YES;
    };
    [monitor start];
    CHECK(SpinUntil(^BOOL { return atomic_load(&scans) == 1; }, 1));
    [monitor stop];
    dispatch_semaphore_signal(gate);
    CHECK(SpinUntil(^BOOL { return ![[monitor valueForKey:@"scanInProgress"] boolValue]; }, 1));
    CHECK(!monitor.isCasting);

    __weak FakeMonitor *weakMonitor;
    @autoreleasepool {
        FakeMonitor *temporary = [FakeMonitor new];
        temporary.scan = ^BOOL { return NO; };
        weakMonitor = temporary;
        [temporary start];
    }
    CHECK(SpinUntil(^BOOL { return weakMonitor == nil; }, 1));
}

static NSTask *StartFixture(NSString *path, NSArray<NSString *> *arguments, NSDictionary<NSString *, NSString *> *environment) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = arguments;
    task.environment = environment;
    task.standardInput = [NSPipe pipe];
    NSPipe *output = [NSPipe pipe];
    task.standardOutput = output;
    NSError *error = nil;
    CHECK([task launchAndReturnError:&error]);
    CHECK([[output.fileHandleForReading readDataOfLength:1] isEqualToData:[@"R" dataUsingEncoding:NSUTF8StringEncoding]]);
    return task;
}

static void StopFixture(NSTask *task) {
    [[task.standardInput fileHandleForWriting] closeFile];
    [task waitUntilExit];
    CHECK(task.terminationStatus == 0);
}

static void TestNativeProcesses(NSString *fixturePath) {
    NSString *bundle = [[[fixturePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    CHECK([fixturePath hasPrefix:[bundle stringByAppendingString:@"/Contents/MacOS/"]]);
    char ownPath[PROC_PIDPATHINFO_MAXSIZE] = {0};
    CHECK(proc_pidpath(getpid(), ownPath, sizeof(ownPath)) > 0);
    NSString *executable = [NSString stringWithUTF8String:ownPath];
    NSArray *markers = @[@"--type=utility", @"--utility-sub-type=mirroring.mojom.MirroringService"];
    NSTask *fixture = StartFixture(fixturePath, markers, @{});
    CHECK(ChromecastBrowserHasMirroringChild(getpid(), executable, bundle));
    CHECK(!ChromecastBrowserHasMirroringChild(getpid(), @"/invalid/executable", bundle));
    CHECK(!ChromecastBrowserHasMirroringChild(getpid(), executable, [bundle stringByAppendingString:@"-lookalike"]));
    // A marked process is not its own child; ancestry remains required.
    CHECK(!ChromecastBrowserHasMirroringChild(fixture.processIdentifier, fixturePath, bundle));
    pid_t exitedPID = fixture.processIdentifier;
    StopFixture(fixture);
    CHECK(!ChromecastBrowserHasMirroringChild(getpid(), executable, bundle));
    CHECK(!ChromecastBrowserHasMirroringChild(exitedPID, fixturePath, bundle));
    fixture = StartFixture(fixturePath, @[@"--type=renderer", markers[1]], @{});
    CHECK(!ChromecastBrowserHasMirroringChild(getpid(), executable, bundle));
    StopFixture(fixture);
    fixture = StartFixture(fixturePath, @[@"--type=utility"], @{@"--utility-sub-type": @"mirroring.mojom.MirroringService"});
    CHECK(!ChromecastBrowserHasMirroringChild(getpid(), executable, bundle));
    StopFixture(fixture);
    CHECK(!ChromecastBrowserHasMirroringChild(-1, executable, bundle));
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        CHECK(argc == 2);
        TestArguments();
        TestLifecycle();
        TestNativeProcesses([[NSString stringWithUTF8String:argv[1]] stringByStandardizingPath]);
        ChromecastMonitor *live = [ChromecastMonitor new];
        NSArray *browsers = [live browserProcesses];
        // Read-only smoke scan: no Chrome control, shell, network or helper calls.
        BOOL detected = [live scanBrowserProcesses:browsers];
        printf("PASS: %lu checks; live browser count=%lu, mirroring=%s\n", atomic_load(&Checks),
               (unsigned long)browsers.count, detected ? "yes" : "no");
    }
    return 0;
}
