#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>

#define KZ_DOMAIN @"com.minis.kztheme"

@interface KZRootListController : PSListController
@end

@implementation KZRootListController

- (id)specifiers {
    if (_specifiers == nil) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] retain];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                                 (__bridge CFStringRef)KZ_DOMAIN);
        CFPreferencesAppSynchronize((__bridge CFStringRef)KZ_DOMAIN);
    }
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id v = nil;
    if (key) {
        v = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                            (__bridge CFStringRef)KZ_DOMAIN);
    }
    if (!v) v = [specifier propertyForKey:@"default"];
    return v;
}

- (void)applyNow {
    CFPreferencesAppSynchronize((__bridge CFStringRef)KZ_DOMAIN);
    notify_post("com.minis.kztheme.changed");

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已应用"
                                                              message:@"素材已经写入挂载目录。现在开始录屏就能看到效果；如果没变化，去 Dopamine 点一次「注销」。"
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end