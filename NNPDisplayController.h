#import <Foundation/Foundation.h>

@interface NNPDisplayController : NSObject
@property(nonatomic, readonly) BOOL lockedVisibleSupported;
@property(nonatomic, readonly) BOOL lockedVisibleActive;
- (BOOL)startLockedVisibleMode;
- (void)stopLockedVisibleMode;
@end
