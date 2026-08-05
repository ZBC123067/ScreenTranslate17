#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface STCache : NSObject
+ (instancetype)shared;
- (nullable NSString *)translationForText:(NSString *)text source:(NSString *)source target:(NSString *)target provider:(NSString *)provider;
- (void)storeTranslation:(NSString *)translation forText:(NSString *)text source:(NSString *)source target:(NSString *)target provider:(NSString *)provider;
- (void)clear;
@end

NS_ASSUME_NONNULL_END
