#import "STInputHelper.h"
#import "STCommon.h"
#import "STPrivacy.h"

@implementation STInputHelper
+ (UIView<UITextInput> *)findInputInView:(UIView *)view {
    if ([view conformsToProtocol:@protocol(UITextInput)] && view.isFirstResponder && ![STPrivacy isSensitiveInputView:view]) return (UIView<UITextInput> *)view;
    for (UIView *subview in view.subviews) {
        UIView<UITextInput> *found = [self findInputInView:subview];
        if (found) return found;
    }
    return nil;
}
+ (UIView<UITextInput> *)currentTextInput {
    UIWindow *window = STActiveAppWindow();
    return window ? [self findInputInView:window] : nil;
}
+ (NSString *)textForInput:(UIView<UITextInput> *)input {
    if (!input) return nil;
    if ([input isKindOfClass:UITextView.class]) return ((UITextView *)input).text;
    if ([input isKindOfClass:UITextField.class]) return ((UITextField *)input).text;
    UITextRange *range = [input textRangeFromPosition:input.beginningOfDocument toPosition:input.endOfDocument];
    return range ? [input textInRange:range] : nil;
}
+ (BOOL)replaceInput:(UIView<UITextInput> *)input withString:(NSString *)text ifCurrentTextEquals:(NSString *)expectedText {
    if (!text.length) return NO;
    if (!input || input.window != STActiveAppWindow() || [STPrivacy isSensitiveInputView:input]) return NO;
    if (![STNormalizeText([self textForInput:input]) isEqualToString:STNormalizeText(expectedText)]) return NO;
    UITextRange *all = [input textRangeFromPosition:input.beginningOfDocument toPosition:input.endOfDocument];
    if (!all) return NO;
    [input replaceRange:all withText:text];
    if ([input isKindOfClass:UITextView.class]) [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:input];
    else if ([input isKindOfClass:UITextField.class]) [(UIControl *)input sendActionsForControlEvents:UIControlEventEditingChanged];
    return YES;
}
@end
