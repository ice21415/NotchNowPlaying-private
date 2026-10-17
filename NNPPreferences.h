#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const NNPPreferencesDidChangeNotification;
FOUNDATION_EXPORT NSString * const NNPSpotifyDataDidChangeNotification;

@interface NNPPreferences : NSObject
@property(nonatomic, readonly) BOOL enabled;
@property(nonatomic, readonly) BOOL chargingAnimationEnabled;
@property(nonatomic, readonly) BOOL spotifyOnly;
@property(nonatomic, readonly) BOOL showWhileUnlocked;
@property(nonatomic, readonly) BOOL showOnLockScreen;
@property(nonatomic, readonly) BOOL showArtwork;
@property(nonatomic, readonly) BOOL showArtist;
@property(nonatomic, readonly) BOOL showProgress;
@property(nonatomic, readonly) BOOL showLyrics;
@property(nonatomic, readonly) BOOL showClock;
@property(nonatomic, readonly) BOOL showBattery;
@property(nonatomic, readonly) BOOL showNextTrack;
@property(nonatomic, readonly) BOOL aodLandscapeEnabled;
@property(nonatomic, readonly) BOOL aodPocketModeEnabled;
@property(nonatomic, readonly) BOOL aodIdleDisplayEnabled;
@property(nonatomic, readonly) NSInteger aodStillTimeoutMinutes;
@property(nonatomic, readonly) BOOL mengoEnabled;
@property(nonatomic, readonly) CGFloat lyricsSyncOffsetMilliseconds;
@property(nonatomic, copy, readonly) NSString *spotifyLyricsText;
@property(nonatomic, copy, readonly) NSString *spotifyLyricsNextLine;
@property(nonatomic, copy, readonly) NSString *spotifyLyricsTrackTitle;
@property(nonatomic, copy, readonly) NSString *spotifyLyricsTrackArtist;
@property(nonatomic, copy, readonly) NSArray<NSDictionary *> *spotifyLyricsTimedLines;
@property(nonatomic, readonly) BOOL hideWhenPaused;
@property(nonatomic, readonly) BOOL aodPixelShiftEnabled;
@property(nonatomic, readonly) float aodBrightnessMultiplier;
@property(nonatomic, readonly) BOOL aodAutomaticBrightnessEnabled;
@property(nonatomic, readonly) BOOL experimentalLockedVisible;
@property(nonatomic, readonly) BOOL experimentalUnlimitedDuration;
@property(nonatomic, readonly) NSTimeInterval experimentalMaxDuration;
@property(nonatomic, readonly) NSTimeInterval progressUpdateInterval;
@property(nonatomic, readonly) CGFloat artworkSize;
@property(nonatomic, readonly) CGFloat cornerRadius;
@property(nonatomic, readonly) CGFloat textSize;
@property(nonatomic, readonly) CGFloat progressHeight;
+ (instancetype)sharedPreferences;
- (void)reload;
- (void)reloadSpotifyLyricsSnapshot;
- (NSDictionary *)spotifyQueueSnapshot;
- (void)reloadAODBrightnessMultiplier;
- (void)startObserving;
@end
