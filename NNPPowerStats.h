#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NNPPowerStatsMode) {
    NNPPowerStatsModeIdle = 0,
    NNPPowerStatsModeMedia = 1,
};

// Records AOD usage and whole-device battery drain, one sample per minute while AOD is visible.
@interface NNPPowerStats : NSObject
+ (instancetype)sharedStats;
- (void)sampleWithMode:(NNPPowerStatsMode)mode;
// Ends the current continuous run (the next sample starts a new baseline) and persists pending data.
- (void)endRun;
// Records the battery level and charging time whenever the level or charging state changes, AOD or not.
- (void)startObservingBattery;
@end
