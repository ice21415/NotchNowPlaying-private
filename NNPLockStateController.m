#import "NNPLockStateController.h"
#import <objc/message.h>

@interface NNPLockStateController ()
@property(nonatomic) BOOL locked;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) BOOL started;
@end

static BOOL NNPReadLockState(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    SEL shared = @selector(sharedInstance), selector = @selector(isUILocked);
    if (!cls || ![cls respondsToSelector:shared]) return NO;
    id manager = ((id (*)(id, SEL))objc_msgSend)((id)cls, shared);
    if (!manager || ![manager respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(manager, selector);
}

@implementation NNPLockStateController
- (void)start {
    if (_started) return;
    _started = YES;
    _locked = NNPReadLockState();
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(__unused NSTimer *timer) {
        [weakSelf poll];
    }];
}
- (void)poll {
    BOOL value = NNPReadLockState();
    if (value == _locked) return;
    _locked = value;
    if (self.stateHandler) self.stateHandler(value);
}
- (void)stop { [_timer invalidate]; _timer = nil; _started = NO; }
- (void)dealloc { [self stop]; }
@end
