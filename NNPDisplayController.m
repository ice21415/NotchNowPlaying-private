#import "NNPDisplayController.h"
#import "NNPDiagnostics.h"

#ifndef NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
#define NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE 0
#endif

#if !NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
void NNPPhase7SetExperimentArmed(__unused BOOL armed) {}
void NNPPhase7RestoreNormalDisplay(void) {}
#endif

// Phase 4 proved the first external display-service boundary, but not a safe
// way to keep the panel visible after normal lock blanking.  Keep this class
// deliberately side-effect-free until that capability is established.
@implementation NNPDisplayController
@synthesize lifecycleState = _lifecycleState;
@synthesize deviceLocked = _deviceLocked;
@synthesize maximumDuration = _maximumDuration;

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _lifecycleState = NNPDisplayLifecycleStateDisabled;
    _maximumDuration = 30.0;
    NNPDiagnosticSetInteger(@"LockedVisibleLifecycle", _lifecycleState);
    return self;
}

- (BOOL)isLockedVisibleSupported {
#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
    Class provider = NSClassFromString(@"BLSHBacklightOSInterfaceProvider");
    return provider && [provider instancesRespondToSelector:NSSelectorFromString(@"transitionToDisplayMode:withDuration:")];
#else
    return NO;
#endif
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
    NNPPhase7SetExperimentArmed(YES);
    self.lifecycleState = NNPDisplayLifecycleStateActive;
    NNPDiagnosticSetBool(@"LockedVisibleSupported", YES);
    NNPDiagnosticLog([NSString stringWithFormat:@"PHASE7 experiment armed duration=%.1fs", self.maximumDuration]);
    __weak typeof(self) weakSelf = self;
    NSTimeInterval duration = MAX(5.0, MIN(60.0, self.maximumDuration));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakSelf.lifecycleState != NNPDisplayLifecycleStateActive) return;
        NNPDiagnosticLog(@"PHASE7 maximum duration reached; restoring normal display");
        [weakSelf stopLockedVisibleMode];
    });
    return YES;
}

- (void)stopLockedVisibleMode {
    if (_lifecycleState == NNPDisplayLifecycleStateDisabled ||
        _lifecycleState == NNPDisplayLifecycleStateIdle ||
        _lifecycleState == NNPDisplayLifecycleStateUnsupported) return;
    if (_lifecycleState == NNPDisplayLifecycleStateStopping) return;
    self.lifecycleState = NNPDisplayLifecycleStateStopping;
    NNPPhase7SetExperimentArmed(NO);
    if (_deviceLocked) NNPPhase7RestoreNormalDisplay();
    self.lifecycleState = NNPDisplayLifecycleStateIdle;
    NNPDiagnosticLog(@"PHASE7 experiment stopped; normal display restore requested");
}
@end
