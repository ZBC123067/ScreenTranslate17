#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "../Sources/STPreferences.h"
#import "../Sources/STCache.h"
#import "../Sources/STTranslationService.h"

@interface STRootListController : PSListController
@end

@implementation STRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *stored = [STPreferences mutableStoredValues];
    return stored[specifier.properties[@"key"]] ?: specifier.properties[@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [STPreferences writeValue:value forKey:specifier.properties[@"key"]];
}
- (void)stClearTranslationCache {
    [[STCache shared] clear];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已清除" message:@"翻译缓存已清空。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)stTestTranslationService {
    [[STTranslationService shared] translateText:@"ScreenTranslate17 service test" source:@"en" target:@"zh-CN" bypassCache:YES eligibility:nil completion:^(NSString *translated, NSError *error) {
        NSString *message = translated.length ? [NSString stringWithFormat:@"测试成功：%@", translated] : (error.localizedDescription ?: @"测试失败。");
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:(translated.length ? @"翻译服务可用" : @"测试失败") message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
}
- (void)stResetAllSettings {
    [STPreferences resetAll];
    [[STCache shared] clear];
    [self reloadSpecifiers];
}
@end
