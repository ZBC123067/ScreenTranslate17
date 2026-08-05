#import "STCommon.h"
#import <CommonCrypto/CommonDigest.h>
#import <roothide.h>
#import <fcntl.h>
#import <sys/file.h>
#import <unistd.h>

NSString * const STPreferencesChangedDarwinNotification = @"com.wmm.screentranslate17/preferencesChanged";
NSString * const STCacheClearedDarwinNotification = @"com.wmm.screentranslate17/cacheCleared";
NSString * const STPreferenceDomain = @"com.wmm.screentranslate17";

NSString *STJBRootPath(NSString *relativePath) {
    return jbroot(relativePath ?: @"/");
}

void STWithFileLock(NSString *lockPath, dispatch_block_t block) {
    if (!block) return;
    NSString *directory = lockPath.stringByDeletingLastPathComponent;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    int descriptor = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
    if (descriptor < 0) { block(); return; }
    if (flock(descriptor, LOCK_EX) == 0) {
        block();
        flock(descriptor, LOCK_UN);
    } else {
        block();
    }
    close(descriptor);
}

UIWindow *STActiveAppWindow(void) {
    UIApplication *application = UIApplication.sharedApplication;
    for (UIScene *scene in application.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows.reverseObjectEnumerator) {
            NSString *className = NSStringFromClass(window.class);
            if (!window.hidden && window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal && ![className hasPrefix:@"ST"]) {
                if (window.isKeyWindow) return window;
            }
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows.reverseObjectEnumerator) {
            NSString *className = NSStringFromClass(window.class);
            if (!window.hidden && window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal && ![className hasPrefix:@"ST"]) return window;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in application.windows.reverseObjectEnumerator) {
        NSString *className = NSStringFromClass(window.class);
        if (!window.hidden && window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal && ![className hasPrefix:@"ST"]) return window;
    }
#pragma clang diagnostic pop
    return nil;
}

UIViewController *STTopViewController(void) {
    UIWindow *window = STActiveAppWindow();
    UIViewController *controller = window.rootViewController;
    while (controller) {
        if (controller.presentedViewController) controller = controller.presentedViewController;
        else if ([controller isKindOfClass:UINavigationController.class]) controller = ((UINavigationController *)controller).visibleViewController;
        else if ([controller isKindOfClass:UITabBarController.class]) controller = ((UITabBarController *)controller).selectedViewController;
        else break;
    }
    return controller;
}

NSString *STCurrentPageIdentity(void) {
    UIWindow *window = STActiveAppWindow();
    UIViewController *controller = STTopViewController();
    if (!window || !controller) return @"";
    NSString *sceneID = @"";
    if (@available(iOS 13.0, *)) sceneID = window.windowScene.session.persistentIdentifier ?: @"";
    return [NSString stringWithFormat:@"%@|%p|%@", sceneID, controller, NSStringFromClass(controller.class)];
}

NSString *STNormalizeText(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray<NSString *> *lines = [trimmed componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString *> *cleanLines = [NSMutableArray arrayWithCapacity:lines.count];
    for (NSString *line in lines) {
        NSString *clean = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (clean.length) [cleanLines addObject:clean];
    }
    return [cleanLines componentsJoinedByString:@"\n"];
}

BOOL STContainsCJK(NSString *text) {
    __block BOOL found = NO;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        unichar character = [substring characterAtIndex:0];
        if ((character >= 0x3400 && character <= 0x4DBF) || (character >= 0x4E00 && character <= 0x9FFF)) {
            found = YES;
            *stop = YES;
        }
    }];
    return found;
}

BOOL STLooksLikeTranslatableText(NSString *text, NSString *targetLanguage) {
    NSString *normalized = STNormalizeText(text);
    if (normalized.length < 2 || normalized.length > 4000) return NO;
    if ([normalized rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound) return NO;
    if ([targetLanguage.lowercaseString hasPrefix:@"zh"] && STContainsCJK(normalized)) {
        NSUInteger cjkCount = 0;
        for (NSUInteger index = 0; index < normalized.length; index++) {
            unichar character = [normalized characterAtIndex:index];
            if ((character >= 0x3400 && character <= 0x4DBF) || (character >= 0x4E00 && character <= 0x9FFF)) cjkCount++;
        }
        if ((double)cjkCount / MAX((double)normalized.length, 1.0) > 0.30) return NO;
    }
    return YES;
}

NSString *STSHA256(NSString *string) {
    NSData *data = [(string ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) [result appendFormat:@"%02x", digest[index]];
    return result;
}

NSError *STMakeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:STPreferenceDomain code:code userInfo:@{ NSLocalizedDescriptionKey: message ?: @"操作失败" }];
}

void STDispatchMain(dispatch_block_t block) {
    if (!block) return;
    if (NSThread.isMainThread) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

@implementation STTextItem
+ (instancetype)itemWithText:(NSString *)text frame:(CGRect)frame sourceView:(UIView *)view {
    STTextItem *item = [STTextItem new];
    item.text = text ?: @"";
    item.frame = frame;
    item.sourceView = view;
    return item;
}
@end
