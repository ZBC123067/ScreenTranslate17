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

+ (NSString *)preferencesLockPath {
    return [[self preferencesPath] stringByAppendingString:@".lock"];
}

+ (NSMutableDictionary *)mutableStoredValues {
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:self.preferencesPath];
    return [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

+ (NSString *)trimmedString:(id)value maximumLength:(NSUInteger)maximumLength {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length <= maximumLength ? trimmed : nil;
}

+ (id)normalizedValue:(id)value forKey:(NSString *)key {
    if (!value || value == NSNull.null) return nil;
    if ([key isEqualToString:@"enabled"] || [key isEqualToString:@"showFloatingBall"] || [key isEqualToString:@"enableOCR"] || [key isEqualToString:@"autoChatMode"] || [key isEqualToString:@"shippingGlossary"] || [key isEqualToString:@"redactSensitiveData"] || [key isEqualToString:@"allowNetwork"]) {
        return [value isKindOfClass:NSNumber.class] ? @([value boolValue]) : nil;
    }
    if ([key isEqualToString:@"continuousInterval"]) {
        return [value isKindOfClass:NSNumber.class] ? @(MAX(1.0, MIN(10.0, [value doubleValue]))) : nil;
    }
    if ([key isEqualToString:@"cacheTTL"]) {
        return [value isKindOfClass:NSNumber.class] ? @(MAX(0.0, MIN(30.0 * 24.0 * 60.0 * 60.0, [value doubleValue]))) : nil;
    }
    if ([key isEqualToString:@"ballX"] || [key isEqualToString:@"ballY"]) {
        return [value isKindOfClass:NSNumber.class] ? @(MAX(0.02, MIN(0.98, [value doubleValue]))) : nil;
    }
    if ([key isEqualToString:@"sourceLanguage"] || [key isEqualToString:@"targetLanguage"]) {
        NSString *language = [[self trimmedString:value maximumLength:32] lowercaseString];
        return language.length ? language : nil;
    }
    if ([key isEqualToString:@"provider"]) {
        NSString *provider = [[self trimmedString:value maximumLength:64] lowercaseString];
        return [@[ @"none", @"microsoft", @"deepl", @"openai_compatible" ] containsObject:provider] ? provider : nil;
    }
    if ([key isEqualToString:@"displayMode"]) {
        NSString *mode = [[self trimmedString:value maximumLength:32] lowercaseString];
        return [@[ @"overlay", @"bilingual", @"below" ] containsObject:mode] ? mode : nil;
    }
    if ([key isEqualToString:@"apiEndpoint"]) return [self trimmedString:value maximumLength:2048];
    if ([key isEqualToString:@"apiKey"]) return [self trimmedString:value maximumLength:4096];
    if ([key isEqualToString:@"apiModel"]) return [self trimmedString:value maximumLength:256];
    if ([key isEqualToString:@"apiRegion"]) return [self trimmedString:value maximumLength:128];
    if ([key isEqualToString:@"blockedBundleIDs"]) {
        if (![value isKindOfClass:NSArray.class] || [(NSArray *)value count] > 200) return nil;
        NSMutableArray<NSString *> *bundleIDs = [NSMutableArray array];
        for (id candidate in (NSArray *)value) {
            NSString *bundleID = [[self trimmedString:candidate maximumLength:255] lowercaseString];
            if (bundleID.length && ![bundleIDs containsObject:bundleID]) [bundleIDs addObject:bundleID];
        }
        return bundleIDs;
    }
    return nil;
}

+ (BOOL)shouldNotifyForKey:(NSString *)key {
    return ![key isEqualToString:@"ballX"] && ![key isEqualToString:@"ballY"];
}

+ (void)writeValue:(id)value forKey:(NSString *)key {
    if (!key.length || ![[self allowedKeys] containsObject:key]) return;
    id normalized = value ? [self normalizedValue:value forKey:key] : nil;
    if (value && !normalized) return;
    __block BOOL didWrite = NO;
    STWithFileLock(self.preferencesLockPath, ^{
        NSMutableDictionary *values = [self mutableStoredValues];
        if (normalized) values[key] = normalized;
        else [values removeObjectForKey:key];
        didWrite = [values writeToFile:self.preferencesPath atomically:YES];
        if (didWrite) [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0600 } ofItemAtPath:self.preferencesPath error:nil];
    });
    if (didWrite && [self shouldNotifyForKey:key]) notify_post(STPreferencesChangedDarwinNotification.UTF8String);
}

+ (void)resetAll {
    STWithFileLock(self.preferencesLockPath, ^{
        [[NSFileManager defaultManager] removeItemAtPath:self.preferencesPath error:nil];
    });
    notify_post(STPreferencesChangedDarwinNotification.UTF8String);
}

- (void)reload {
    NSMutableDictionary *merged = [[STPreferences defaultValues] mutableCopy];
    if ([[NSFileManager defaultManager] fileExistsAtPath:STPreferences.preferencesPath]) [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0600 } ofItemAtPath:STPreferences.preferencesPath error:nil];
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:STPreferences.preferencesPath];
    if ([stored isKindOfClass:NSDictionary.class]) {
        for (NSString *key in STPreferences.allowedKeys) {
            id value = [self.class normalizedValue:stored[key] forKey:key];
            if (value) merged[key] = value;
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
