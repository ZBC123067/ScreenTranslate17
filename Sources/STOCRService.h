#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "STCommon.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^STOCRCompletion)(NSArray<STTextItem *> *items, NSError *_Nullable error);

@interface STOCRService : NSObject
+ (instancetype)shared;
- (nullable UIImage *)captureCurrentAppWindow;
- (NSString *)fingerprintForImage:(UIImage *)image regionInImage:(CGRect)region;
- (void)recognizeImage:(UIImage *)image regionInImage:(CGRect)region fast:(BOOL)fast completion:(STOCRCompletion)completion;
- (void)recognizeCurrentScreenInRegion:(CGRect)region fast:(BOOL)fast completion:(STOCRCompletion)completion;
@end

NS_ASSUME_NONNULL_END
