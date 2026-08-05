#import "STCache.h"
#import "STCommon.h"
#import "STPreferences.h"
#import <notify.h>

@interface STCache ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *entries;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) int cacheNotificationToken;
@end

@implementation STCache

+ (instancetype)shared {
    static STCache *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [STCache new]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.wmm.screentranslate17.cache", DISPATCH_QUEUE_SERIAL);
        _entries = [NSMutableDictionary dictionary];
        dispatch_sync(_queue, ^{
            STWithFileLock(self.cacheLockPath, ^{
                [self reloadFromDiskLocked];
                if ([self pruneLocked]) [self flushLocked];
                else if ([[NSFileManager defaultManager] fileExistsAtPath:self.cachePath]) [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0600 } ofItemAtPath:self.cachePath error:nil];
            });
        });
        __weak typeof(self) weakSelf = self;
        notify_register_dispatch(STCacheClearedDarwinNotification.UTF8String, &_cacheNotificationToken, _queue, ^(int token) {
            __strong typeof(weakSelf) self = weakSelf;
            [self clearLocked];
        });
    }
    return self;
}

- (NSString *)cachePath {
    return STJBRootPath(@"/var/mobile/Library/Preferences/com.wmm.screentranslate17.cache.plist");
}

- (NSString *)cacheLockPath {
    return [[self cachePath] stringByAppendingString:@".lock"];
}

- (NSString *)keyForText:(NSString *)text source:(NSString *)source target:(NSString *)target provider:(NSString *)provider {
    NSString *redactionState = STPreferences.shared.redactSensitiveData ? @"redaction-on" : @"redaction-off";
    return STSHA256([NSString stringWithFormat:@"%@\n%@\n%@\n%@\n%@", provider ?: @"", source ?: @"", target ?: @"", redactionState, text ?: @""]);
}

- (void)flushLocked {
    NSString *directory = self.cachePath.stringByDeletingLastPathComponent;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    [self.entries writeToFile:self.cachePath atomically:YES];
    [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0600 } ofItemAtPath:self.cachePath error:nil];
}

- (void)reloadFromDiskLocked {
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:self.cachePath];
    self.entries = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

- (BOOL)pruneLocked {
    NSTimeInterval ttl = STPreferences.shared.cacheTTL;
    NSTimeInterval cutoff = NSDate.date.timeIntervalSince1970 - ttl;
    NSMutableArray<NSString *> *expired = [NSMutableArray array];
    [self.entries enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *entry, BOOL *stop) {
        NSNumber *time = [entry isKindOfClass:NSDictionary.class] ? entry[@"time"] : nil;
        NSString *translation = [entry isKindOfClass:NSDictionary.class] ? entry[@"translation"] : nil;
        if (ttl <= 0 || ![time isKindOfClass:NSNumber.class] || ![translation isKindOfClass:NSString.class] || time.doubleValue < cutoff) [expired addObject:key];
    }];
    [self.entries removeObjectsForKeys:expired];
    return expired.count > 0;
}

- (NSString *)translationForText:(NSString *)text source:(NSString *)source target:(NSString *)target provider:(NSString *)provider {
    __block NSString *translation;
    dispatch_sync(self.queue, ^{
        [self pruneLocked];
        NSDictionary *entry = self.entries[[self keyForText:text source:source target:target provider:provider]];
        id value = [entry isKindOfClass:NSDictionary.class] ? entry[@"translation"] : nil;
        if ([value isKindOfClass:NSString.class]) translation = value;
    });
    return translation;
}

- (void)storeTranslation:(NSString *)translation forText:(NSString *)text source:(NSString *)source target:(NSString *)target provider:(NSString *)provider {
    if (!translation.length || !text.length || translation.length > 12000 || STPreferences.shared.cacheTTL <= 0) return;
    dispatch_async(self.queue, ^{
        STWithFileLock(self.cacheLockPath, ^{
            [self reloadFromDiskLocked];
            [self pruneLocked];
            NSString *key = [self keyForText:text source:source target:target provider:provider];
            self.entries[key] = @{ @"translation": translation, @"time": @(NSDate.date.timeIntervalSince1970) };
            if (self.entries.count > 900) {
                NSArray<NSString *> *oldest = [self.entries keysSortedByValueUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
                    return [left[@"time"] compare:right[@"time"]];
                }];
                NSUInteger count = self.entries.count - 750;
                [self.entries removeObjectsForKeys:[oldest subarrayWithRange:NSMakeRange(0, MIN(count, oldest.count))]];
            }
            [self flushLocked];
        });
    });
}

- (void)clearLocked {
    [self.entries removeAllObjects];
}

- (void)clear {
    dispatch_async(self.queue, ^{
        STWithFileLock(self.cacheLockPath, ^{
            [self clearLocked];
            [[NSFileManager defaultManager] removeItemAtPath:self.cachePath error:nil];
        });
        notify_post(STCacheClearedDarwinNotification.UTF8String);
    });
}

- (void)dealloc {
    if (_cacheNotificationToken) notify_cancel(_cacheNotificationToken);
}
@end
