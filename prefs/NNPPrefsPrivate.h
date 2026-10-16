#pragma once
#import <UIKit/UIKit.h>

// Minimal declarations of the private Preferences.framework classes this bundle subclasses.
// The classes are resolved at load time inside the Settings app.
@interface PSSpecifier : NSObject
@property(nonatomic, strong) NSString *name;
@property(nonatomic, strong) NSDictionary *properties;
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)value forKey:(NSString *)key;
@end

@interface PSListController : UIViewController <UITableViewDelegate, UITableViewDataSource> {
    NSMutableArray *_specifiers;
}
@property(nonatomic, strong) PSSpecifier *specifier;
- (NSArray *)specifiers;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)plistName target:(id)target;
- (void)reloadSpecifiers;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (UITableView *)table;
- (NSBundle *)bundle;
@end

static NSString *const NNPPrefsDomain = @"com.user.notchnowplaying";
static NSString *const NNPPrefsChangedNotification = @"com.user.notchnowplaying.preferences.changed";
