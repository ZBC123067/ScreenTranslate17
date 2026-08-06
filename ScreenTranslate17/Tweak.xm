#import <UIKit/UIKit.h>
#import "Sources/STManager.h"

static BOOL STShouldRunInCurrentProcess(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundleID = bundle.bundleIdentifier.lowercaseString ?: @"";
    NSString *bundlePath = bundle.bundlePath.lowercaseString ?: @"";
    if (![bundlePath.pathExtension isEqualToString:@"app"] || [bundlePath containsString:@".appex/"]) return NO;
    if (!bundleID.length || [bundleID isEqualToString:@"com.apple.springboard"] || [bundleID hasPrefix:@"com.apple.webkit."]) return NO;
    if ([bundleID isEqualToString:@"com.wmm.screentranslate17.preferences"] || [bundleID isEqualToString:@"com.apple.authkituiservice"]) return NO;
    return NSClassFromString(@"UIApplication") != nil;
}

%ctor {
    @autoreleasepool {
        if (!STShouldRunInCurrentProcess()) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[STManager sharedManager] scheduleStart];
        });
    }
}
