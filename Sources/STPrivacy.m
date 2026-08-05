#import "STPrivacy.h"
#import "STPreferences.h"
#import "STCommon.h"

@interface STPrivacy ()
+ (BOOL)view:(UIView *)view containsSensitiveContentWithTerms:(NSArray<NSString *> *)terms;
@end

@implementation STPreparedText
@end

@implementation STPrivacy

+ (BOOL)isCurrentBundleBlocked {
    NSString *bundleID = [[NSBundle mainBundle].bundleIdentifier lowercaseString] ?: @"";
    if (!bundleID.length) return YES;
    for (id blocked in STPreferences.shared.blockedBundleIDs) {
        if (![blocked isKindOfClass:NSString.class]) continue;
        NSString *candidate = [(NSString *)blocked lowercaseString];
        if ([bundleID isEqualToString:candidate] || [bundleID hasPrefix:[candidate stringByAppendingString:@"."]]) return YES;
    }
    NSArray<NSString *> *sensitiveTerms = @[ @"bank", @"banking", @"wallet", @"payment", @"finance", @"authenticator", @"token" ];
    for (NSString *term in sensitiveTerms) if ([bundleID containsString:term]) return YES;
    return NO;
}

+ (BOOL)isSensitiveInputView:(UIView *)view {
    if ([view isKindOfClass:UITextField.class]) return ((UITextField *)view).secureTextEntry;
    if ([view conformsToProtocol:@protocol(UITextInput)]) {
        for (UIView *subview in view.subviews) if ([self isSensitiveInputView:subview]) return YES;
    }
    NSString *label = [[NSString stringWithFormat:@"%@ %@ %@", view.accessibilityLabel ?: @"", view.accessibilityHint ?: @"", view.accessibilityValue ?: @""] lowercaseString];
    return [label containsString:@"password"] || [label containsString:@"passcode"] || [label containsString:@"verification code"] || [label containsString:@"验证码"] || [label containsString:@"密码"];
}

+ (BOOL)isCurrentScreenSensitive {
    UIWindow *window = STActiveAppWindow();
    if (!window) return YES;
    NSArray<NSString *> *terms = @[ @"password", @"passcode", @"verification code", @"one-time code", @"credit card", @"debit card", @"apple pay", @"wallet", @"face id", @"密码", @"验证码", @"银行卡", @"信用卡", @"钱包", @"支付", @"面容 id" ];
    return [self view:window containsSensitiveContentWithTerms:terms];
}

+ (BOOL)view:(UIView *)view containsSensitiveContentWithTerms:(NSArray<NSString *> *)terms {
    if (!view || view.hidden || view.alpha < 0.05) return NO;
    if ([self isSensitiveInputView:view]) return YES;
    NSString *text = [NSString stringWithFormat:@"%@ %@ %@", view.accessibilityLabel ?: @"", view.accessibilityHint ?: @"", view.accessibilityValue ?: @""];
    if ([view isKindOfClass:UILabel.class]) text = [text stringByAppendingFormat:@" %@", ((UILabel *)view).text ?: @""];
    else if ([view isKindOfClass:UITextField.class]) text = [text stringByAppendingFormat:@" %@ %@", ((UITextField *)view).placeholder ?: @"", ((UITextField *)view).secureTextEntry ? @"" : ((UITextField *)view).text ?: @""];
    else if ([view isKindOfClass:UITextView.class]) text = [text stringByAppendingFormat:@" %@", ((UITextView *)view).text ?: @""];
    else if ([view isKindOfClass:UIButton.class]) text = [text stringByAppendingFormat:@" %@", ((UIButton *)view).currentTitle ?: @""];
    NSString *lower = text.lowercaseString;
    for (NSString *term in terms) if ([lower containsString:term]) return YES;
    for (UIView *subview in view.subviews) if ([self view:subview containsSensitiveContentWithTerms:terms]) return YES;
    return NO;
}

+ (NSRegularExpression *)sensitiveDataExpression {
    static NSRegularExpression *expression;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *pattern = @"(?<![A-Z0-9])(?:[A-Z]{4}\\d{7}|(?:\\d[ -]?){13,19}\\d|\\+?\\d[\\d ()-]{7,}\\d|(?:B/L|BL|BOOKING|ACCOUNT|PASSPORT|ID)[\\s:#-]*[A-Z0-9-]{5,})(?![A-Z0-9])";
        expression = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return expression;
}

+ (BOOL)textContainsSensitiveData:(NSString *)text {
    if (!text.length) return NO;
    NSRange range = NSMakeRange(0, text.length);
    return [[self sensitiveDataExpression] firstMatchInString:text options:0 range:range] != nil;
}

+ (STPreparedText *)prepareTextForNetwork:(NSString *)text {
    STPreparedText *prepared = [STPreparedText new];
    prepared.text = text ?: @"";
    prepared.tokens = @{};
    if (!STPreferences.shared.redactSensitiveData || !text.length) return prepared;

    NSArray<NSTextCheckingResult *> *matches = [[self sensitiveDataExpression] matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!matches.count) return prepared;

    NSMutableString *working = [text mutableCopy];
    NSMutableDictionary<NSString *, NSString *> *tokens = [NSMutableDictionary dictionaryWithCapacity:matches.count];
    NSString *nonce = [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSUInteger index = 0;
    for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        NSString *original = [working substringWithRange:match.range];
        NSString *token = [NSString stringWithFormat:@"[[ST_PRIVATE_%@_%lu]]", nonce, (unsigned long)index++];
        while ([text containsString:token]) token = [token stringByAppendingString:@"_X"];
        tokens[token] = original;
        [working replaceCharactersInRange:match.range withString:token];
    }
    prepared.text = working;
    prepared.tokens = tokens;
    return prepared;
}

+ (NSString *)restoreTokensInText:(NSString *)text tokens:(NSDictionary<NSString *,NSString *> *)tokens {
    NSMutableString *result = [text mutableCopy] ?: [NSMutableString string];
    [tokens enumerateKeysAndObjectsUsingBlock:^(NSString *token, NSString *value, BOOL *stop) {
        [result replaceOccurrencesOfString:token withString:value options:0 range:NSMakeRange(0, result.length)];
    }];
    return result;
}

+ (NSDictionary<NSString *, NSString *> *)englishToChineseGlossary {
    return @{
        @"space confirmation": @"舱位确认", @"transshipment": @"中转", @"rollover": @"甩柜",
        @"gate in": @"进场", @"omission": @"跳港", @"shut out": @"未能装船",
        @"demurrage": @"滞箱费", @"detention": @"箱使费", @"free time": @"免箱期",
        @"release order": @"放箱指示", @"freight collect": @"运费到付", @"freight prepaid": @"运费预付",
        @"draft bl": @"提单草稿", @"surrender bl": @"电放提单", @"equipment": @"箱源",
        @"booking": @"订舱", @"vessel": @"船舶", @"voyage": @"航次"
    };
}

+ (NSString *)offlineGlossaryTranslationForText:(NSString *)text targetLanguage:(NSString *)targetLanguage {
    if (!STPreferences.shared.shippingGlossary) return nil;
    NSString *normalized = STNormalizeText(text).lowercaseString;
    if (!normalized.length || normalized.length > 80) return nil;
    NSDictionary<NSString *, NSString *> *map = [self englishToChineseGlossary];
    if ([targetLanguage.lowercaseString hasPrefix:@"zh"]) return map[normalized];
    if ([targetLanguage.lowercaseString hasPrefix:@"en"]) {
        __block NSString *match;
        [map enumerateKeysAndObjectsUsingBlock:^(NSString *english, NSString *chinese, BOOL *stop) {
            if ([normalized isEqualToString:chinese.lowercaseString]) { match = english; *stop = YES; }
        }];
        return match;
    }
    return nil;
}

+ (NSString *)shippingGlossaryInstructionForTargetLanguage:(NSString *)targetLanguage {
    if (!STPreferences.shared.shippingGlossary) return @"";
    if (![targetLanguage.lowercaseString hasPrefix:@"zh"]) return @"Preserve shipping and trade terminology accurately.";
    return @"For shipping context, use these Chinese terms where applicable: space confirmation=舱位确认; transshipment=中转; rollover=甩柜; gate in=进场; omission=跳港; shut out=未能装船; demurrage=滞箱费; detention=箱使费; free time=免箱期; release order=放箱指示; booking=订舱. Do not force a glossary term when the surrounding context has a different meaning.";
}
@end
