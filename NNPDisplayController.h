#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NNPDisplayLifecycleState) {
    NNPDisplayLifecycleStateDisabled = 0,
    NNPDisplayLifecycleStateIdle,
    NNPDisplayLifecycleStatePreparing,
    NNPDisplayLifecycleStateActive,
    NNPDisplayLifecycleStateStopping,
    NNPDisplayLifecycleStateUnsupported,
    NNPDisplayLifecycleStateFailed,
};

@interface NNPDisplayController : NSObject
@property(nonatomic, readonly) NNPDisplayLifecycleState lifecycleState;
- (BOOL)isLockedVisibleSupported;
- (BOOL)startLockedVisibleMode;
- (void)stopLockedVisibleMode;
@end
