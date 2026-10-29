#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const ChromecastMonitorDidChangeNotification;

// Lifecycle, state reads and notifications are confined to the main thread.
@interface ChromecastMonitor : NSObject

@property (nonatomic, readonly, getter=isCasting) BOOL casting;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
