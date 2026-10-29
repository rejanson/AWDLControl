#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// KERN_PROCARGS2 contains argc, executable path, padding, argv, then environment.
// Only complete argv entries count; neither the path nor environment is searched.
BOOL ChromecastArgumentsIndicateMirroring(const void * _Nullable bytes, size_t length);

// Inspect only same-user direct children whose executable is inside this bundle.
BOOL ChromecastBrowserHasMirroringChild(pid_t browserPID,
                                       NSString *browserExecutablePath,
                                       NSString *browserBundlePath);

NS_ASSUME_NONNULL_END
