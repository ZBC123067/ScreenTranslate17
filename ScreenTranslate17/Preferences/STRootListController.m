#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "../Sources/STPreferences.h"
#import "../Sources/STCache.h"

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
- (void)clearCache {
    [[STCache shared] clear];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已清除" message:@"翻译缓存已清空。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)resetAll {
    [STPreferences resetAll];
    [self reloadSpecifiers];
}
@end
