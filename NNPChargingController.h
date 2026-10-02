#import <Foundation/Foundation.h>
@class UIView;

// Independent of media playback; all presentation changes run on the main queue.
@interface NNPChargingController : NSObject
@property(nonatomic) BOOL aodPresentationActive;
- (void)setAODPresentationHost:(UIView *)host;
- (void)start;
- (void)stop;
@end
