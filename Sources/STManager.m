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
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) int preferenceNotificationToken;
@property (nonatomic, assign) CGRect continuousRegion;
@property (nonatomic, copy) NSString *lastVisualFingerprint;
@property (nonatomic, copy) NSString *lastRecognizedFingerprint;
@property (nonatomic, copy) NSString *lastContinuousText;
@property (nonatomic, assign) NSUInteger operationGeneration;
@property (nonatomic, assign) NSUInteger continuousRequestSerial;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *seenTexts;
@property (nonatomic, strong) NSMutableSet<NSString *> *chatInFlightKeys;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *chatRetryAfter;
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
        _seenTexts = [NSMutableOrderedSet orderedSet];
        _chatInFlightKeys = [NSMutableSet set];
        _chatRetryAfter = [NSMutableDictionary dictionary];
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
    [center addObserver:self selector:@selector(thermalStateChanged) name:NSProcessInfoThermalStateDidChangeNotification object:nil];
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

- (void)advanceOperationGeneration {
    self.operationGeneration = self.operationGeneration == NSUIntegerMax ? 1 : self.operationGeneration + 1;
}

- (NSUInteger)beginForegroundOperation {
    [self advanceOperationGeneration];
    self.translating = YES;
    [self.overlay setBusy:YES];
    return self.operationGeneration;
}

- (BOOL)contextIsCurrentForGeneration:(NSUInteger)generation pageIdentity:(NSString *)pageIdentity {
    if (!self.started || generation != self.operationGeneration || !pageIdentity.length) return NO;
    if (![pageIdentity isEqualToString:STCurrentPageIdentity()]) return NO;
    return ![STPrivacy isCurrentScreenSensitive];
}

- (BOOL)itemIsStillVisible:(STTextItem *)item {
    UIView *source = item.sourceView;
    if (!source) return YES;
    UIWindow *window = STActiveAppWindow();
    if (!window || source.window != window || source.hidden || source.alpha < 0.05) return NO;
    CGRect current = [source convertRect:source.bounds toView:window];
    if (!CGRectIntersectsRect(current, window.bounds)) return NO;
    return fabs(current.origin.x - item.frame.origin.x) < 4.0 && fabs(current.origin.y - item.frame.origin.y) < 4.0;
}

- (STTranslationEligibility)eligibilityForGeneration:(NSUInteger)generation pageIdentity:(NSString *)pageIdentity {
    __weak typeof(self) weakSelf = self;
    return ^BOOL {
        __strong typeof(weakSelf) self = weakSelf;
        return self && [self contextIsCurrentForGeneration:generation pageIdentity:pageIdentity];
    };
}

- (BOOL)isAutomaticWorkRestricted {
    return NSProcessInfo.processInfo.isLowPowerModeEnabled || NSProcessInfo.processInfo.thermalState >= NSProcessInfoThermalStateSerious;
}

- (void)pauseAutomaticWorkWithMessage:(BOOL)showMessage {
    BOOL wasActive = self.continuousActive || self.chatActive;
    [self setContinuous:NO announce:NO];
    [self setChat:NO announce:NO];
    if (showMessage && wasActive) [self.overlay showMessage:@"低电量模式或设备温度较高，已暂停自动翻译。"];
}

- (void)preferencesChanged {
    [STPreferences.shared reload];
    [self advanceOperationGeneration];
    self.translating = NO;
    [self.overlay setBusy:NO];
    [self.overlay clearTranslations];
    [self.overlay refreshForCurrentScene];
    if (!STPreferences.shared.enabled || [STPrivacy isCurrentBundleBlocked]) {
        [self stopTimers];
        [self.overlay setBallVisible:NO];
        return;
    }
    [self.overlay setBallVisible:STPreferences.shared.showFloatingBall];
    if (!STPreferences.shared.autoChatMode && self.chatActive) [self setChat:NO announce:NO];
    if ([self isAutomaticWorkRestricted]) [self pauseAutomaticWorkWithMessage:NO];
}

- (void)appActive {
    [STPreferences.shared reload];
    if (!STPreferences.shared.enabled || [STPrivacy isCurrentBundleBlocked]) return;
    [self.overlay setBallVisible:STPreferences.shared.showFloatingBall];
    if ([self isAutomaticWorkRestricted]) return;
    if (STPreferences.shared.autoChatMode && !self.chatActive) [self setChat:YES announce:NO];
}

- (void)appInactive {
    [self advanceOperationGeneration];
    self.translating = NO;
    [self stopTimers];
    [self.overlay setBusy:NO];
    [self.overlay clearTranslations];
}

- (void)refreshOverlay {
    [self advanceOperationGeneration];
    self.translating = NO;
    [self.overlay setBusy:NO];
    [self.overlay refreshForCurrentScene];
}

- (void)lowPowerModeChanged {
    if ([self isAutomaticWorkRestricted]) [self pauseAutomaticWorkWithMessage:YES];
}

- (void)thermalStateChanged {
    if ([self isAutomaticWorkRestricted]) [self pauseAutomaticWorkWithMessage:YES];
}

- (void)stopTimers {
    [self.continuousTimer invalidate];
    self.continuousTimer = nil;
    [self.chatTimer invalidate];
    self.chatTimer = nil;
    self.continuousActive = NO;
    self.chatActive = NO;
    self.lastVisualFingerprint = nil;
    self.lastRecognizedFingerprint = nil;
    self.lastContinuousText = nil;
    self.continuousRequestSerial++;
    [self.seenTexts removeAllObjects];
    [self.chatInFlightKeys removeAllObjects];
    [self.chatRetryAfter removeAllObjects];
}

- (NSTimer *)commonModeTimerWithInterval:(NSTimeInterval)interval selector:(SEL)selector {
    NSTimer *timer = [NSTimer timerWithTimeInterval:interval target:self selector:selector userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    return timer;
}

- (void)finishForegroundOperationForGeneration:(NSUInteger)generation pageIdentity:(NSString *)pageIdentity {
    if (generation != self.operationGeneration) return;
    self.translating = NO;
    [self.overlay setBusy:NO];
}

- (void)translateItems:(NSArray<STTextItem *> *)items clearExisting:(BOOL)clearExisting showEmptyMessage:(BOOL)showEmpty generation:(NSUInteger)generation pageIdentity:(NSString *)pageIdentity completion:(dispatch_block_t)completion {
    if (![self contextIsCurrentForGeneration:generation pageIdentity:pageIdentity]) { if (completion) completion(); return; }
    NSMutableArray<STTextItem *> *usable = [NSMutableArray array];
    for (STTextItem *item in items) {
        if (STLooksLikeTranslatableText(item.text, STPreferences.shared.targetLanguage)) [usable addObject:item];
        if (usable.count >= 18) break;
    }
    if (!usable.count) {
        if (showEmpty) [self.overlay showMessage:@"当前页面没有识别到可翻译文字。"];
        if (completion) completion();
        return;
    }
    if (clearExisting) [self.overlay clearTranslations];
    __block NSInteger pending = usable.count;
    __block BOOL receivedTranslation = NO;
    __block NSError *firstTranslationError;
    void (^finishOne)(void) = ^{
        pending--;
        if (pending != 0) return;
        if (!receivedTranslation && firstTranslationError && [self contextIsCurrentForGeneration:generation pageIdentity:pageIdentity]) {
            [self.overlay showMessage:firstTranslationError.localizedDescription ?: @"翻译失败，请检查服务配置和网络开关。"];
        }
        if (completion) completion();
    };
    STTranslationEligibility eligibility = [self eligibilityForGeneration:generation pageIdentity:pageIdentity];
    for (STTextItem *item in usable) {
        if (![self contextIsCurrentForGeneration:generation pageIdentity:pageIdentity]) { finishOne(); continue; }
        [[STTranslationService shared] translateText:item.text source:STPreferences.shared.sourceLanguage target:STPreferences.shared.targetLanguage bypassCache:NO eligibility:eligibility completion:^(NSString *translated, NSError *error) {
            if (translated.length) {
                receivedTranslation = YES;
                if ([self contextIsCurrentForGeneration:generation pageIdentity:pageIdentity] && [self itemIsStillVisible:item]) [self.overlay showTranslation:translated forItem:item];
            } else if (!firstTranslationError && error) {
                firstTranslationError = error;
            }
            finishOne();
        }];
    }
}

- (void)beginManualTranslationWithItems:(NSArray<STTextItem *> *)items clearExisting:(BOOL)clearExisting {
    if (self.translating) return;
    NSString *pageIdentity = STCurrentPageIdentity();
    NSUInteger generation = [self beginForegroundOperation];
    [self translateItems:items clearExisting:clearExisting showEmptyMessage:YES generation:generation pageIdentity:pageIdentity completion:^{
        [self finishForegroundOperationForGeneration:generation pageIdentity:pageIdentity];
    }];
}

- (BOOL)canTranslateCurrentScreen {
    if ([STPrivacy isCurrentScreenSensitive]) {
        [self.overlay showMessage:@"为保护隐私，此页面不会识别或翻译。"];
        return NO;
    }
    return YES;
}

- (void)translateScreenNativeFirst {
    if (self.translating || ![self canTranslateCurrentScreen]) return;
    NSArray<STTextItem *> *nativeItems = [[STTextScanner shared] scanVisibleText];
    if (nativeItems.count) { [self beginManualTranslationWithItems:nativeItems clearExisting:YES]; return; }
    if (!STPreferences.shared.enableOCR) { [self.overlay showMessage:@"未识别到原生文字，且 OCR 已关闭。"] ; return; }
    NSString *pageIdentity = STCurrentPageIdentity();
    NSUInteger generation = [self beginForegroundOperation];
    [[STOCRService shared] recognizeCurrentScreenInRegion:CGRectNull fast:NO completion:^(NSArray<STTextItem *> *items, NSError *error) {
        if (![self contextIsCurrentForGeneration:generation pageIdentity:pageIdentity]) return;
        if (error) [self.overlay showMessage:error.localizedDescription];
        [self translateItems:items clearExisting:YES showEmptyMessage:!error generation:generation pageIdentity:pageIdentity completion:^{
            [self finishForegroundOperationForGeneration:generation pageIdentity:pageIdentity];
        }];
    }];
}

- (void)translateCurrentScreenUsingOCR {
    if (self.translating || ![self canTranslateCurrentScreen]) return;
    NSString *pageIdentity = STCurrentPageIdentity();
    NSUInteger generation = [self beginForegroundOperation];
    [[STOCRService shared] recognizeCurrentScreenInRegion:CGRectNull fast:NO completion:^(NSArray<STTextItem *> *items, NSError *error) {
        if (![self contextIsCurrentForGeneration:generation pageIdentity:pageIdentity]) return;
        if (error) [self.overlay showMessage:error.localizedDescription];
        [self translateItems:items clearExisting:YES showEmptyMessage:!error generation:generation pageIdentity:pageIdentity completion:^{
            [self finishForegroundOperationForGeneration:generation pageIdentity:pageIdentity];
        }];
    }];
}

- (void)selectRegionWithCompletion:(void (^)(CGRect region, BOOL cancelled))completion {
    UIView *root = [self.overlay overlayRootView];
    [self.regionSelector presentInView:root completion:completion];
}

- (void)translateSelectedRegion {
    if (self.translating || ![self canTranslateCurrentScreen]) return;
    __weak typeof(self) weakSelf = self;
    [self selectRegionWithCompletion:^(CGRect region, BOOL cancelled) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || cancelled || self.translating || ![self canTranslateCurrentScreen]) return;
        NSString *pageIdentity = STCurrentPageIdentity();
        NSUInteger generation = [self beginForegroundOperation];
        [[STOCRService shared] recognizeCurrentScreenInRegion:region fast:NO completion:^(NSArray<STTextItem *> *items, NSError *error) {
            if (![self contextIsCurrentForGeneration:generation pageIdentity:pageIdentity]) return;
            if (error) [self.overlay showMessage:error.localizedDescription];
            [self translateItems:items clearExisting:YES showEmptyMessage:!error generation:generation pageIdentity:pageIdentity completion:^{
                [self finishForegroundOperationForGeneration:generation pageIdentity:pageIdentity];
            }];
        }];
    }];
}

- (void)setContinuous:(BOOL)enabled announce:(BOOL)announce {
    [self.continuousTimer invalidate];
    self.continuousTimer = nil;
    self.continuousActive = enabled;
    self.lastVisualFingerprint = nil;
    self.lastRecognizedFingerprint = nil;
    self.lastContinuousText = nil;
    self.continuousRequestSerial++;
    if (!enabled) { if (announce) [self.overlay showMessage:@"连续字幕翻译已关闭。"] ; return; }
    if ([self isAutomaticWorkRestricted]) {
        self.continuousActive = NO;
        [self.overlay showMessage:@"低电量模式或设备温度较高，无法启动连续字幕翻译。"];
        return;
    }
    NSTimeInterval interval = MAX(1.0, STPreferences.shared.continuousInterval);
    self.continuousTimer = [self commonModeTimerWithInterval:interval selector:@selector(continuousTimerFired:)];
    [self continuousTick];
    if (announce) [self.overlay showMessage:@"连续字幕翻译已开启。画面稳定后会识别所选区域。"];
}

- (void)startContinuousAfterSelectingRegion {
    if (self.continuousActive) { [self setContinuous:NO announce:YES]; return; }
    if (![self canTranslateCurrentScreen]) return;
    __weak typeof(self) weakSelf = self;
    [self selectRegionWithCompletion:^(CGRect region, BOOL cancelled) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || cancelled || ![self canTranslateCurrentScreen]) return;
        self.continuousRegion = region;
        [self setContinuous:YES announce:YES];
    }];
}

- (void)continuousTimerFired:(NSTimer *)timer { [self continuousTick]; }

- (void)continuousTick {
    if (!self.continuousActive || self.translating) return;
    if ([self isAutomaticWorkRestricted]) { [self pauseAutomaticWorkWithMessage:YES]; return; }
    if ([STPrivacy isCurrentScreenSensitive]) { [self setContinuous:NO announce:NO]; return; }
    NSUInteger generation = self.operationGeneration;
    NSString *pageIdentity = STCurrentPageIdentity();
    UIImage *image = [[STOCRService shared] captureCurrentAppWindow];
    if (!image || ![self contextIsCurrentForGeneration:generation pageIdentity:pageIdentity]) return;
    NSString *fingerprint = [[STOCRService shared] fingerprintForImage:image regionInImage:self.continuousRegion];
    if (!fingerprint.length || ![fingerprint isEqualToString:self.lastVisualFingerprint]) {
        self.lastVisualFingerprint = fingerprint;
        return;
    }
    if ([fingerprint isEqualToString:self.lastRecognizedFingerprint]) return;
    self.lastRecognizedFingerprint = fingerprint;
    NSUInteger serial = ++self.continuousRequestSerial;
    [[STOCRService shared] recognizeImage:image regionInImage:self.continuousRegion fast:YES completion:^(NSArray<STTextItem *> *items, NSError *error) {
        if (![self contextIsCurrentForGeneration:generation pageIdentity:pageIdentity] || !self.continuousActive || serial != self.continuousRequestSerial) return;
        if (error) { self.lastRecognizedFingerprint = nil; return; }
        NSMutableString *joined = [NSMutableString string];
        for (STTextItem *item in items) {
            if (joined.length) [joined appendString:@"\n"];
            [joined appendString:item.text];
            if (joined.length >= 1600) break;
        }
        NSString *text = STNormalizeText(joined);
        if (!text.length || [text isEqualToString:self.lastContinuousText]) return;
        [[STTranslationService shared] translateText:text source:STPreferences.shared.sourceLanguage target:STPreferences.shared.targetLanguage bypassCache:NO eligibility:[self eligibilityForGeneration:generation pageIdentity:pageIdentity] completion:^(NSString *translated, NSError *translationError) {
            if (![self contextIsCurrentForGeneration:generation pageIdentity:pageIdentity] || !self.continuousActive || serial != self.continuousRequestSerial) return;
            if (!translated.length) { self.lastRecognizedFingerprint = nil; return; }
            self.lastContinuousText = text;
            [self.overlay showSubtitle:translated original:text];
        }];
    }];
}

- (NSString *)chatKeyForItem:(STTextItem *)item {
    return STSHA256([NSString stringWithFormat:@"%@|%.0f|%.0f", item.text, item.frame.origin.x, item.frame.origin.y]);
}

- (void)rememberChatKey:(NSString *)key {
    if (!key.length || [self.seenTexts containsObject:key]) return;
    [self.seenTexts addObject:key];
    if (self.seenTexts.count > 800) [self.seenTexts removeObjectsInRange:NSMakeRange(0, self.seenTexts.count - 800)];
}

- (void)seedSeenChatTexts {
    for (STTextItem *item in [[STTextScanner shared] scanVisibleText]) [self rememberChatKey:[self chatKeyForItem:item]];
}

- (void)setChat:(BOOL)enabled announce:(BOOL)announce {
    [self.chatTimer invalidate];
    self.chatTimer = nil;
    self.chatActive = enabled;
    [self.seenTexts removeAllObjects];
    [self.chatInFlightKeys removeAllObjects];
    [self.chatRetryAfter removeAllObjects];
    if (!enabled) { if (announce) [self.overlay showMessage:@"自动聊天翻译已关闭。"] ; return; }
    if ([self isAutomaticWorkRestricted]) {
        self.chatActive = NO;
        if (announce) [self.overlay showMessage:@"低电量模式或设备温度较高，无法启动自动聊天翻译。"];
        return;
    }
    [self seedSeenChatTexts];
    self.chatTimer = [self commonModeTimerWithInterval:1.5 selector:@selector(chatTimerFired:)];
    if (announce) [self.overlay showMessage:@"自动聊天翻译已开启；只会翻译之后新出现的普通文本。"];
}

- (void)chatTimerFired:(NSTimer *)timer { [self chatTick]; }

- (void)chatTick {
    if (!self.chatActive || self.translating) return;
    if ([self isAutomaticWorkRestricted]) { [self pauseAutomaticWorkWithMessage:YES]; return; }
    if ([STPrivacy isCurrentScreenSensitive]) { [self setChat:NO announce:NO]; return; }
    NSUInteger generation = self.operationGeneration;
    NSString *pageIdentity = STCurrentPageIdentity();
    NSArray<STTextItem *> *items = [[STTextScanner shared] scanVisibleText];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSUInteger started = 0;
    for (STTextItem *item in items) {
        NSString *key = [self chatKeyForItem:item];
        if ([self.seenTexts containsObject:key] || [self.chatInFlightKeys containsObject:key] || [self.chatRetryAfter[key] doubleValue] > now) continue;
        [self.chatInFlightKeys addObject:key];
        started++;
        [[STTranslationService shared] translateText:item.text source:STPreferences.shared.sourceLanguage target:STPreferences.shared.targetLanguage bypassCache:NO eligibility:[self eligibilityForGeneration:generation pageIdentity:pageIdentity] completion:^(NSString *translated, NSError *error) {
            [self.chatInFlightKeys removeObject:key];
            if (![self contextIsCurrentForGeneration:generation pageIdentity:pageIdentity] || !self.chatActive) return;
            if (translated.length) {
                [self rememberChatKey:key];
                [self.chatRetryAfter removeObjectForKey:key];
                if ([self itemIsStillVisible:item]) [self.overlay showTranslation:translated forItem:item];
            } else {
                self.chatRetryAfter[key] = @(NSDate.date.timeIntervalSince1970 + 5.0);
            }
        }];
        if (started >= 4) break;
    }
}

- (void)translateInput {
    if (self.translating || ![self canTranslateCurrentScreen]) return;
    UIView<UITextInput> *input = [STInputHelper currentTextInput];
    NSString *text = STNormalizeText([STInputHelper textForInput:input]);
    if (!input || !text.length) { [self.overlay showMessage:@"请先点进普通输入框并输入文字。密码和验证码输入框不会被读取。"] ; return; }
    NSString *pageIdentity = STCurrentPageIdentity();
    NSUInteger generation = [self beginForegroundOperation];
    [[STTranslationService shared] translateText:text source:@"auto" target:@"en" bypassCache:NO eligibility:[self eligibilityForGeneration:generation pageIdentity:pageIdentity] completion:^(NSString *translated, NSError *error) {
        [self finishForegroundOperationForGeneration:generation pageIdentity:pageIdentity];
        if (![self contextIsCurrentForGeneration:generation pageIdentity:pageIdentity]) return;
        if (!translated.length) { [self.overlay showMessage:error.localizedDescription ?: @"输入翻译失败。"] ; return; }
        [self.overlay presentInputReplacementConfirmation:translated completion:^(BOOL replace) {
            if (replace && ![STInputHelper replaceInput:input withString:translated ifCurrentTextEquals:text]) [self.overlay showMessage:@"输入框已经改变，未替换文字。"];
        }];
    }];
}

- (void)showPluginSettingsInstructions {
    [self.overlay showMessage:@"请打开系统“设置”，在插件列表中选择 ScreenTranslate17。PreferenceLoader 的第三方设置页不能通过 iOS 的系统链接直接跳转。"];
}

- (void)performConfiguredAction:(NSString *)action {
    NSString *normalized = action.lowercaseString;
    if ([normalized isEqualToString:@"screen"]) [self translateScreenNativeFirst];
    else if ([normalized isEqualToString:@"ocr"]) [self translateCurrentScreenUsingOCR];
    else if ([normalized isEqualToString:@"region"]) [self translateSelectedRegion];
    else if ([normalized isEqualToString:@"continuous"]) [self startContinuousAfterSelectingRegion];
    else if ([normalized isEqualToString:@"chat"]) [self setChat:!self.chatActive announce:YES];
    else if ([normalized isEqualToString:@"input"]) [self translateInput];
    else if ([normalized isEqualToString:@"toggle_translations"]) [self.overlay toggleTranslations];
    else if ([normalized isEqualToString:@"settings"]) [self showPluginSettingsInstructions];
    else if (![normalized isEqualToString:@"none"]) [self.overlay showMessage:@"未识别的按钮动作。"];
}

- (void)overlayManagerDidRequestScreenTranslation:(STOverlayManager *)manager { [self translateScreenNativeFirst]; }
- (void)overlayManagerDidRequestOCRTranslation:(STOverlayManager *)manager { [self translateCurrentScreenUsingOCR]; }
- (void)overlayManagerDidRequestRegionTranslation:(STOverlayManager *)manager { [self translateSelectedRegion]; }
- (void)overlayManagerDidRequestToggleContinuous:(STOverlayManager *)manager { [self startContinuousAfterSelectingRegion]; }
- (void)overlayManagerDidRequestInputTranslation:(STOverlayManager *)manager { [self translateInput]; }
- (void)overlayManagerDidRequestToggleChatMode:(STOverlayManager *)manager { [self setChat:!self.chatActive announce:YES]; }
- (void)overlayManager:(STOverlayManager *)manager didRequestConfiguredAction:(NSString *)action { [self performConfiguredAction:action]; }
- (void)overlayManagerDidRequestControlPanel:(STOverlayManager *)manager { [self.overlay presentControlPanelWithContinuousActive:self.continuousActive chatActive:self.chatActive]; }
@end
