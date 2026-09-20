#import <Foundation/Foundation.h>

typedef void (^NNPLockStateHandler)(BOOL locked);

@interface NNPLockStateController : NSObject
@property(nonatomic, readonly, getter=isLocked) BOOL locked;
@property(nonatomic, copy) NNPLockStateHandler stateHandler;
- (void)start;
- (void)stop;
@end
