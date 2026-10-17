#import <Foundation/Foundation.h>

// Reports "phone lifted" events from CoreMotion's wake-gesture engine, which runs on the motion
// coprocessor, so nothing wakes the application processor until the phone is actually picked up.
// Works with the system's Raise to Wake setting off (the system then has no delegate of its own).
// When the system already owns the engine's delegate, its delegate methods are observed instead and
// the engine is never started or stopped here.
@interface NNPPickupMonitor : NSObject
@property(nonatomic, copy) void (^lifted)(void);
- (void)setActive:(BOOL)active;
@end
