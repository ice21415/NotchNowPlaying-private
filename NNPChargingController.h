#import <Foundation/Foundation.h>

// Independent of media playback; all presentation changes run on the main queue.
@interface NNPChargingController : NSObject
@property(nonatomic) BOOL aodPresentationActive;
- (void)start;
- (void)stop;
@end
