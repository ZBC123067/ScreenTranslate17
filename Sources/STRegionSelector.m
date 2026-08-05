#import "STRegionSelector.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface STRegionSelectionView : UIView
@property (nonatomic, assign) CGPoint start;
@property (nonatomic, assign) CGRect selected;
@property (nonatomic, strong) CAShapeLayer *maskLayer;
@property (nonatomic, strong) CAShapeLayer *borderLayer;
@property (nonatomic, copy) STRegionSelectionCompletion completion;
@property (nonatomic, assign) BOOL completed;
@end

@implementation STRegionSelectionView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
        _maskLayer = [CAShapeLayer layer];
        _maskLayer.fillRule = kCAFillRuleEvenOdd;
        self.layer.mask = _maskLayer;
        _borderLayer = [CAShapeLayer layer];
        _borderLayer.fillColor = UIColor.clearColor.CGColor;
        _borderLayer.strokeColor = UIColor.systemBlueColor.CGColor;
        _borderLayer.lineWidth = 2.0;
        _borderLayer.lineDashPattern = @[ @6, @4 ];
        [self.layer addSublayer:_borderLayer];

        UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(16, 48, frame.size.width - 32, 44)];
        hint.text = @"拖动框选翻译区域 · 点击左上角取消";
        hint.textAlignment = NSTextAlignmentCenter;
        hint.textColor = UIColor.whiteColor;
        hint.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
        hint.layer.cornerRadius = 10;
        hint.layer.masksToBounds = YES;
        hint.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self addSubview:hint];

        UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
        cancel.frame = CGRectMake(14, 100, 68, 36);
        [cancel setTitle:@"取消" forState:UIControlStateNormal];
        cancel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
        [cancel setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        cancel.layer.cornerRadius = 9;
        [cancel addTarget:self action:@selector(cancelled) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:cancel];
        [self updateMask];
    }
    return self;
}

- (void)finishWithRegion:(CGRect)region cancelled:(BOOL)cancelled {
    if (self.completed) return;
    self.completed = YES;
    STRegionSelectionCompletion completion = self.completion;
    self.completion = nil;
    [self removeFromSuperview];
    if (completion) completion(region, cancelled);
}
- (void)cancelled { [self finishWithRegion:CGRectZero cancelled:YES]; }
- (void)updateMask {
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:self.bounds];
    if (!CGRectIsEmpty(self.selected)) [path appendPath:[UIBezierPath bezierPathWithRoundedRect:self.selected cornerRadius:8]];
    self.maskLayer.path = path.CGPath;
    self.borderLayer.path = CGRectIsEmpty(self.selected) ? nil : [UIBezierPath bezierPathWithRoundedRect:self.selected cornerRadius:8].CGPath;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.start = [touches.anyObject locationInView:self];
    self.selected = CGRectZero;
    [self updateMask];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint point = [touches.anyObject locationInView:self];
    self.selected = CGRectMake(MIN(self.start.x, point.x), MIN(self.start.y, point.y), fabs(point.x - self.start.x), fabs(point.y - self.start.y));
    [self updateMask];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.selected.size.width >= 20.0 && self.selected.size.height >= 20.0) [self finishWithRegion:self.selected cancelled:NO];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self finishWithRegion:CGRectZero cancelled:YES];
}
@end

@implementation STRegionSelector
- (void)presentInView:(UIView *)view completion:(STRegionSelectionCompletion)completion {
    if (!view || CGRectIsEmpty(view.bounds)) { if (completion) completion(CGRectZero, YES); return; }
    STRegionSelectionView *selection = [[STRegionSelectionView alloc] initWithFrame:view.bounds];
    selection.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    selection.completion = completion;
    [view addSubview:selection];
}
@end
