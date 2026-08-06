#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface STPreparedText : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *tokens;
@end

@interface STPrivacy : NSObject
+ (BOOL)isCurrentBundleBlocked;
+ (BOOL)isCurrentScreenSensitive;
+ (BOOL)isSensitiveInputView:(UIView *)view;
+ (STPreparedText *)prepareTextForNetwork:(NSString *)text;
+ (NSString *)restoreTokensInText:(NSString *)text tokens:(NSDictionary<NSString *, NSString *> *)tokens;
+ (nullable NSString *)offlineGlossaryTranslationForText:(NSString *)text targetLanguage:(NSString *)targetLanguage;
+ (NSString *)shippingGlossaryInstructionForTargetLanguage:(NSString *)targetLanguage;
@end

NS_ASSUME_NONNULL_END
