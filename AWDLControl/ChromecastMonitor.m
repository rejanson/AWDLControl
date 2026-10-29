#import "ChromecastMonitor.h"
#import "ChromecastProcess.h"

#import <AppKit/AppKit.h>

NSNotificationName const ChromecastMonitorDidChangeNotification = @"ChromecastMonitorDidChangeNotification";

@interface ChromecastMonitor () {
    BOOL _running;
    BOOL _scanInProgress;
    NSUInteger _generation;
    dispatch_source_t _timer;
    dispatch_queue_t _scanQueue;
}
@property (nonatomic, readwrite, getter=isCasting) BOOL casting;
@end

@implementation ChromecastMonitor

- (instancetype)init {
    self = [super init];
    if (self) {
        dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
        _scanQueue = dispatch_queue_create("com.jh.AWDLControl.chromecast", attributes);
    }
    return self;
}

- (void)dealloc {
    if (_timer) {
        dispatch_source_cancel(_timer);
    }
}

- (void)start {
    NSAssert([NSThread isMainThread], @"ChromecastMonitor must start on the main thread");
    if (_running) {
        return;
    }
    _running = YES;
    _generation++;
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC, NSEC_PER_SEC / 4);
    __weak ChromecastMonitor *weakSelf = self;
    dispatch_source_set_event_handler(_timer, ^{
        [weakSelf poll];
    });
    dispatch_resume(_timer);
}

- (void)stop {
    NSAssert([NSThread isMainThread], @"ChromecastMonitor must stop on the main thread");
    if (!_running) {
        return;
    }
    _running = NO;
    _generation++;
    dispatch_source_cancel(_timer);
    _timer = nil;
    [self updateCasting:NO];
}

- (void)updateCasting:(BOOL)casting {
    if (_casting != casting) {
        _casting = casting;
        [[NSNotificationCenter defaultCenter] postNotificationName:ChromecastMonitorDidChangeNotification object:self];
    }
}

// Snapshot AppKit objects on main; worker blocks receive immutable values only.
- (NSArray<NSDictionary *> *)browserProcesses {
    NSSet<NSString *> *identifiers = [NSSet setWithArray:@[
        @"com.google.Chrome", @"com.google.Chrome.beta", @"com.google.Chrome.dev",
        @"com.google.Chrome.canary", @"org.chromium.Chromium"
    ]];
    NSMutableArray<NSDictionary *> *browsers = [NSMutableArray array];
    for (NSRunningApplication *application in NSWorkspace.sharedWorkspace.runningApplications) {
        if (!application.terminated && application.bundleIdentifier
            && [identifiers containsObject:application.bundleIdentifier]
            && application.processIdentifier > 0 && application.executableURL.path && application.bundleURL.path) {
            [browsers addObject:@{
                @"pid": @(application.processIdentifier),
                @"executable": application.executableURL.path,
                @"bundle": application.bundleURL.path
            }];
        }
    }
    return [browsers copy];
}

- (BOOL)scanBrowserProcesses:(NSArray<NSDictionary *> *)browsers {
    for (NSDictionary *browser in browsers) {
        if (ChromecastBrowserHasMirroringChild([browser[@"pid"] intValue], browser[@"executable"], browser[@"bundle"])) {
            return YES;
        }
    }
    return NO;
}

- (void)poll {
    if (!_running || _scanInProgress) {
        return;
    }
    _scanInProgress = YES;
    NSUInteger generation = _generation;
    NSArray<NSDictionary *> *browsers = [self browserProcesses];
    dispatch_async(_scanQueue, ^{
        @autoreleasepool {
            BOOL casting = [self scanBrowserProcesses:browsers];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_scanInProgress = NO;
                if (!self->_running) {
                    return;
                }
                if (generation != self->_generation) {
                    // A restart waited for this old scan; begin a fresh snapshot.
                    [self poll];
                    return;
                }
                [self updateCasting:casting];
            });
        }
    });
}

@end
