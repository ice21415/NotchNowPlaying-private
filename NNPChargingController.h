#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@class UIView;

// Independent of media playback; all presentation changes run on the main queue.
@interface NNPChargingController : NSObject
@property(nonatomic) BOOL aodPresentationActive;
@property(nonatomic) CGPoint pixelShiftPixels;
- (void)restPixels;
- (void)setAODPresentationHost:(UIView *)host;
- (void)start;
- (void)stop;
@end
