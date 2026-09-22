#import "NNPDisplayController.h"
#import "NNPDiagnostics.h"

// Phase 4 proved the first external display-service boundary, but not a safe
// way to keep the panel visible after normal lock blanking.  Keep this class
// deliberately side-effect-free until that capability is established.
@implementation NNPDisplayController
@synthesize lifecycleState = _lifecycleState;

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _lifecycleState = NNPDisplayLifecycleStateDisabled;
    NNPDiagnosticSetInteger(@"LockedVisibleLifecycle", _lifecycleState);
    return self;
}

- (BOOL)isLockedVisibleSupported {
    return NO;
}

- (void)setLifecycleState:(NNPDisplayLifecycleState)state {
    if (_lifecycleState == state) return;
    _lifecycleState = state;
    NNPDiagnosticSetInteger(@"LockedVisibleLifecycle", state);
}

- (BOOL)startLockedVisibleMode {
    if (_lifecycleState == NNPDisplayLifecycleStateActive ||
        _lifecycleState == NNPDisplayLifecycleStatePreparing) return YES;
    if (_lifecycleState == NNPDisplayLifecycleStateStopping) return NO;
    if (![self isLockedVisibleSupported]) {
        self.lifecycleState = NNPDisplayLifecycleStateUnsupported;
        NNPDiagnosticSetBool(@"LockedVisibleSupported", NO);
        NNPDiagnosticLog(@"LOCKED_VISIBLE unsupported; no display mutation attempted");
        return NO;
    }
    self.lifecycleState = NNPDisplayLifecycleStatePreparing;
    // No supported/reversible SpringBoard-local presentation primitive has
    // been identified.  Do not cross the BackBoard display boundary here.
    self.lifecycleState = NNPDisplayLifecycleStateFailed;
    NNPDiagnosticLog(@"LOCKED_VISIBLE failed during preparation");
    return NO;
}

- (void)stopLockedVisibleMode {
    if (_lifecycleState == NNPDisplayLifecycleStateDisabled ||
        _lifecycleState == NNPDisplayLifecycleStateIdle ||
        _lifecycleState == NNPDisplayLifecycleStateUnsupported) return;
    if (_lifecycleState == NNPDisplayLifecycleStateStopping) return;
    self.lifecycleState = NNPDisplayLifecycleStateStopping;
    // Idempotent cleanup hook reserved for a future supported experiment.
    self.lifecycleState = NNPDisplayLifecycleStateIdle;
    NNPDiagnosticLog(@"LOCKED_VISIBLE stopped; no display state was changed");
}
@end
