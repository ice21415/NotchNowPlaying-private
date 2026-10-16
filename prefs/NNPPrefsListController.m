#import "NNPPrefsListController.h"
#import <notify.h>

@implementation NNPPrefsListController

- (NSString *)plistName {
    NSString *name = [self.specifier propertyForKey:@"plistName"];
    return name.length ? name : @"Root";
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:[self plistName] target:self] mutableCopy];
        [self applyDependencies];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *name = self.specifier.name;
    self.title = name.length ? name : @"瀏海音樂播放器";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyDependencies];
    [self.table reloadData];
}

- (BOOL)boolPreferenceForKey:(NSString *)key fallback:(BOOL)fallback {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NNPPrefsDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)NNPPrefsDomain));
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

- (void)applyDependencies {
    for (PSSpecifier *specifier in _specifiers) {
        NSString *key = [specifier propertyForKey:@"dependsOn"];
        if (!key.length) continue;
        BOOL current = [self boolPreferenceForKey:key fallback:[[specifier propertyForKey:@"dependsDefault"] boolValue]];
        BOOL enabledWhen = [[specifier propertyForKey:@"dependsEnabledWhen"] boolValue];
        [specifier setProperty:@(current == enabledWhen) forKey:@"enabled"];
    }
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    [self applyDependencies];
    [self.table reloadData];
}

- (id)versionString:(__unused PSSpecifier *)specifier {
    NSBundle *bundle = [NSBundle bundleForClass:NNPPrefsListController.class];
    return [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"—";
}

- (void)resetAllSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"還原所有設定？"
        message:@"所有選項會回到預設值，耗電統計資料不會被刪除。" preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"還原" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        CFStringRef domain = (__bridge CFStringRef)NNPPrefsDomain;
        CFArrayRef keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (keys) {
            NSMutableArray *removable = [NSMutableArray array];
            for (NSString *key in (__bridge NSArray *)keys) {
                if (![key hasPrefix:@"SSHScreenshot"]) [removable addObject:key];
            }
            CFPreferencesSetMultiple(NULL, (__bridge CFArrayRef)removable, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            CFRelease(keys);
        }
        CFPreferencesAppSynchronize(domain);
        notify_post(NNPPrefsChangedNotification.UTF8String);
        [weakSelf reloadSpecifiers];
        [weakSelf applyDependencies];
        [weakSelf.table reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@implementation NNPRootListController
- (NSString *)plistName { return @"Root"; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"瀏海音樂播放器";
}
@end
