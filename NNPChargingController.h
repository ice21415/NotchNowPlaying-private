#import <Foundation/Foundation.h>

// Independent of media playback; all presentation changes run on the main queue.
@interface NNPChargingController : NSObject
- (void)start;
- (void)stop;
@end
