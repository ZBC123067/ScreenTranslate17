#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface STInputHelper : NSObject
+ (nullable UIView<UITextInput> *)currentTextInput;
+ (nullable NSString *)currentText;
+ (BOOL)replaceCurrentTextWithString:(NSString *)text;
@end
NS_ASSUME_NONNULL_END
