#import "STPreferences.h"
#import "STCommon.h"
#import <notify.h>

@interface STPreferences ()
@property (nonatomic, copy) NSDictionary *values;
@end

@implementation STPreferences

+ (instancetype)shared {
    static STPreferences *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [STPreferences new];
        [instance reload];
    });
    return instance;
}

+ (NSDictionary *)defaultValues {
    return @{
        @"enabled": @YES,
        @"showFloatingBall": @YES,
        @"enableOCR": @YES,
        @"autoChatMode": @NO,
        @"shippingGlossary": @YES,
        @"redactSensitiveData": @YES,
        @"allowNetwork": @NO,
        @"continuousInterval": @1.5,
        @"cacheTTL": @(7 * 24 * 60 * 60),
        @"sourceLanguage": @"auto",
        @"targetLanguage": @"zh-CN",
        @"displayMode": @"overlay",
        @"provider": @"none",
        @"apiEndpoint": @"",
        @"apiKey": @"",
        @"apiModel": @"gpt-4.1-mini",
        @"apiRegion": @"",
        @"ballX": @0.88,
        @"ballY": @0.55,
        @"blockedBundleIDs": @[
            @"com.apple.Passbook", @"com.apple.MobileSMS.compose", @"com.apple.Preferences.Passwords",
            @"com.maybank2u.m2umobile", @"com.cimb.CIMBClicks", @"com.touchngo.ewallet",
            @"com.apple.AuthKitUIService", @"com.apple.MobilePhone"
        ]
    };
}

+ (NSSet<NSString *> *)allowedKeys {
    static NSSet<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ keys = [NSSet setWithArray:self.defaultValues.allKeys]; });
    return keys;
}

+ (NSString *)preferencesPath {
    return STJBRootPath(@"/var/mobile/Library/Preferences/com.wmm.screentranslate17.plist");
}

+ (NSMutableDictionary *)mutableStoredValues {
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:self.preferencesPath];
    return [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

+ (void)writeValue:(id)value forKey:(NSString *)key {
    if (!key.length || ![[self allowedKeys] containsObject:key]) return;
    NSMutableDictionary *values = [self mutableStoredValues];
    if (value) values[key] = value;
    else [values removeObjectForKey:key];
    NSString *directory = self.preferencesPath.stringByDeletingLastPathComponent;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    [values writeToFile:self.preferencesPath atomically:YES];
    notify_post(STPreferencesChangedDarwinNotification.UTF8String);
}

+ (void)resetAll {
    [[NSFileManager defaultManager] removeItemAtPath:self.preferencesPath error:nil];
    notify_post(STPreferencesChangedDarwinNotification.UTF8String);
}

- (void)reload {
    NSMutableDictionary *merged = [[STPreferences defaultValues] mutableCopy];
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:STPreferences.preferencesPath];
    if ([stored isKindOfClass:NSDictionary.class]) {
        for (NSString *key in STPreferences.allowedKeys) {
            id value = stored[key];
            if (value && value != [NSNull null]) merged[key] = value;
        }
    }
    self.values = merged;
}

- (id)valueForKey:(NSString *)key {
    return self.values[key];
}

- (BOOL)boolForKey:(NSString *)key { return [[self valueForKey:key] boolValue]; }
- (NSString *)stringForKey:(NSString *)key {
    id value = [self valueForKey:key];
    return [value isKindOfClass:NSString.class] ? value : @"";
}
- (BOOL)enabled { return [self boolForKey:@"enabled"]; }
- (BOOL)showFloatingBall { return [self boolForKey:@"showFloatingBall"]; }
- (BOOL)enableOCR { return [self boolForKey:@"enableOCR"]; }
- (BOOL)autoChatMode { return [self boolForKey:@"autoChatMode"]; }
- (BOOL)shippingGlossary { return [self boolForKey:@"shippingGlossary"]; }
- (BOOL)redactSensitiveData { return [self boolForKey:@"redactSensitiveData"]; }
- (BOOL)allowNetwork { return [self boolForKey:@"allowNetwork"]; }
- (NSTimeInterval)continuousInterval { return MAX(1.0, MIN(10.0, [[self valueForKey:@"continuousInterval"] doubleValue])); }
- (NSTimeInterval)cacheTTL { return MAX(0.0, MIN(30.0 * 24.0 * 60.0 * 60.0, [[self valueForKey:@"cacheTTL"] doubleValue])); }
- (NSString *)sourceLanguage { return [self stringForKey:@"sourceLanguage"]; }
- (NSString *)targetLanguage { return [self stringForKey:@"targetLanguage"]; }
- (NSString *)displayMode { return [self stringForKey:@"displayMode"]; }
- (NSString *)provider { return [self stringForKey:@"provider"]; }
- (NSString *)apiEndpoint { return [self stringForKey:@"apiEndpoint"]; }
- (NSString *)apiKey { return [self stringForKey:@"apiKey"]; }
- (NSString *)apiModel { return [self stringForKey:@"apiModel"]; }
- (NSString *)apiRegion { return [self stringForKey:@"apiRegion"]; }
- (NSArray<NSString *> *)blockedBundleIDs {
    id value = [self valueForKey:@"blockedBundleIDs"];
    return [value isKindOfClass:NSArray.class] ? value : @[];
}
@end
