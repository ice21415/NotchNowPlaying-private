#import "NNPPreferences.h"
#import "NNPDiagnostics.h"
#import "NNPSnapshotCache.h"
#import <CoreFoundation/CoreFoundation.h>

NSString * const NNPPreferencesDidChangeNotification = @"com.user.notchnowplaying.preferences.changed";
NSString * const NNPSpotifyDataDidChangeNotification = @"com.user.notchnowplaying.spotify-data.changed";
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
        if (![snapshot[@"SpotifyLyricsText"] isKindOfClass:NSString.class] &&
            ![snapshot[@"SpotifyQueueSnapshot"] isKindOfClass:NSDictionary.class]) continue;
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
@property(nonatomic, strong) NNPSnapshotCache *snapshotCache;
@property(nonatomic, strong) NSDictionary *appliedSpotifySnapshot;
@property(nonatomic) BOOL observing;
@property(nonatomic) BOOL changeScheduled;
@property(nonatomic) BOOL settingsChanged;
@property(nonatomic) BOOL spotifyChanged;
- (void)queueChangeForSettings:(BOOL)settings;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL chargingAnimationEnabled;
@property(nonatomic) BOOL spotifyOnly;
@property(nonatomic) BOOL showWhileUnlocked;
@property(nonatomic) BOOL showOnLockScreen;
@property(nonatomic) BOOL showArtwork;
@property(nonatomic) BOOL showArtist;
@property(nonatomic) BOOL showProgress;
@property(nonatomic) BOOL showLyrics;
@property(nonatomic) BOOL showClock;
@property(nonatomic) BOOL showBattery;
@property(nonatomic) BOOL showNextTrack;
@property(nonatomic) BOOL aodLandscapeEnabled;
@property(nonatomic) BOOL aodPocketModeEnabled;
@property(nonatomic) BOOL aodIdleDisplayEnabled;
@property(nonatomic) double aodStillTimeoutMinutes;
@property(nonatomic) BOOL aodSleepEnabled;
@property(nonatomic) BOOL aodSleepWhileCharging;
@property(nonatomic) NSInteger aodLowBatteryPercent;
@property(nonatomic) NSInteger aodSleepStartMinutes;
@property(nonatomic) NSInteger aodSleepEndMinutes;
@property(nonatomic) double aodSleepTimeoutMinutes;
@property(nonatomic) double aodLiftBoostFactor;
@property(nonatomic) BOOL mengoEnabled;
@property(nonatomic) CGFloat lyricsSyncOffsetMilliseconds;
@property(nonatomic, copy) NSString *spotifyLyricsText;
@property(nonatomic, copy) NSString *spotifyLyricsNextLine;
@property(nonatomic, copy) NSString *spotifyLyricsTrackTitle;
@property(nonatomic, copy) NSString *spotifyLyricsTrackArtist;
@property(nonatomic, copy) NSArray<NSDictionary *> *spotifyLyricsTimedLines;
@property(nonatomic, copy) NSDictionary *spotifyQueueSnapshot;
@property(nonatomic) BOOL hideWhenPaused;
@property(nonatomic) BOOL aodPixelShiftEnabled;
@property(nonatomic) float aodBrightnessMultiplier;
@property(nonatomic) BOOL aodAutomaticBrightnessEnabled;
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
    BOOL settings = CFEqual(name, (__bridge CFStringRef)NNPPreferencesDidChangeNotification);
    dispatch_async(dispatch_get_main_queue(), ^{ [preferences queueChangeForSettings:settings]; });
}

@implementation NNPPreferences
+ (instancetype)sharedPreferences { static NNPPreferences *p; static dispatch_once_t once; dispatch_once(&once, ^{ p = [self new]; [p reload]; }); return p; }
- (void)reload {
    CFPreferencesAppSynchronize(NNPPreferencesDomain);
    self.enabled = NNPBool(@"Enabled", YES);
    self.chargingAnimationEnabled = NNPBool(@"ChargingAnimationEnabled", YES);
    self.spotifyOnly = NNPBool(@"SpotifyOnly", YES);
    self.showWhileUnlocked = NNPBool(@"ShowWhileUnlocked", YES);
    self.showOnLockScreen = NNPBool(@"ShowOnLockScreen", YES);
    self.showArtwork = NNPBool(@"ShowArtwork", YES);
    self.showArtist = NNPBool(@"ShowArtist", YES);
    self.showProgress = NNPBool(@"ShowProgress", YES);
    self.showLyrics = NNPBool(@"ShowLyrics", YES);
    self.showClock = NNPBool(@"ShowClock", YES);
    self.showBattery = NNPBool(@"ShowBattery", YES);
    self.showNextTrack = NNPBool(@"ShowNextTrack", YES);
    self.aodLandscapeEnabled = NNPBool(@"AODLandscapeEnabled", YES);
    self.aodPocketModeEnabled = NNPBool(@"AODPocketModeEnabled", YES);
    self.aodIdleDisplayEnabled = NNPBool(@"AODIdleDisplayEnabled", YES);
    self.aodLiftBoostFactor = MAX(1.0, MIN(4.0, NNPFloat(@"AODLiftBoostFactor", 2.0)));
    self.aodSleepEnabled = NNPBool(@"AODSleepEnabled", NO);
    self.aodSleepWhileCharging = NNPBool(@"AODSleepWhileCharging", NO);
    self.aodLowBatteryPercent = (NSInteger)MAX(0.0, MIN(60.0, NNPFloat(@"AODLowBatteryPercent", 20.0)));
    self.aodSleepStartMinutes = (NSInteger)MAX(0.0, MIN(1439.0, NNPFloat(@"AODSleepStartMinutes", 1380.0)));
    self.aodSleepEndMinutes = (NSInteger)MAX(0.0, MIN(1439.0, NNPFloat(@"AODSleepEndMinutes", 420.0)));
    self.aodSleepTimeoutMinutes = MAX(0.02, MIN(120.0, NNPFloat(@"AODSleepTimeoutMinutes", 1.0)));
    self.aodStillTimeoutMinutes = MAX(0.0, MIN(120.0, NNPFloat(@"AODStillTimeoutMinutes", 0.0)));
    self.mengoEnabled = NNPBool(@"MengoEnabled", YES);
    self.lyricsSyncOffsetMilliseconds = MAX(-500.0, MIN(500.0, NNPFloat(@"LyricsSyncOffsetMilliseconds", 100.0)));
    [self reloadSpotifyLyricsSnapshot];
    self.hideWhenPaused = NNPBool(@"HideWhenPaused", YES);
    self.aodPixelShiftEnabled = NNPBool(@"AODPixelShiftEnabled", YES);
    self.aodAutomaticBrightnessEnabled = NNPBool(@"AODAutomaticBrightnessEnabled", YES);
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
- (void)reloadSpotifyLyricsSnapshot {
    if (!self.snapshotCache) {
        self.snapshotCache = [[NNPSnapshotCache alloc] initWithLoader:^{
            static NSUInteger reads;
            NNPDiagnosticSetInteger(@"SpotifySnapshotReadCount", ++reads);
            return NNPSpotifyLyricsSnapshot();
        } recoveryInterval:30.0];
    }
    NSDictionary *lyrics = [self.snapshotCache snapshotAtTime:NSProcessInfo.processInfo.systemUptime];
    if (lyrics == self.appliedSpotifySnapshot) return;
    self.appliedSpotifySnapshot = lyrics;
    self.spotifyQueueSnapshot = [lyrics[@"SpotifyQueueSnapshot"] isKindOfClass:NSDictionary.class] ? lyrics[@"SpotifyQueueSnapshot"] : @{};
    self.spotifyLyricsText = [lyrics[@"SpotifyLyricsText"] isKindOfClass:NSString.class] ? lyrics[@"SpotifyLyricsText"] : @"";
    self.spotifyLyricsNextLine = [lyrics[@"SpotifyLyricsNextLine"] isKindOfClass:NSString.class] ? lyrics[@"SpotifyLyricsNextLine"] : @"";
    self.spotifyLyricsTrackTitle = [lyrics[@"SpotifyLyricsTrackTitle"] isKindOfClass:NSString.class] ? lyrics[@"SpotifyLyricsTrackTitle"] : @"";
    self.spotifyLyricsTrackArtist = [lyrics[@"SpotifyLyricsTrackArtist"] isKindOfClass:NSString.class] ? lyrics[@"SpotifyLyricsTrackArtist"] : @"";
    self.spotifyLyricsTimedLines = [lyrics[@"SpotifyLyricsTimedLines"] isKindOfClass:NSArray.class] ? lyrics[@"SpotifyLyricsTimedLines"] : @[];
}
- (void)reloadAODBrightnessMultiplier {
    CFPreferencesAppSynchronize(NNPPreferencesDomain);
    self.aodBrightnessMultiplier = (float)MAX(1.0, MIN(4.0, NNPFloat(@"AODBrightnessMultiplier", 100.0) / 100.0));
    NNPDiagnosticSetDouble(@"PreferenceAODBrightnessMultiplier", self.aodBrightnessMultiplier);
}
- (void)startObserving {
    if (self.observing) return;
    self.observing = YES;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), NNPPreferencesCallback, (__bridge CFStringRef)NNPPreferencesDidChangeNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), NNPPreferencesCallback, (__bridge CFStringRef)NNPSpotifyDataDidChangeNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
- (void)queueChangeForSettings:(BOOL)settings {
    self.settingsChanged |= settings;
    self.spotifyChanged |= !settings;
    if (self.changeScheduled) return;
    self.changeScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL settingsChanged = self.settingsChanged;
        BOOL spotifyChanged = self.spotifyChanged;
        self.settingsChanged = self.spotifyChanged = self.changeScheduled = NO;
        [self.snapshotCache invalidate];
        if (settingsChanged) [self reload];
        else [self reloadSpotifyLyricsSnapshot];
        if (settingsChanged)
            [NSNotificationCenter.defaultCenter postNotificationName:NNPPreferencesDidChangeNotification object:self];
        else if (spotifyChanged)
            [NSNotificationCenter.defaultCenter postNotificationName:NNPSpotifyDataDidChangeNotification object:self];
    });
}
- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), NULL, NULL);
}
@end
