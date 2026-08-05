#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface STPreferences : NSObject
+ (instancetype)shared;
- (void)reload;

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL showFloatingBall;
@property (nonatomic, readonly) BOOL enableOCR;
@property (nonatomic, readonly) BOOL autoChatMode;
@property (nonatomic, readonly) BOOL shippingGlossary;
@property (nonatomic, readonly) BOOL redactSensitiveData;
@property (nonatomic, readonly) BOOL allowNetwork;
@property (nonatomic, readonly) NSTimeInterval continuousInterval;
@property (nonatomic, readonly) NSTimeInterval cacheTTL;
@property (nonatomic, readonly) NSString *sourceLanguage;
@property (nonatomic, readonly) NSString *targetLanguage;
@property (nonatomic, readonly) NSString *displayMode;
@property (nonatomic, readonly) NSString *provider;
@property (nonatomic, readonly) NSString *apiEndpoint;
@property (nonatomic, readonly) NSString *apiKey;
@property (nonatomic, readonly) NSString *apiModel;
@property (nonatomic, readonly) NSString *apiRegion;
@property (nonatomic, readonly) NSArray<NSString *> *blockedBundleIDs;

+ (NSDictionary *)defaultValues;
+ (NSString *)preferencesPath;
+ (NSMutableDictionary *)mutableStoredValues;
+ (void)writeValue:(nullable id)value forKey:(NSString *)key;
+ (void)resetAll;
@end

NS_ASSUME_NONNULL_END
