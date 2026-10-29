#import "../AWDLControl/AppDelegate.h"
#import "../AWDLControl/ChromecastMonitor.h"
#import <Network/Network.h>

// Exercise the real automatic-mode controller without starting the app or helper.
@interface AppDelegate (Testing)
- (void)updateAutoAWDLMode;
- (NSRunningApplication *)activeGame;
@end

@interface TestMonitor : ChromecastMonitor
@property BOOL testCasting;
@property BOOL running;
@end
@implementation TestMonitor
- (BOOL)isCasting { return self.testCasting; }
- (void)start { self.running = YES; }
- (void)stop {
    BOOL wasCasting = self.testCasting;
    self.running = NO;
    self.testCasting = NO;
    if (wasCasting) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ChromecastMonitorDidChangeNotification object:self];
    }
}
@end

@interface TestReachability : NSObject
@property nw_interface_type_t interfaceType;
@end
@implementation TestReachability
@end

@interface TestHelper : NSObject
@property NSMutableArray<NSNumber *> *requests;
- (id)remoteObjectProxy;
- (void)setAWDLEnabled:(BOOL)enabled;
@end
@implementation TestHelper
- (id)remoteObjectProxy { return self; }
- (void)setAWDLEnabled:(BOOL)enabled { [self.requests addObject:@(enabled)]; }
@end

@interface TestGame : NSObject
@property (getter=isActive) BOOL active;
@property (getter=isTerminated) BOOL terminated;
@property NSString *localizedName;
@property NSImage *icon;
@end
@implementation TestGame
@end

@interface TestAppDelegate : AppDelegate
@property TestGame *game;
@end
@implementation TestAppDelegate
- (NSRunningApplication *)activeGame { return (id)self.game; }
@end

static void Check(BOOL passed, NSString *message) {
    if (!passed) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(EXIT_FAILURE);
    }
}

int main(void) {
    @autoreleasepool {
        TestAppDelegate *delegate = [TestAppDelegate new];
        TestMonitor *monitor = [TestMonitor new];
        TestReachability *reachability = [TestReachability new];
        TestHelper *helper = [TestHelper new];
        helper.requests = [NSMutableArray new];
        NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
        [delegate setValue:monitor forKey:@"chromecastMonitor"];
        [delegate setValue:reachability forKey:@"reachability"];
        [delegate setValue:helper forKey:@"helperConnection"];
        [delegate setValue:status forKey:@"activeMenuItem"];
        [delegate setValue:@(-1) forKey:@"awdlEnabled"];
        [[NSNotificationCenter defaultCenter] addObserver:delegate selector:@selector(updateAutoAWDLMode)
            name:ChromecastMonitorDidChangeNotification object:monitor];

        // Persisted mode 0 remains automatic. No defaults are changed by this test.
        [delegate setValue:@0 forKey:@"awdlMode"];
        reachability.interfaceType = nw_interface_type_wifi;
        [delegate updateAutoAWDLMode];
        Check(monitor.running && helper.requests.lastObject.boolValue, @"Idle WiFi allows AWDL and starts detection");

        monitor.testCasting = YES;
        [delegate updateAutoAWDLMode];
        Check(!helper.requests.lastObject.boolValue, @"Casting with no foreground game disables AWDL");
        Check([status.title isEqualToString:@"Active for Chromecast"], @"Casting reason appears in menu");
        NSUInteger requestCount = helper.requests.count;
        [delegate updateAutoAWDLMode];
        Check(helper.requests.count == requestCount, @"Unchanged casting does not send redundant helper requests");

        delegate.game = [TestGame new];
        delegate.game.active = YES;
        delegate.game.localizedName = @"Test Game";
        [delegate updateAutoAWDLMode];
        monitor.testCasting = NO;
        [delegate updateAutoAWDLMode];
        Check(helper.requests.count == requestCount, @"Stopping casting keeps AWDL down for the active game");
        Check([status.title isEqualToString:@"Active for Test Game"], @"Game reason replaces casting reason");

        monitor.testCasting = YES;
        delegate.game.active = NO;
        delegate.game = nil;
        [delegate updateAutoAWDLMode];
        Check(helper.requests.count == requestCount, @"Leaving game keeps AWDL down during background casting");
        monitor.testCasting = NO;
        [delegate updateAutoAWDLMode];
        Check(helper.requests.lastObject.boolValue, @"Stopping both activities restores AWDL");

        monitor.testCasting = YES;
        [delegate updateAutoAWDLMode];
        reachability.interfaceType = nw_interface_type_wired;
        [delegate updateAutoAWDLMode];
        Check(!monitor.running && helper.requests.lastObject.boolValue, @"Ethernet releases AWDL and stops detection");
        Check([status.title isEqualToString:@"Connected via Ethernet"], @"Ethernet status remains accurate");
        reachability.interfaceType = nw_interface_type_other;
        [delegate updateAutoAWDLMode];
        Check(!monitor.running && helper.requests.lastObject.boolValue, @"Disconnected path allows AWDL");
        reachability.interfaceType = nw_interface_type_wifi;
        [delegate updateAutoAWDLMode];
        Check(monitor.running, @"Returning to WiFi restarts detection");

        for (NSNumber *manualMode in @[@1, @2]) {
            [delegate setValue:manualMode forKey:@"awdlMode"];
            monitor.testCasting = YES;
            requestCount = helper.requests.count;
            [delegate updateAutoAWDLMode];
            Check(!monitor.running && helper.requests.count == requestCount, @"Automatic events cannot override a manual mode");
        }
        [delegate setValue:@0 forKey:@"awdlMode"];
        [delegate updateAutoAWDLMode];
        Check(monitor.running, @"Returning to automatic restarts detection");

        [delegate setValue:nil forKey:@"helperConnection"];
        requestCount = helper.requests.count;
        [delegate updateAutoAWDLMode];
        Check(!monitor.running && helper.requests.count == requestCount, @"Missing helper stops detection without requests");

        [delegate setValue:helper forKey:@"helperConnection"];
        [delegate updateAutoAWDLMode];
        monitor.testCasting = YES;
        [delegate updateAutoAWDLMode];
        [delegate applicationWillTerminate:[NSNotification notificationWithName:NSApplicationWillTerminateNotification object:nil]];
        Check(!monitor.running, @"Stopping during termination cannot restart the monitor through its notification");
        puts("PASS: automatic-mode regression tests");
    }
    return EXIT_SUCCESS;
}
