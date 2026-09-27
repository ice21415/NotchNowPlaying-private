#import "NNPPreferences.h"
#import "NNPDiagnostics.h"
#import <CoreFoundation/CoreFoundation.h>

NSString * const NNPPreferencesDidChangeNotification = @"com.user.notchnowplaying.preferences.changed";
static CFStringRef const NNPPreferencesDomain = CFSTR("com.user.notchnowplaying");

static id NNPPreferenceValue(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, NNPPreferencesDomain));
}
static NSDictionary *NNPSpotifyLyricsSnapshot(void) {
    static NSString *cachedPreferencesPath;
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if (cachedPreferencesPath.length) {
        NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:cachedPreferencesPath];
        if (snapshot) return snapshot;
        cachedPreferencesPath = nil;
    }

    NSString *containersPath = @"/private/var/mobile/Containers/Data/Application";
    NSArray<NSString *> *containerNames = [fileManager contentsOfDirectoryAtPath:containersPath error:nil];
    for (NSString *containerName in containerNames) {
        NSString *preferencesDirectory = [[containersPath stringByAppendingPathComponent:containerName]
            stringByAppendingPathComponent:@"Library/Preferences"];
        NSString *spotifyDefaults = [preferencesDirectory stringByAppendingPathComponent:@"com.spotify.client.plist"];
        NSString *lyricsPreferences = [preferencesDirectory stringByAppendingPathComponent:@"com.user.notchnowplaying.plist"];
        if (![fileManager fileExistsAtPath:spotifyDefaults] || ![fileManager fileExistsAtPath:lyricsPreferences]) continue;
        NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:lyricsPreferences];
        if (![snapshot[@"SpotifyLyricsText"] isKindOfClass:NSString.class]) continue;
        cachedPreferencesPath = lyricsPreferences;
        NNPDiagnosticSetBool(@"SpotifyLyricsContainerReadable", YES);
        return snapshot;
    }
    NNPDiagnosticSetBool(@"SpotifyLyricsContainerReadable", NO);
    return @{};
}
static BOOL NNPBool(NSString *key, BOOL fallback) {
    id value = NNPPreferenceValue(key);
    return value ? [value boolValue] : fallback;
}
static CGFloat NNPFloat(NSString *key, CGFloat fallback) {
    id value = NNPPreferenceValue(key);
    return value ? [value doubleValue] : fallback;
}

@interface NNPPreferences ()
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL spotifyOnly;
@property(nonatomic) BOOL showWhileUnlocked;
@property(nonatomic) BOOL showOnLockScreen;
@property(nonatomic) BOOL showArtwork;
@property(nonatomic) BOOL showArtist;
@property(nonatomic) BOOL showProgress;
@property(nonatomic) BOOL showLyrics;
@property(nonatomic, copy) NSString *spotifyLyricsText;
@property(nonatomic, copy) NSString *spotifyLyricsNextLine;
@property(nonatomic, copy) NSString *spotifyLyricsTrackTitle;
@property(nonatomic) BOOL hideWhenPaused;
@property(nonatomic) BOOL aodPixelShiftEnabled;
@property(nonatomic) float aodBrightnessMultiplier;
@property(nonatomic) BOOL experimentalLockedVisible;
@property(nonatomic) BOOL experimentalUnlimitedDuration;
@property(nonatomic) NSTimeInterval experimentalMaxDuration;
@property(nonatomic) NSTimeInterval progressUpdateInterval;
@property(nonatomic) CGFloat artworkSize;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic) CGFloat textSize;
@property(nonatomic) CGFloat progressHeight;
@end

static void NNPPreferencesCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NNPPreferences *preferences = (__bridge NNPPreferences *)observer;
    [preferences reload];
    [[NSNotificationCenter defaultCenter] postNotificationName:NNPPreferencesDidChangeNotification object:preferences];
}

@implementation NNPPreferences
+ (instancetype)sharedPreferences { static NNPPreferences *p; static dispatch_once_t once; dispatch_once(&once, ^{ p = [self new]; [p reload]; }); return p; }
- (void)reload {
    CFPreferencesAppSynchronize(NNPPreferencesDomain);
    self.enabled = NNPBool(@"Enabled", YES);
    self.spotifyOnly = NNPBool(@"SpotifyOnly", YES);
    self.showWhileUnlocked = NNPBool(@"ShowWhileUnlocked", YES);
    self.showOnLockScreen = NNPBool(@"ShowOnLockScreen", YES);
    self.showArtwork = NNPBool(@"ShowArtwork", YES);
    self.showArtist = NNPBool(@"ShowArtist", YES);
    self.showProgress = NNPBool(@"ShowProgress", YES);
    self.showLyrics = NNPBool(@"ShowLyrics", YES);
    NSDictionary *lyrics = NNPSpotifyLyricsSnapshot();
    self.spotifyLyricsText = [lyrics[@"SpotifyLyricsText"] isKindOfClass:NSString.class] ? lyrics[@"SpotifyLyricsText"] : @"";
    self.spotifyLyricsNextLine = [lyrics[@"SpotifyLyricsNextLine"] isKindOfClass:NSString.class] ? lyrics[@"SpotifyLyricsNextLine"] : @"";
    self.spotifyLyricsTrackTitle = [lyrics[@"SpotifyLyricsTrackTitle"] isKindOfClass:NSString.class] ? lyrics[@"SpotifyLyricsTrackTitle"] : @"";
    self.hideWhenPaused = NNPBool(@"HideWhenPaused", YES);
    self.aodPixelShiftEnabled = NNPBool(@"AODPixelShiftEnabled", YES);
    self.aodBrightnessMultiplier = (float)MAX(1.0, MIN(4.0, NNPFloat(@"AODBrightnessMultiplier", 100.0) / 100.0));
    self.experimentalLockedVisible = NNPBool(@"ExperimentalLockedVisible", NO);
    self.experimentalUnlimitedDuration = NNPBool(@"ExperimentalUnlimitedDuration", NO);
    self.experimentalMaxDuration = MAX(5.0, MIN(60.0, NNPFloat(@"ExperimentalMaxDuration", 30.0)));
    self.progressUpdateInterval = MAX(0.5, MIN(5.0, NNPFloat(@"ProgressUpdateInterval", 1.0)));
    self.artworkSize = MAX(28.0, MIN(56.0, NNPFloat(@"ArtworkSize", 40.0)));
    self.cornerRadius = MAX(4.0, MIN(16.0, NNPFloat(@"CornerRadius", 9.0)));
    self.textSize = MAX(10.0, MIN(20.0, NNPFloat(@"TextSize", 14.0)));
    self.progressHeight = MAX(2.0, MIN(6.0, NNPFloat(@"ProgressHeight", 3.0)));
}
- (void)reloadAODBrightnessMultiplier {
    CFPreferencesAppSynchronize(NNPPreferencesDomain);
    self.aodBrightnessMultiplier = (float)MAX(1.0, MIN(4.0, NNPFloat(@"AODBrightnessMultiplier", 100.0) / 100.0));
    NNPDiagnosticSetDouble(@"PreferenceAODBrightnessMultiplier", self.aodBrightnessMultiplier);
}
- (void)startObserving {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), NNPPreferencesCallback, (__bridge CFStringRef)NNPPreferencesDidChangeNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), NULL, NULL);
}
@end
