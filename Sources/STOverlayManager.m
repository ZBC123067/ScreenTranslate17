#import "STOverlayManager.h"
#import "STPreferences.h"
#import "STCommon.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface STPassthroughWindow : UIWindow
@end

@implementation STPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self.rootViewController.view ? nil : hit;
}
@end

@interface STOverlayViewController : UIViewController
@end
@implementation STOverlayViewController
- (BOOL)prefersStatusBarHidden { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

@interface STTranslationCard : UIView
@property (nonatomic, strong) UIVisualEffectView *materialView;
@property (nonatomic, strong) UIVisualEffectView *vibrancyView;
@property (nonatomic, strong) UILabel *textLabel;
@property (nonatomic, strong) CAGradientLayer *highlightLayer;
@property (nonatomic, copy) NSString *displayText;
@property (nonatomic, assign) CGRect sourceFrame;
@property (nonatomic, assign) BOOL forceBelow;
- (CGSize)preferredSizeConstrainedToWidth:(CGFloat)width;
- (void)applyText:(NSString *)text font:(UIFont *)font;
@end

@implementation STTranslationCard

- (instancetype)init {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = UIColor.clearColor;
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
        _materialView = [[UIVisualEffectView alloc] initWithEffect:blur];
        _materialView.frame = self.bounds;
        _materialView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _materialView.clipsToBounds = YES;
        [self addSubview:_materialView];

        _vibrancyView = [[UIVisualEffectView alloc] initWithEffect:[UIVibrancyEffect effectForBlurEffect:blur]];
        _vibrancyView.frame = _materialView.bounds;
        _vibrancyView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_materialView.contentView addSubview:_vibrancyView];

        _textLabel = [UILabel new];
        _textLabel.numberOfLines = 0;
        _textLabel.textAlignment = NSTextAlignmentNatural;
        _textLabel.textColor = UIColor.labelColor;
        _textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _textLabel.frame = CGRectInset(_vibrancyView.bounds, 10.0, 7.0);
        _textLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_vibrancyView.contentView addSubview:_textLabel];

        _highlightLayer = [CAGradientLayer layer];
        _highlightLayer.colors = @[ (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.42].CGColor, (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.05].CGColor, (__bridge id)UIColor.clearColor.CGColor ];
        _highlightLayer.locations = @[ @0.0, @0.35, @1.0 ];
        _highlightLayer.startPoint = CGPointMake(0.0, 0.0);
        _highlightLayer.endPoint = CGPointMake(0.0, 1.0);
        [_materialView.contentView.layer addSublayer:_highlightLayer];

        self.layer.cornerRadius = 14.0;
        if (@available(iOS 13.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 0.75;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.32].CGColor;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.16;
        self.layer.shadowRadius = 9.0;
        self.layer.shadowOffset = CGSizeMake(0, 3);
        self.layer.masksToBounds = NO;
        _materialView.layer.cornerRadius = 14.0;
        _materialView.layer.masksToBounds = YES;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.highlightLayer.frame = self.materialView.bounds;
    self.textLabel.frame = CGRectInset(self.vibrancyView.bounds, 10.0, 7.0);
}

- (void)applyText:(NSString *)text font:(UIFont *)font {
    self.displayText = text ?: @"";
    self.textLabel.text = self.displayText;
    self.textLabel.font = font;
}

- (CGSize)preferredSizeConstrainedToWidth:(CGFloat)width {
    CGFloat contentWidth = MAX(60.0, width - 20.0);
    CGSize measured = [self.textLabel sizeThatFits:CGSizeMake(contentWidth, 142.0)];
    return CGSizeMake(width, MAX(32.0, MIN(156.0, ceil(measured.height) + 14.0)));
}
@end

@interface STOverlayManager ()
@property (nonatomic, strong) STPassthroughWindow *window;
@property (nonatomic, strong) UIView *translationContainer;
@property (nonatomic, strong) UIView *ball;
@property (nonatomic, strong) UILabel *ballLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) NSMutableDictionary<NSString *, STTranslationCard *> *translationCards;
@property (nonatomic, assign) BOOL translationsHidden;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) CGSize installedBoundsSize;
@end

@implementation STOverlayManager

- (instancetype)init {
    if ((self = [super init])) _translationCards = [NSMutableDictionary dictionary];
    return self;
}

- (void)installIfNeeded {
    UIWindow *appWindow = STActiveAppWindow();
    if (!appWindow) return;
    if (self.window && self.window.windowScene == appWindow.windowScene) return;
    [self.window resignKeyWindow];
    self.window.hidden = YES;
    self.window = nil;
    [self.translationCards removeAllObjects];

    STOverlayViewController *controller = [STOverlayViewController new];
    controller.view.backgroundColor = UIColor.clearColor;
    STPassthroughWindow *window = [[STPassthroughWindow alloc] initWithFrame:appWindow.bounds];
    if (@available(iOS 13.0, *)) window.windowScene = appWindow.windowScene;
    window.rootViewController = controller;
    window.backgroundColor = UIColor.clearColor;
    window.windowLevel = UIWindowLevelNormal + 1.0;
    window.hidden = NO;
    self.window = window;
    self.installedBoundsSize = appWindow.bounds.size;

    UIView *container = [[UIView alloc] initWithFrame:controller.view.bounds];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    container.backgroundColor = UIColor.clearColor;
    container.userInteractionEnabled = NO;
    [controller.view addSubview:container];
    self.translationContainer = container;
    [self buildFloatingBall];
    [self buildSubtitleLabel];
    [self setBallVisible:STPreferences.shared.showFloatingBall];
}

- (void)buildFloatingBall {
    const CGFloat size = 48.0;
    UIView *ball = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    ball.backgroundColor = [UIColor colorWithRed:0.20 green:0.48 blue:0.98 alpha:0.94];
    ball.layer.cornerRadius = size / 2.0;
    ball.layer.shadowColor = UIColor.blackColor.CGColor;
    ball.layer.shadowOpacity = 0.25;
    ball.layer.shadowRadius = 6.0;
    ball.layer.shadowOffset = CGSizeMake(0, 2);
    ball.accessibilityLabel = @"ScreenTranslate17 翻译按钮";

    UILabel *label = [[UILabel alloc] initWithFrame:ball.bounds];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.text = @"译";
    label.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    [ball addSubview:label];
    self.ballLabel = label;

    [self.window.rootViewController.view addSubview:ball];
    self.ball = ball;
    [self positionBallFromPreferences];

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(singleTapped:)];
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
    doubleTap.numberOfTapsRequired = 2;
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [ball addGestureRecognizer:singleTap];
    [ball addGestureRecognizer:doubleTap];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    longPress.minimumPressDuration = 0.55;
    [ball addGestureRecognizer:longPress];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(ballPanned:)];
    [ball addGestureRecognizer:pan];
}

- (void)positionBallFromPreferences {
    if (!self.ball) return;
    NSDictionary *stored = [STPreferences mutableStoredValues];
    CGFloat x = [stored[@"ballX"] doubleValue];
    CGFloat y = [stored[@"ballY"] doubleValue];
    if (x <= 0 || x > 1) x = 0.88;
    if (y <= 0 || y > 1) y = 0.55;
    CGFloat half = self.ball.bounds.size.width / 2.0;
    CGSize size = self.window.bounds.size;
    self.ball.center = CGPointMake(MAX(half, MIN(size.width - half, size.width * x)), MAX(70.0, MIN(size.height - 70.0, size.height * y)));
}

- (void)buildSubtitleLabel {
    UILabel *label = [UILabel new];
    label.hidden = YES;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.78];
    label.layer.cornerRadius = 10;
    label.layer.masksToBounds = YES;
    label.userInteractionEnabled = NO;
    [self.window.rootViewController.view addSubview:label];
    self.subtitleLabel = label;
}

- (void)singleTapped:(UITapGestureRecognizer *)gesture {
    if (!self.busy) [self.delegate overlayManagerDidRequestScreenTranslation:self];
}
- (void)doubleTapped:(UITapGestureRecognizer *)gesture { [self toggleTranslations]; }
- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) [self.delegate overlayManagerDidRequestControlPanel:self];
}

- (void)ballPanned:(UIPanGestureRecognizer *)gesture {
    UIView *ball = gesture.view;
    CGPoint delta = [gesture translationInView:self.window];
    ball.center = CGPointMake(ball.center.x + delta.x, ball.center.y + delta.y);
    [gesture setTranslation:CGPointZero inView:self.window];
    CGFloat half = ball.bounds.size.width / 2.0;
    ball.center = CGPointMake(MAX(half, MIN(self.window.bounds.size.width - half, ball.center.x)), MAX(70.0, MIN(self.window.bounds.size.height - 70.0, ball.center.y)));
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        CGFloat x = ball.center.x < self.window.bounds.size.width / 2.0 ? half + 5.0 : self.window.bounds.size.width - half - 5.0;
        [UIView animateWithDuration:0.2 animations:^{ ball.center = CGPointMake(x, ball.center.y); } completion:^(BOOL finished) {
            [STPreferences writeValue:@(ball.center.x / MAX(self.window.bounds.size.width, 1.0)) forKey:@"ballX"];
            [STPreferences writeValue:@(ball.center.y / MAX(self.window.bounds.size.height, 1.0)) forKey:@"ballY"];
        }];
    }
}

- (void)setBallVisible:(BOOL)visible {
    if (visible || self.window) [self installIfNeeded];
    self.ball.hidden = !visible;
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    self.ballLabel.text = busy ? @"…" : @"译";
    [self setStatusColor:(busy ? [UIColor colorWithRed:0.55 green:0.30 blue:0.95 alpha:0.95] : [UIColor colorWithRed:0.20 green:0.48 blue:0.98 alpha:0.94])];
}
- (void)setStatusColor:(UIColor *)color { self.ball.backgroundColor = color; }

- (NSString *)keyForItem:(STTextItem *)item {
    return [NSString stringWithFormat:@"%@|%.0f|%.0f|%.0f|%.0f", item.text, item.frame.origin.x, item.frame.origin.y, item.frame.size.width, item.frame.size.height];
}

- (CGRect)availableTranslationRect {
    UIEdgeInsets insets = self.window.safeAreaInsets;
    CGRect bounds = self.translationContainer.bounds;
    return UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(MAX(10.0, insets.top + 8.0), MAX(10.0, insets.left + 8.0), MAX(10.0, insets.bottom + 8.0), MAX(10.0, insets.right + 8.0)));
}

- (CGFloat)overlapArea:(CGRect)left right:(CGRect)right {
    CGRect intersection = CGRectIntersection(left, right);
    return CGRectIsNull(intersection) || CGRectIsEmpty(intersection) ? 0.0 : intersection.size.width * intersection.size.height;
}

- (CGRect)clampedFrame:(CGRect)frame within:(CGRect)available {
    CGFloat width = MIN(frame.size.width, available.size.width);
    CGFloat height = MIN(frame.size.height, available.size.height);
    return CGRectMake(MAX(CGRectGetMinX(available), MIN(CGRectGetMaxX(available) - width, frame.origin.x)), MAX(CGRectGetMinY(available), MIN(CGRectGetMaxY(available) - height, frame.origin.y)), width, height);
}

- (CGRect)bestFrameForCard:(STTranslationCard *)card excludingKey:(NSString *)key {
    CGRect available = [self availableTranslationRect];
    CGRect source = CGRectIntersection(card.sourceFrame, self.translationContainer.bounds);
    CGFloat preferredWidth = MIN(MAX(112.0, source.size.width + 18.0), MIN(available.size.width * 0.72, 310.0));
    CGSize preferredSize = [card preferredSizeConstrainedToWidth:preferredWidth];
    CGFloat exactWidth = MIN(MAX(56.0, source.size.width + 12.0), MIN(available.size.width * 0.55, 230.0));
    CGSize exactSize = [card preferredSizeConstrainedToWidth:exactWidth];
    BOOL canOverlaySource = exactSize.height <= MAX(36.0, source.size.height + 14.0) && source.size.width >= 42.0;
    canOverlaySource = canOverlaySource && !card.forceBelow;
    NSMutableArray<NSValue *> *candidates = [NSMutableArray array];
    if (canOverlaySource) [candidates addObject:[NSValue valueWithCGRect:CGRectMake(CGRectGetMidX(source) - exactSize.width / 2.0, CGRectGetMidY(source) - exactSize.height / 2.0, exactSize.width, exactSize.height)]];
    [candidates addObject:[NSValue valueWithCGRect:CGRectMake(CGRectGetMinX(source), CGRectGetMaxY(source) + 6.0, preferredSize.width, preferredSize.height)]];
    [candidates addObject:[NSValue valueWithCGRect:CGRectMake(CGRectGetMinX(source), CGRectGetMinY(source) - preferredSize.height - 6.0, preferredSize.width, preferredSize.height)]];
    [candidates addObject:[NSValue valueWithCGRect:CGRectMake(CGRectGetMaxX(source) + 6.0, CGRectGetMidY(source) - preferredSize.height / 2.0, preferredSize.width, preferredSize.height)]];
    [candidates addObject:[NSValue valueWithCGRect:CGRectMake(CGRectGetMinX(source) - preferredSize.width - 6.0, CGRectGetMidY(source) - preferredSize.height / 2.0, preferredSize.width, preferredSize.height)]];

    CGRect best = CGRectZero;
    CGFloat bestScore = CGFLOAT_MAX;
    NSValue *firstCandidate = candidates.firstObject;
    for (NSValue *value in candidates) {
        CGRect candidate = [self clampedFrame:value.CGRectValue within:available];
        CGFloat score = hypot(CGRectGetMidX(candidate) - CGRectGetMidX(source), CGRectGetMidY(candidate) - CGRectGetMidY(source)) * 0.15;
        if (!canOverlaySource || !CGRectEqualToRect(value.CGRectValue, firstCandidate.CGRectValue)) score += [self overlapArea:candidate right:source] * 0.18;
        for (NSString *existingKey in self.translationCards) {
            if ([existingKey isEqualToString:key]) continue;
            score += [self overlapArea:candidate right:self.translationCards[existingKey].frame] * 1.6;
        }
        if (!self.ball.hidden) score += [self overlapArea:candidate right:self.ball.frame] * 3.0;
        if (!self.subtitleLabel.hidden) score += [self overlapArea:candidate right:self.subtitleLabel.frame] * 1.4;
        if (score < bestScore) { bestScore = score; best = candidate; }
    }
    return best;
}

- (void)relayoutTranslationCards {
    NSArray<NSString *> *keys = [self.translationCards.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        STTranslationCard *first = self.translationCards[left];
        STTranslationCard *second = self.translationCards[right];
        if (fabs(first.sourceFrame.origin.y - second.sourceFrame.origin.y) > 8.0) return first.sourceFrame.origin.y < second.sourceFrame.origin.y ? NSOrderedAscending : NSOrderedDescending;
        return first.sourceFrame.origin.x < second.sourceFrame.origin.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (NSString *key in keys) self.translationCards[key].frame = [self bestFrameForCard:self.translationCards[key] excludingKey:key];
}

- (void)showTranslation:(NSString *)translation forItem:(STTextItem *)item {
    if (!translation.length || !item) return;
    [self installIfNeeded];
    NSString *key = [self keyForItem:item];
    STTranslationCard *card = self.translationCards[key];
    if (!card) {
        if (self.translationCards.count >= 80) return;
        card = [STTranslationCard new];
        card.userInteractionEnabled = NO;
        [self.translationContainer addSubview:card];
        self.translationCards[key] = card;
    }
    NSString *mode = STPreferences.shared.displayMode;
    NSString *displayText = translation;
    if ([mode isEqualToString:@"bilingual"]) {
        displayText = [NSString stringWithFormat:@"%@\n%@", item.text, translation];
    }
    card.sourceFrame = item.frame;
    card.forceBelow = [mode isEqualToString:@"below"] || [mode isEqualToString:@"bilingual"];
    CGFloat fontSize = [mode isEqualToString:@"bilingual"] ? 14.0 : 15.0;
    [card applyText:displayText font:[UIFont systemFontOfSize:fontSize weight:UIFontWeightMedium]];
    card.hidden = self.translationsHidden;
    [self relayoutTranslationCards];
}

- (void)showSubtitle:(NSString *)translation original:(NSString *)original {
    [self installIfNeeded];
    self.subtitleLabel.text = (original.length && [STPreferences.shared.displayMode isEqualToString:@"bilingual"]) ? [NSString stringWithFormat:@"%@\n%@", original, translation] : translation;
    CGFloat width = MIN(self.window.bounds.size.width - 32.0, 640.0);
    CGSize fit = [self.subtitleLabel sizeThatFits:CGSizeMake(width - 24.0, 160.0)];
    CGFloat height = MAX(48.0, MIN(160.0, fit.height + 20.0));
    self.subtitleLabel.frame = CGRectMake((self.window.bounds.size.width - width) / 2.0, self.window.bounds.size.height - height - 90.0, width, height);
    self.subtitleLabel.hidden = self.translationsHidden;
}

- (void)clearTranslations {
    for (STTranslationCard *card in self.translationCards.allValues) [card removeFromSuperview];
    [self.translationCards removeAllObjects];
    self.subtitleLabel.text = nil;
    self.subtitleLabel.hidden = YES;
}
- (void)toggleTranslations {
    self.translationsHidden = !self.translationsHidden;
    for (STTranslationCard *card in self.translationCards.allValues) card.hidden = self.translationsHidden;
    self.subtitleLabel.hidden = self.translationsHidden || !self.subtitleLabel.text.length;
}

- (UIViewController *)presentationController {
    return STTopViewController() ?: self.window.rootViewController;
}

- (void)showMessage:(NSString *)message {
    UIViewController *controller = [self presentationController];
    if (!controller || controller.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ScreenTranslate17" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

- (void)presentControlPanelWithContinuousActive:(BOOL)continuousActive chatActive:(BOOL)chatActive {
    UIViewController *controller = [self presentationController];
    if (!controller || controller.presentedViewController) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"ScreenTranslate17" message:@"选择操作" preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"翻译当前界面" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self.delegate overlayManagerDidRequestScreenTranslation:self]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"OCR 翻译当前屏幕" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self.delegate overlayManagerDidRequestOCRTranslation:self]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"框选区域翻译" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self.delegate overlayManagerDidRequestRegionTranslation:self]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:(continuousActive ? @"停止连续字幕" : @"选择区域并开启连续字幕") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self.delegate overlayManagerDidRequestToggleContinuous:self]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:(chatActive ? @"关闭自动聊天翻译" : @"开启自动聊天翻译") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self.delegate overlayManagerDidRequestToggleChatMode:self]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"翻译输入内容" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self.delegate overlayManagerDidRequestInputTranslation:self]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"显示 / 隐藏译文" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self toggleTranslations]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"清除当前译文" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self clearTranslations]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.ball;
        sheet.popoverPresentationController.sourceRect = self.ball.bounds;
    }
    [controller presentViewController:sheet animated:YES completion:nil];
}

- (void)presentInputReplacementConfirmation:(NSString *)translation completion:(void (^)(BOOL))completion {
    UIViewController *controller = [self presentationController];
    if (!controller || controller.presentedViewController) { if (completion) completion(NO); return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认填入译文" message:translation preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { if (completion) completion(NO); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"替换输入框文字" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { if (completion) completion(YES); }]];
    [controller presentViewController:alert animated:YES completion:nil];
}

- (void)refreshForCurrentScene {
    [self installIfNeeded];
    UIWindow *appWindow = STActiveAppWindow();
    if (appWindow) {
        self.window.frame = appWindow.bounds;
        if (!CGSizeEqualToSize(self.installedBoundsSize, appWindow.bounds.size)) {
            self.installedBoundsSize = appWindow.bounds.size;
            [self clearTranslations];
        }
    }
    [self positionBallFromPreferences];
    [self relayoutTranslationCards];
    if (self.subtitleLabel.text.length) [self showSubtitle:self.subtitleLabel.text original:nil];
}

- (UIView *)overlayRootView {
    [self installIfNeeded];
    return self.window.rootViewController.view;
}
@end
