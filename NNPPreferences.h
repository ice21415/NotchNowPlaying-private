#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const NNPPreferencesDidChangeNotification;

@interface NNPPreferences : NSObject
@property(nonatomic, readonly) BOOL enabled;
@property(nonatomic, readonly) BOOL spotifyOnly;
@property(nonatomic, readonly) BOOL showWhileUnlocked;
@property(nonatomic, readonly) BOOL showOnLockScreen;
@property(nonatomic, readonly) BOOL showArtwork;
@property(nonatomic, readonly) BOOL showArtist;
@property(nonatomic, readonly) BOOL showProgress;
@property(nonatomic, readonly) BOOL hideWhenPaused;
@property(nonatomic, readonly) BOOL aodPixelShiftEnabled;
@property(nonatomic, readonly) float aodBrightnessMultiplier;
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
- (void)reloadAODBrightnessMultiplier;
- (void)startObserving;
@end
