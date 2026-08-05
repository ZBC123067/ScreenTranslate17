#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface STInputHelper : NSObject
+ (nullable UIView<UITextInput> *)currentTextInput;
+ (nullable NSString *)textForInput:(UIView<UITextInput> *)input;
+ (BOOL)replaceInput:(UIView<UITextInput> *)input withString:(NSString *)text ifCurrentTextEquals:(NSString *)expectedText;
@end
NS_ASSUME_NONNULL_END
