#import "STTextScanner.h"
#import "STPreferences.h"
#import "STPrivacy.h"
#import "STCommon.h"

@implementation STTextScanner

+ (instancetype)shared {
    static STTextScanner *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [STTextScanner new]; });
    return instance;
}

- (NSArray<STTextItem *> *)scanVisibleText {
    UIWindow *window = STActiveAppWindow();
    if (!window) return @[];
    NSMutableArray<STTextItem *> *items = [NSMutableArray array];
    NSMutableSet<NSString *> *dedupe = [NSMutableSet set];
    [self scanView:window inWindow:window output:items dedupe:dedupe depth:0];
    return [items sortedArrayUsingComparator:^NSComparisonResult(STTextItem *left, STTextItem *right) {
        if (fabs(left.frame.origin.y - right.frame.origin.y) > 8.0) return left.frame.origin.y < right.frame.origin.y ? NSOrderedAscending : NSOrderedDescending;
        return left.frame.origin.x < right.frame.origin.x ? NSOrderedAscending : NSOrderedDescending;
    }];
}

- (void)scanView:(UIView *)view inWindow:(UIWindow *)window output:(NSMutableArray<STTextItem *> *)output dedupe:(NSMutableSet<NSString *> *)dedupe depth:(NSUInteger)depth {
    if (!view || view.hidden || view.alpha < 0.05 || depth > 80 || output.count >= 120) return;
    if ([STPrivacy isSensitiveInputView:view]) return;
    CGRect frame = [view convertRect:view.bounds toView:window];
    if (!view.window || !CGRectIntersectsRect(frame, window.bounds)) return;

    NSString *text;
    if ([view isKindOfClass:UILabel.class]) text = ((UILabel *)view).text ?: ((UILabel *)view).attributedText.string;
    else if ([view isKindOfClass:UIButton.class]) text = [((UIButton *)view) titleForState:UIControlStateNormal] ?: ((UIButton *)view).currentTitle;
    else if ([view isKindOfClass:UITextView.class] && !view.isFirstResponder && !((UITextView *)view).editable) text = ((UITextView *)view).text;
    else if ([view isKindOfClass:UITextField.class] && !view.isFirstResponder && !((UITextField *)view).secureTextEntry) text = ((UITextField *)view).text.length ? ((UITextField *)view).text : ((UITextField *)view).placeholder;
    if (!text.length && view.isAccessibilityElement && !view.isFirstResponder) text = view.accessibilityLabel;
    text = STNormalizeText(text);

    if (STLooksLikeTranslatableText(text, STPreferences.shared.targetLanguage) && frame.size.width > 4.0 && frame.size.height > 4.0) {
        NSString *key = [NSString stringWithFormat:@"%@|%.0f|%.0f|%.0f|%.0f", text, frame.origin.x, frame.origin.y, frame.size.width, frame.size.height];
        if (![dedupe containsObject:key]) {
            [dedupe addObject:key];
            [output addObject:[STTextItem itemWithText:text frame:frame sourceView:view]];
        }
    }
    for (UIView *subview in view.subviews) [self scanView:subview inWindow:window output:output dedupe:dedupe depth:depth + 1];
}
@end
