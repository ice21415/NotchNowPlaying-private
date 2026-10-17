#import "NNPPrefsListController.h"
#import <notify.h>

@implementation NNPPrefsListController

- (NSString *)plistName {
    NSString *name = [self.specifier propertyForKey:@"plistName"];
    return name.length ? name : @"Root";
}

static UIColor *NNPTintColor(NSString *name) {
    static NSDictionary *colors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        colors = @{ @"pink": UIColor.systemPinkColor, @"indigo": UIColor.systemIndigoColor,
                    @"orange": UIColor.systemOrangeColor, @"teal": UIColor.systemTealColor,
                    @"green": UIColor.systemGreenColor, @"gray": UIColor.systemGrayColor,
                    @"blue": UIColor.systemBlueColor, @"purple": UIColor.systemPurpleColor,
                    @"red": UIColor.systemRedColor, @"yellow": UIColor.systemYellowColor };
    });
    return colors[name] ?: UIColor.systemBlueColor;
}

// Settings-style icon: white SF Symbol on a colored rounded square.
static UIImage *NNPIconImage(NSString *symbol, NSString *tint) {
    CGSize size = CGSizeMake(29, 29);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [NNPTintColor(tint) setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:6.5] fill];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium];
        UIImage *glyph = [[UIImage systemImageNamed:symbol withConfiguration:config] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (!glyph) return;
        [glyph drawAtPoint:CGPointMake((size.width - glyph.size.width) / 2, (size.height - glyph.size.height) / 2)];
    }];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:[self plistName] target:self] mutableCopy];
        for (PSSpecifier *specifier in _specifiers) {
            NSString *symbol = [specifier propertyForKey:@"symbol"];
            if (!symbol.length) continue;
            UIImage *icon = NNPIconImage(symbol, [specifier propertyForKey:@"tint"]);
            if (icon) [specifier setProperty:icon forKey:@"iconImage"];
        }
        [self applyDependencies];
    }
    return _specifiers;
}

// Segmented rows only show a selection when the stored value is one of their steps, so a value left
// by the previous slider UI is shown as the nearest step (it is only rewritten when the user taps).
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    id value = [super readPreferenceValue:specifier];
    NSArray *steps = [specifier propertyForKey:@"validValues"];
    if (![steps isKindOfClass:NSArray.class] || !steps.count || ![value respondsToSelector:@selector(doubleValue)]) return value;
    double current = [value doubleValue];
    id nearest = steps.firstObject;
    for (id step in steps)
        if (fabs([step doubleValue] - current) < fabs([nearest doubleValue] - current)) nearest = step;
    return nearest;
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

// Small illustration of the notch player shown above the root list.
static UIView *NNPMakeHeaderView(void) {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 168)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIView *phone = [[UIView alloc] initWithFrame:CGRectMake(0, 16, 230, 140)];
    phone.center = CGPointMake(160, phone.center.y);
    phone.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    phone.backgroundColor = UIColor.blackColor;
    phone.layer.cornerRadius = 34;
    phone.layer.borderWidth = 2.5;
    phone.layer.borderColor = UIColor.systemGray3Color.CGColor;
    phone.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    phone.clipsToBounds = YES;
    [header addSubview:phone];

    UIView *notch = [[UIView alloc] initWithFrame:CGRectMake(70, -1, 90, 24)];
    notch.backgroundColor = UIColor.blackColor;
    notch.layer.cornerRadius = 12;
    notch.layer.borderWidth = 1;
    notch.layer.borderColor = UIColor.systemGray2Color.CGColor;
    [phone addSubview:notch];

    UIView *art = [[UIView alloc] initWithFrame:CGRectMake(14, 34, 30, 30)];
    art.layer.cornerRadius = 7;
    art.clipsToBounds = YES;
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = art.bounds;
    gradient.colors = @[(id)UIColor.systemPinkColor.CGColor, (id)UIColor.systemOrangeColor.CGColor];
    [art.layer addSublayer:gradient];
    [phone addSubview:art];

    UIView *title = [[UIView alloc] initWithFrame:CGRectMake(52, 39, 90, 7)];
    title.backgroundColor = UIColor.whiteColor;
    title.layer.cornerRadius = 3.5;
    [phone addSubview:title];
    UIView *artist = [[UIView alloc] initWithFrame:CGRectMake(52, 53, 56, 6)];
    artist.backgroundColor = UIColor.systemGray2Color;
    artist.layer.cornerRadius = 3;
    [phone addSubview:artist];

    UIView *track = [[UIView alloc] initWithFrame:CGRectMake(14, 78, 202, 4)];
    track.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
    track.layer.cornerRadius = 2;
    [phone addSubview:track];
    UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(14, 78, 120, 4)];
    fill.backgroundColor = UIColor.systemGreenColor;
    fill.layer.cornerRadius = 2;
    [phone addSubview:fill];

    UILabel *clock = [[UILabel alloc] initWithFrame:CGRectMake(14, 94, 202, 36)];
    clock.text = @"9:41";
    clock.font = [UIFont monospacedDigitSystemFontOfSize:30 weight:UIFontWeightThin];
    clock.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    [phone addSubview:clock];
    return header;
}

@implementation NNPRootListController
- (NSString *)plistName { return @"Root"; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"瀏海音樂播放器";
    self.table.tableHeaderView = NNPMakeHeaderView();
}
@end
