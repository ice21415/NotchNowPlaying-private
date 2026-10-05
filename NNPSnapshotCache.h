#import <Foundation/Foundation.h>
// Accessed on the main thread. Notifications invalidate; a bounded recovery
// read handles missed notifications without rereading the plist every tick.
@interface NNPSnapshotCache : NSObject
- (instancetype)initWithLoader:(NSDictionary *(^)(void))loader recoveryInterval:(NSTimeInterval)interval;
- (NSDictionary *)snapshotAtTime:(NSTimeInterval)now;
- (void)invalidate;
@end
