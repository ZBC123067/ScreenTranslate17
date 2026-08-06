#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^STTranslationCompletion)(NSString *_Nullable translatedText, NSError *_Nullable error);

@interface STTranslationService : NSObject
+ (instancetype)shared;
- (void)translateText:(NSString *)text completion:(STTranslationCompletion)completion;
- (void)translateText:(NSString *)text source:(NSString *)source target:(NSString *)target completion:(STTranslationCompletion)completion;
@end

NS_ASSUME_NONNULL_END
