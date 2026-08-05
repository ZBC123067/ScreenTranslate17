#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "STCommon.h"

NS_ASSUME_NONNULL_BEGIN

@interface STTextScanner : NSObject
+ (instancetype)shared;
- (NSArray<STTextItem *> *)scanVisibleText;
@end

NS_ASSUME_NONNULL_END
