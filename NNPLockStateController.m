#import "NNPLockStateController.h"
#import "NNPDiagnostics.h"
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
    NNPDiagnosticLog([NSString stringWithFormat:@"LOCK_OBSERVER started initialLogicalLock=%@", _locked ? @"YES" : @"NO"]);
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(__unused NSTimer *timer) {
        [weakSelf poll];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)poll {
    BOOL value = NNPReadLockState();
    if (value == _locked) return;
    _locked = value;
    NNPDiagnosticBeginTransition(value ? @"logical-lock-observed" : @"logical-unlock-observed");
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"LOCK_OBSERVER isUILocked changed value=%@", value ? @"YES" : @"NO"]);
    if (self.stateHandler) self.stateHandler(value);
}
- (void)stop { [_timer invalidate]; _timer = nil; _started = NO; NNPDiagnosticLogTransition(@"LOCK_OBSERVER stopped"); }
- (void)dealloc { [self stop]; }
@end
