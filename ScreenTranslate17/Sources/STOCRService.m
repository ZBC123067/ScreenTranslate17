#import "STOCRService.h"
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>

@implementation STOCRService

+ (instancetype)shared {
    static STOCRService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [STOCRService new]; });
    return instance;
}

- (UIImage *)captureCurrentAppWindow {
    __block UIImage *image;
    void (^capture)(void) = ^{
        UIWindow *window = STActiveAppWindow();
        if (!window || CGRectIsEmpty(window.bounds)) return;
        UIGraphicsBeginImageContextWithOptions(window.bounds.size, NO, UIScreen.mainScreen.scale);
        CGContextRef context = UIGraphicsGetCurrentContext();
        if (!context) { UIGraphicsEndImageContext(); return; }
        if (![window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES]) [window.layer renderInContext:context];
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    };
    if (NSThread.isMainThread) capture();
    else dispatch_sync(dispatch_get_main_queue(), capture);
    return image;
}

- (CGRect)effectiveRegion:(CGRect)region image:(UIImage *)image {
    CGRect imageBounds = (CGRect){ CGPointZero, image.size };
    if (CGRectIsNull(region) || CGRectIsEmpty(region)) return imageBounds;
    return CGRectIntersection(region, imageBounds);
}

- (NSString *)fingerprintForImage:(UIImage *)image regionInImage:(CGRect)region {
    if (!image.CGImage) return @"";
    CGRect effective = [self effectiveRegion:region image:image];
    if (CGRectIsEmpty(effective)) return @"";
    CGFloat scale = image.scale ?: 1.0;
    CGRect pixels = CGRectIntegral(CGRectMake(effective.origin.x * scale, effective.origin.y * scale, effective.size.width * scale, effective.size.height * scale));
    CGRect pixelBounds = CGRectMake(0.0, 0.0, CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage));
    pixels = CGRectIntersection(pixels, pixelBounds);
    if (CGRectIsEmpty(pixels)) return @"";
    CGImageRef cropped = CGImageCreateWithImageInRect(image.CGImage, pixels);
    if (!cropped) return @"";
    const size_t width = 24, height = 24;
    uint8_t bytes[width * height];
    memset(bytes, 0, sizeof(bytes));
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(bytes, width, height, 8, width, colorSpace, kCGImageAlphaNone);
    if (context) {
        CGContextSetInterpolationQuality(context, kCGInterpolationLow);
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), cropped);
        CGContextRelease(context);
    }
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(cropped);
    NSData *data = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    return STSHA256([data base64EncodedStringWithOptions:0]);
}

- (void)recognizeCurrentScreenInRegion:(CGRect)region fast:(BOOL)fast completion:(STOCRCompletion)completion {
    UIImage *image = [self captureCurrentAppWindow];
    if (!image) {
        STDispatchMain(^{ if (completion) completion(@[], STMakeError(100, @"无法截取当前应用画面。")); });
        return;
    }
    [self recognizeImage:image regionInImage:region fast:fast completion:completion];
}

- (void)recognizeImage:(UIImage *)image regionInImage:(CGRect)region fast:(BOOL)fast completion:(STOCRCompletion)completion {
    if (!image.CGImage) {
        STDispatchMain(^{ if (completion) completion(@[], STMakeError(101, @"图片格式不受支持。")); });
        return;
    }
    CGRect effective = [self effectiveRegion:region image:image];
    if (CGRectIsEmpty(effective)) {
        STDispatchMain(^{ if (completion) completion(@[], STMakeError(102, @"选择区域为空。")); });
        return;
    }
    CGFloat scale = image.scale ?: 1.0;
    CGRect pixels = CGRectIntegral(CGRectMake(effective.origin.x * scale, effective.origin.y * scale, effective.size.width * scale, effective.size.height * scale));
    CGRect pixelBounds = CGRectMake(0.0, 0.0, CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage));
    pixels = CGRectIntersection(pixels, pixelBounds);
    if (CGRectIsEmpty(pixels)) {
        STDispatchMain(^{ if (completion) completion(@[], STMakeError(103, @"选择区域超出当前画面。")); });
        return;
    }
    CGImageRef cropped = CGImageCreateWithImageInRect(image.CGImage, pixels);
    if (!cropped) {
        STDispatchMain(^{ if (completion) completion(@[], STMakeError(103, @"无法裁剪识别区域。")); });
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __block NSArray<STTextItem *> *recognized = @[];
        __block NSError *requestError;
        VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *error) {
            requestError = error;
            if (error) return;
            NSMutableArray<STTextItem *> *items = [NSMutableArray array];
            for (VNRecognizedTextObservation *observation in request.results) {
                VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
                NSString *text = STNormalizeText(candidate.string);
                if (!text.length) continue;
                CGRect box = observation.boundingBox;
                CGRect frame = CGRectMake(effective.origin.x + box.origin.x * effective.size.width,
                                          effective.origin.y + (1.0 - box.origin.y - box.size.height) * effective.size.height,
                                          box.size.width * effective.size.width,
                                          box.size.height * effective.size.height);
                STTextItem *item = [STTextItem itemWithText:text frame:CGRectInset(frame, -2.0, -2.0) sourceView:nil];
                item.fromOCR = YES;
                [items addObject:item];
            }
            recognized = [items sortedArrayUsingComparator:^NSComparisonResult(STTextItem *left, STTextItem *right) {
                if (fabs(left.frame.origin.y - right.frame.origin.y) > 8.0) return left.frame.origin.y < right.frame.origin.y ? NSOrderedAscending : NSOrderedDescending;
                return left.frame.origin.x < right.frame.origin.x ? NSOrderedAscending : NSOrderedDescending;
            }];
        }];
        request.recognitionLevel = fast ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = !fast;
        request.minimumTextHeight = fast ? 0.014 : 0.008;
        if (@available(iOS 16.0, *)) request.automaticallyDetectsLanguage = YES;
        NSArray<NSString *> *preferredLanguages = @[ @"en-US", @"zh-Hans", @"zh-Hant", @"ms-MY", @"id-ID", @"ja-JP", @"ko-KR", @"vi-VN", @"th-TH" ];
        NSError *languageError = nil;
        NSArray<NSString *> *supportedLanguages = [VNRecognizeTextRequest supportedRecognitionLanguagesForTextRecognitionLevel:request.recognitionLevel revision:request.revision error:&languageError];
        if (supportedLanguages.count) {
            NSMutableArray<NSString *> *availableLanguages = [NSMutableArray array];
            for (NSString *language in preferredLanguages) {
                if ([supportedLanguages containsObject:language]) [availableLanguages addObject:language];
            }
            if (availableLanguages.count) request.recognitionLanguages = availableLanguages;
        }
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cropped orientation:kCGImagePropertyOrientationUp options:@{}];
        NSError *performError;
        [handler performRequests:@[ request ] error:&performError];
        CGImageRelease(cropped);
        NSError *error = performError ?: requestError;
        STDispatchMain(^{ if (completion) completion(recognized, error); });
    });
}
@end
