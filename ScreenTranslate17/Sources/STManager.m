#import "STManager.h"
#import "STPreferences.h"
#import "STPrivacy.h"
#import "STTextScanner.h"
#import "STOCRService.h"
#import "STTranslationService.h"
#import "STRegionSelector.h"
#import "STInputHelper.h"
#import "STCommon.h"
#import <notify.h>
#import <math.h>

@interface STManager ()
@property (nonatomic, strong) STOverlayManager *overlay;
@property (nonatomic, strong) STRegionSelector *regionSelector;
@property (nonatomic, strong, nullable) NSTimer *continuousTimer;
@property (nonatomic, strong, nullable) NSTimer *chatTimer;
@property (nonatomic, assign) BOOL continuousActive;
@property (nonatomic, assign) BOOL chatActive;
@property (nonatomic, assign) BOOL translating;
@property (nonatomic, assign) BOOL continuousOCRInFlight;
@property (nonatomic, assign) BOOL chatOCRInFlight;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) int preferenceNotificationToken;
@property (nonatomic, assign) CGRect continuousRegion;
@property (nonatomic, copy) NSString *lastVisualFingerprint;
@property (nonatomic, copy) NSString *lastRecognizedFingerprint;
@property (nonatomic, copy) NSString *lastContinuousText;
@property (nonatomic, strong) NSMutableSet<NSString *> *seenTexts;
@property (nonatomic, assign) NSUInteger manualGeneration;
@property (nonatomic, assign) NSUInteger continuousGeneration;
@property (nonatomic, assign) NSUInteger chatGeneration;
@property (nonatomic, assign) NSUInteger chatTickCount;
@property (nonatomic, assign) NSTimeInterval lastContinuousErrorTime;
@property (nonatomic, assign) NSTimeInterval lastChatErrorTime;
@end

@implementation STManager

+ (instancetype)sharedManager {
    static STManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [STManager new]; });
    return manager;
}

- (instancetype)init {
    if ((self = [super init])) {
        _overlay = [STOverlayManager new];
        _overlay.delegate = self;
        _regionSelector = [STRegionSelector new];
        _seenTexts = [NSMutableSet set];
        _continuousRegion = CGRectNull;
    }
    return self;
}

- (void)scheduleStart {
    if (self.started) return;
    self.started = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(appActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(appInactive) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(appInactive) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(refreshOverlay) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    [center addObserver:self selector:@selector(lowPowerModeChanged) name:NSProcessInfoPowerStateDidChangeNotification object:nil];
    __weak typeof(self) weakSelf = self;
    notify_register_dispatch(STPreferencesChangedDarwinNotification.UTF8String, &_preferenceNotificationToken, dispatch_get_main_queue(), ^(int token) {
        [weakSelf preferencesChanged];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self appActive]; });
}

- (void)dealloc {
    if (_preferenceNotificationToken) notify_cancel(_preferenceNotificationToken);
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)preferencesChanged {
    [STPreferences.shared reload];
    [self refreshOverlay];
    if (!STPreferences.shared.enabled || [STPrivacy isCurrentBundleBlocked]) {
        [self stopTimers];
        [self.overlay clearTranslations];
        [self.overlay setBallVisible:NO];
        return;
    }
    [self.overlay setBallVisible:STPreferences.shared.showFloatingBall];
    if (!STPreferences.shared.autoChatMode && self.chatActive) [self setChat:NO announce:NO];
}

- (void)appActive {
    [STPreferences.shared reload];
    if (!STPreferences.shared.enabled || [STPrivacy isCurrentBundleBlocked]) return;
    [self.overlay setBallVisible:STPreferences.shared.showFloatingBall];
    if (STPreferences.shared.autoChatMode && !self.chatActive) [self setChat:YES announce:NO];
}

- (void)appInactive {
    self.manualGeneration += 1;
    [self stopTimers];
    self.translating = NO;
    [self.seenTexts removeAllObjects];
    [self.overlay setBusy:NO];
    [self.overlay clearTranslations];
}

- (void)refreshOverlay { [self.overlay refreshForCurrentScene]; }

- (void)lowPowerModeChanged {
    if (NSProcessInfo.processInfo.isLowPowerModeEnabled && self.continuousActive) [self setContinuous:NO announce:YES];
}

- (void)stopTimers {
    [self.continuousTimer invalidate];
    self.continuousTimer = nil;
    [self.chatTimer invalidate];
    self.chatTimer = nil;
    self.continuousActive = NO;
    self.chatActive = NO;
    self.continuousOCRInFlight = NO;
    self.chatOCRInFlight = NO;
    self.continuousGeneration += 1;
    self.chatGeneration += 1;
    self.lastVisualFingerprint = nil;
    self.lastRecognizedFingerprint = nil;
    [self.overlay updateModeStateContinuous:NO chatActive:NO];
}

- (NSArray<STTextItem *> *)preparedItemsForTranslation:(NSArray<STTextItem *> *)items {
    NSMutableArray<STTextItem *> *result = [NSMutableArray array];
    for (STTextItem *item in items) {
        if (!STLooksLikeTranslatableText(item.text, STPreferences.shared.targetLanguage)) continue;
        STTextItem *previous = result.lastObject;
        BOOL canMergeOCR = item.fromOCR && previous.fromOCR && previous.text.length + item.text.length < 1200;
        if (canMergeOCR) {
            CGFloat gap = CGRectGetMinY(item.frame) - CGRectGetMaxY(previous.frame);
            CGFloat overlap = MAX(0.0, MIN(CGRectGetMaxX(item.frame), CGRectGetMaxX(previous.frame)) - MAX(CGRectGetMinX(item.frame), CGRectGetMinX(previous.frame)));
            CGFloat minimumWidth = MAX(1.0, MIN(item.frame.size.width, previous.frame.size.width));
            BOOL aligned = overlap / minimumWidth > 0.28 || fabs(item.frame.origin.x - previous.frame.origin.x) < 28.0;
            CGFloat allowedGap = MAX(12.0, MAX(item.frame.size.height, previous.frame.size.height) * 0.90);
            if (gap >= -4.0 && gap <= allowedGap && aligned) {
                previous.text = [NSString stringWithFormat:@"%@ %@", previous.text, item.text];
                previous.frame = CGRectUnion(previous.frame, item.frame);
                continue;
            }
        }
        STTextItem *copy = [STTextItem itemWithText:item.text frame:item.frame sourceView:item.sourceView];
        copy.fromOCR = item.fromOCR;
        [result addObject:copy];
        if (result.count >= 24) break;
    }
    return result;
}

- (void)translateItems:(NSArray<STTextItem *> *)items
         clearExisting:(BOOL)clearExisting
       showEmptyMessage:(BOOL)showEmpty
               announce:(BOOL)announce
                  valid:(BOOL (^)(void))valid
             completion:(void (^)(NSUInteger successCount, NSError *_Nullable error))completion {
    NSArray<STTextItem *> *usable = [self preparedItemsForTranslation:items];
    if (!usable.count) {
        if (showEmptyMessage) [self.overlay showMessage:@"当前界面没有识别到可翻译文字。"];
        if (completion) completion(0, nil);
        return;
    }
    if (clearExisting) [self.overlay clearTranslations];
    if (announce) [self.overlay showStatus:[NSString stringWithFormat:@"识别到 %lu 段，正在翻译…", (unsigned long)usable.count] busy:YES autoHideAfter:0.0];
    __block NSInteger pending = usable.count;
    __block NSUInteger successCount = 0;
    __block NSError *firstError = nil;
    for (STTextItem *item in usable) {
        [[STTranslationService shared] translateText:item.text completion:^(NSString *translated, NSError *error) {
            BOOL stillValid = valid ? valid() : YES;
            if (stillValid && translated.length) {
                successCount += 1;
                [self.overlay showTranslation:translated forItem:item];
            } else if (error && !firstError) {
                firstError = error;
            }
            pending--;
            if (pending == 0) {
                if (stillValid && announce) {
                    if (successCount) [self.overlay showStatus:[NSString stringWithFormat:@"翻译完成 · %lu 段", (unsigned long)successCount] busy:NO autoHideAfter:2.2];
                    else [self.overlay showMessage:firstError.localizedDescription ?: @"没有获得译文，请检查翻译服务设置。"];
                }
                if (completion) completion(successCount, firstError);
            }
        }];
    }
}

- (void)beginManualTranslationWithItems:(NSArray<STTextItem *> *)items clearExisting:(BOOL)clearExisting {
    if (self.translating) return;
    self.translating = YES;
    NSUInteger generation = ++self.manualGeneration;
    [self.overlay setBusy:YES];
    __weak typeof(self) weakSelf = self;
    [self translateItems:items clearExisting:clearExisting showEmptyMessage:YES announce:YES valid:^BOOL{
        return weakSelf && generation == weakSelf.manualGeneration && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    } completion:^(NSUInteger successCount, NSError *error) {
        if (generation != self.manualGeneration) return;
        self.translating = NO;
        [self.overlay setBusy:NO];
    }];
}

- (void)performManualOCRInRegion:(CGRect)region status:(NSString *)status {
    if (self.translating) {
        [self.overlay showMessage:@"上一项翻译仍在进行，请稍候。"];
        return;
    }
    if (!STPreferences.shared.enableOCR) {
        [self.overlay showMessage:@"OCR 已关闭，请先在设置中开启。"];
        return;
    }
    self.translating = YES;
    NSUInteger generation = ++self.manualGeneration;
    [self.overlay setBusy:YES];
    [self.overlay showStatus:status busy:YES autoHideAfter:0.0];
    __weak typeof(self) weakSelf = self;
    [[STOCRService shared] recognizeCurrentScreenInRegion:region fast:NO completion:^(NSArray<STTextItem *> *items, NSError *error) {
        if (!weakSelf || generation != weakSelf.manualGeneration) return;
        if (error) {
            weakSelf.translating = NO;
            [weakSelf.overlay setBusy:NO];
            [weakSelf.overlay showMessage:error.localizedDescription ?: @"OCR 识别失败。"];
            return;
        }
        [weakSelf translateItems:items clearExisting:YES showEmptyMessage:YES announce:YES valid:^BOOL{
            return weakSelf && generation == weakSelf.manualGeneration && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
        } completion:^(NSUInteger successCount, NSError *translationError) {
            if (generation != weakSelf.manualGeneration) return;
            weakSelf.translating = NO;
            [weakSelf.overlay setBusy:NO];
        }];
    }];
}

- (void)translateScreenNativeFirst {
    if (self.translating) { [self.overlay showMessage:@"上一项翻译仍在进行，请稍候。"]; return; }
    if ([STPrivacy isCurrentScreenSensitive]) { [self.overlay showMessage:@"为保护隐私，此页面不会识别或翻译。"] ; return; }
    NSArray<STTextItem *> *nativeItems = [[STTextScanner shared] scanVisibleText];
    if (nativeItems.count >= 8 || (nativeItems.count && !STPreferences.shared.enableOCR)) {
        [self beginManualTranslationWithItems:nativeItems clearExisting:YES];
        return;
    }
    if (STPreferences.shared.enableOCR) {
        [self performManualOCRInRegion:CGRectNull status:(nativeItems.count ? @"原生文字较少，正在自动补充 OCR…" : @"正在截取屏幕并识别文字…")];
        return;
    }
    [self.overlay showMessage:@"未识别到原生文字，且 OCR 已关闭。"];
}

- (void)translateCurrentScreenUsingOCR {
    if (self.translating) { [self.overlay showMessage:@"上一项翻译仍在进行，请稍候。"]; return; }
    if ([STPrivacy isCurrentScreenSensitive]) { [self.overlay showMessage:@"为保护隐私，此页面不会识别或翻译。"] ; return; }
    [self performManualOCRInRegion:CGRectNull status:@"OCR 正在识别当前屏幕…"];
}

- (void)selectRegionWithCompletion:(void (^)(CGRect region, BOOL cancelled))completion {
    [self.overlay showStatus:@"拖动框选区域，松手后立即识别" busy:NO autoHideAfter:0.0];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *root = [self.overlay overlayRootView];
        [self.regionSelector presentInView:root completion:completion];
    });
}

- (void)translateSelectedRegion {
    if ([STPrivacy isCurrentScreenSensitive]) { [self.overlay showMessage:@"为保护隐私，此页面不会识别或翻译。"] ; return; }
    __weak typeof(self) weakSelf = self;
    [self selectRegionWithCompletion:^(CGRect region, BOOL cancelled) {
        if (cancelled) { [weakSelf.overlay showMessage:@"已取消框选。"]; return; }
        [weakSelf performManualOCRInRegion:region status:@"正在识别框选区域…"];
    }];
}

- (void)setContinuous:(BOOL)enabled announce:(BOOL)announce {
    [self.continuousTimer invalidate];
    self.continuousTimer = nil;
    self.continuousGeneration += 1;
    self.continuousOCRInFlight = NO;
    self.continuousActive = enabled;
    self.lastVisualFingerprint = nil;
    self.lastRecognizedFingerprint = nil;
    self.lastContinuousText = nil;
    if (!enabled) {
        [self.overlay updateModeStateContinuous:NO chatActive:self.chatActive];
        if (announce) [self.overlay showMessage:@"连续字幕翻译已关闭。"];
        return;
    }
    if (NSProcessInfo.processInfo.isLowPowerModeEnabled) {
        self.continuousActive = NO;
        [self.overlay updateModeStateContinuous:NO chatActive:self.chatActive];
        [self.overlay showMessage:@"低电量模式下不会启动连续字幕翻译。"];
        return;
    }
    NSTimeInterval interval = MAX(1.0, STPreferences.shared.continuousInterval);
    self.continuousTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(continuousTick) userInfo:nil repeats:YES];
    self.continuousTimer.tolerance = MIN(0.25, interval * 0.15);
    [self.overlay updateModeStateContinuous:YES chatActive:self.chatActive];
    [self continuousTick];
    if (announce) [self.overlay showStatus:@"连续字幕已开启，正在监听所选区域" busy:NO autoHideAfter:0.0];
}

- (void)startContinuousAfterSelectingRegion {
    if (self.continuousActive) { [self setContinuous:NO announce:YES]; return; }
    __weak typeof(self) weakSelf = self;
    [self selectRegionWithCompletion:^(CGRect region, BOOL cancelled) {
        if (cancelled) { [weakSelf.overlay showMessage:@"已取消连续字幕框选。"]; return; }
        weakSelf.continuousRegion = region;
        [weakSelf setContinuous:YES announce:YES];
    }];
}

- (void)continuousTick {
    if (!self.continuousActive || self.translating || self.continuousOCRInFlight) return;
    if ([STPrivacy isCurrentScreenSensitive]) {
        [self setContinuous:NO announce:NO];
        [self.overlay showMessage:@"检测到敏感页面，连续字幕已自动停止。"];
        return;
    }
    UIImage *image = [[STOCRService shared] captureCurrentAppWindow];
    if (!image) {
        [self.overlay showMessage:@"暂时无法截取当前应用画面，稍后会自动重试。"];
        return;
    }
    NSString *fingerprint = [[STOCRService shared] fingerprintForImage:image regionInImage:self.continuousRegion];
    if (!fingerprint.length) return;
    self.lastVisualFingerprint = fingerprint;
    if ([fingerprint isEqualToString:self.lastRecognizedFingerprint]) return;
    self.lastRecognizedFingerprint = fingerprint;
    self.continuousOCRInFlight = YES;
    NSUInteger generation = self.continuousGeneration;
    [[STOCRService shared] recognizeImage:image regionInImage:self.continuousRegion fast:YES completion:^(NSArray<STTextItem *> *items, NSError *error) {
        if (generation != self.continuousGeneration) return;
        self.continuousOCRInFlight = NO;
        if (!self.continuousActive) return;
        if (error) {
            self.lastRecognizedFingerprint = nil;
            NSTimeInterval now = NSDate.date.timeIntervalSince1970;
            if (now - self.lastContinuousErrorTime > 8.0) {
                self.lastContinuousErrorTime = now;
                [self.overlay showMessage:error.localizedDescription ?: @"连续字幕 OCR 失败，正在重试。"];
            }
            return;
        }
        NSMutableString *joined = [NSMutableString string];
        for (STTextItem *item in items) {
            if (joined.length) [joined appendString:@"\n"];
            [joined appendString:item.text];
            if (joined.length >= 1600) break;
        }
        NSString *text = STNormalizeText(joined);
        if (!text.length || [text isEqualToString:self.lastContinuousText]) {
            [self.overlay showStatus:@"连续字幕监听中" busy:NO autoHideAfter:0.0];
            return;
        }
        self.lastContinuousText = text;
        [[STTranslationService shared] translateText:text completion:^(NSString *translated, NSError *translationError) {
            if (generation != self.continuousGeneration || !self.continuousActive) return;
            if (translated.length) {
                [self.overlay showSubtitle:translated original:text];
                [self.overlay showStatus:@"连续字幕监听中 · 已更新" busy:NO autoHideAfter:0.0];
            } else {
                NSTimeInterval now = NSDate.date.timeIntervalSince1970;
                if (now - self.lastContinuousErrorTime > 8.0) {
                    self.lastContinuousErrorTime = now;
                    [self.overlay showMessage:translationError.localizedDescription ?: @"连续字幕翻译失败，正在重试。"];
                }
            }
        }];
    }];
}

- (NSUInteger)processChatItems:(NSArray<STTextItem *> *)items generation:(NSUInteger)generation {
    NSMutableArray<STTextItem *> *freshBottomUp = [NSMutableArray array];
    for (STTextItem *item in items.reverseObjectEnumerator) {
        if (!STLooksLikeTranslatableText(item.text, STPreferences.shared.targetLanguage)) continue;
        NSString *key = STSHA256(STNormalizeText(item.text));
        if (![self.seenTexts containsObject:key]) {
            [self.seenTexts addObject:key];
            [freshBottomUp addObject:item];
            if (freshBottomUp.count >= 4) break;
        }
    }
    if (!freshBottomUp.count) return 0;
    NSArray<STTextItem *> *fresh = freshBottomUp.reverseObjectEnumerator.allObjects;
    __weak typeof(self) weakSelf = self;
    [self translateItems:fresh clearExisting:NO showEmptyMessage:NO announce:NO valid:^BOOL{
        return weakSelf && weakSelf.chatActive && generation == weakSelf.chatGeneration;
    } completion:^(NSUInteger successCount, NSError *error) {
        if (!weakSelf || generation != weakSelf.chatGeneration || !weakSelf.chatActive) return;
        if (successCount) {
            [weakSelf.overlay showStatus:[NSString stringWithFormat:@"自动聊天监听中 · 新译 %lu 条", (unsigned long)successCount] busy:NO autoHideAfter:0.0];
        } else if (error) {
            NSTimeInterval now = NSDate.date.timeIntervalSince1970;
            if (now - weakSelf.lastChatErrorTime > 8.0) {
                weakSelf.lastChatErrorTime = now;
                [weakSelf.overlay showMessage:error.localizedDescription];
            }
        }
    }];
    return fresh.count;
}

- (void)setChat:(BOOL)enabled announce:(BOOL)announce {
    [self.chatTimer invalidate];
    self.chatTimer = nil;
    self.chatGeneration += 1;
    self.chatOCRInFlight = NO;
    self.chatTickCount = 0;
    self.chatActive = enabled;
    [self.seenTexts removeAllObjects];
    [self.overlay updateModeStateContinuous:self.continuousActive chatActive:enabled];
    if (!enabled) { if (announce) [self.overlay showMessage:@"自动聊天翻译已关闭。"]; return; }
    self.chatTimer = [NSTimer scheduledTimerWithTimeInterval:1.4 target:self selector:@selector(chatTick) userInfo:nil repeats:YES];
    self.chatTimer.tolerance = 0.2;
    [self chatTick];
    if (announce) [self.overlay showStatus:@"自动聊天已开启，正在监听新消息" busy:NO autoHideAfter:0.0];
}

- (void)chatTick {
    if (!self.chatActive || self.translating) return;
    if ([STPrivacy isCurrentScreenSensitive]) {
        [self setChat:NO announce:NO];
        [self.overlay showMessage:@"检测到敏感页面，自动聊天翻译已停止。"];
        return;
    }
    self.chatTickCount += 1;
    NSUInteger generation = self.chatGeneration;
    NSArray<STTextItem *> *items = [[STTextScanner shared] scanVisibleText];
    NSUInteger nativeFresh = [self processChatItems:items generation:generation];
    BOOL shouldUseOCR = STPreferences.shared.enableOCR && !self.chatOCRInFlight && (items.count < 2 || (nativeFresh == 0 && self.chatTickCount % 3 == 0));
    if (shouldUseOCR) {
        self.chatOCRInFlight = YES;
        [[STOCRService shared] recognizeCurrentScreenInRegion:CGRectNull fast:YES completion:^(NSArray<STTextItem *> *ocrItems, NSError *error) {
            if (generation != self.chatGeneration) return;
            self.chatOCRInFlight = NO;
            if (!self.chatActive) return;
            if (error) {
                NSTimeInterval now = NSDate.date.timeIntervalSince1970;
                if (now - self.lastChatErrorTime > 10.0) {
                    self.lastChatErrorTime = now;
                    [self.overlay showMessage:error.localizedDescription ?: @"聊天 OCR 暂时失败，稍后自动重试。"];
                }
                return;
            }
            [self processChatItems:ocrItems generation:generation];
        }];
    }
    if (self.seenTexts.count > 800) [self.seenTexts removeAllObjects];
}

- (void)translateInput {
    NSString *text = STNormalizeText([STInputHelper currentText]);
    if (!text.length) { [self.overlay showMessage:@"请先点进普通输入框并输入文字。密码和验证码输入框不会读取。"] ; return; }
    [self.overlay setBusy:YES];
    [[STTranslationService shared] translateText:text source:@"auto" target:@"en" completion:^(NSString *translated, NSError *error) {
        [self.overlay setBusy:NO];
        if (!translated.length) { [self.overlay showMessage:error.localizedDescription ?: @"输入翻译失败。"] ; return; }
        [self.overlay presentInputReplacementConfirmation:translated completion:^(BOOL replace) {
            if (replace && ![STInputHelper replaceCurrentTextWithString:translated]) [self.overlay showMessage:@"输入框已经改变，未替换文字。"];
        }];
    }];
}

- (void)overlayManagerDidRequestScreenTranslation:(STOverlayManager *)manager { [self translateScreenNativeFirst]; }
- (void)overlayManagerDidRequestOCRTranslation:(STOverlayManager *)manager { [self translateCurrentScreenUsingOCR]; }
- (void)overlayManagerDidRequestRegionTranslation:(STOverlayManager *)manager { [self translateSelectedRegion]; }
- (void)overlayManagerDidRequestToggleContinuous:(STOverlayManager *)manager { [self startContinuousAfterSelectingRegion]; }
- (void)overlayManagerDidRequestInputTranslation:(STOverlayManager *)manager { [self translateInput]; }
- (void)overlayManagerDidRequestToggleChatMode:(STOverlayManager *)manager { [self setChat:!self.chatActive announce:YES]; }
@end
