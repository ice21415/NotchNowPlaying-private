#import "NNPDisplayController.h"
#import "NNPDiagnostics.h"

#ifndef NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
#define NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE 0
#endif

#if !NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
void NNPPhase7SetExperimentArmed(__unused BOOL armed) {}
void NNPPhase7SetSessionID(__unused NSString *sessionID) {}
void NNPPhase7NotifyDisplayModeSubstitution(__unused long long requestedMode, __unused long long substitutedMode) {}
#endif

@interface NNPDisplayController ()
@property(nonatomic, strong) NSTimer *visibleDurationTimer;
@property(nonatomic) NSUInteger sessionGeneration;
@property(nonatomic, copy) NSString *sessionIdentifier;
@property(nonatomic) BOOL modeSubstitutionObserved;
@property(nonatomic) BOOL lockedVisibleActivated;
- (void)noteDisplayModeSubstitutionRequested:(long long)requestedMode substitutedMode:(long long)substitutedMode;
- (void)activateLockedVisibleSessionIfReady;
- (void)stopLockedVisibleModeWithReason:(NSString *)reason;
@end

@implementation NNPDisplayController
@synthesize lifecycleState = _lifecycleState;
@synthesize maximumDuration = _maximumDuration;

static __weak NNPDisplayController *NNPCurrentDisplayController;
static NSUInteger NNPNextSessionGeneration;

#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
void NNPPhase7NotifyDisplayModeSubstitution(long long requestedMode, long long substitutedMode) {
    __weak NNPDisplayController *weakController = NNPCurrentDisplayController;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakController noteDisplayModeSubstitutionRequested:requestedMode substitutedMode:substitutedMode];
    });
}
#endif

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NNPCurrentDisplayController = self;
    _lifecycleState = NNPDisplayLifecycleStateDisabled;
    _maximumDuration = 30.0;
    NNPDiagnosticSetInteger(@"LockedVisibleLifecycle", _lifecycleState);
    NNPDiagnosticSetBool(@"Phase7ModeSubstitution", NO);
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
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY lifecycle state=%ld", (long)state]);
}

- (void)setDeviceLocked:(BOOL)deviceLocked {
    if (_deviceLocked == deviceLocked) return;
    BOOL wasLocked = _deviceLocked;
    _deviceLocked = deviceLocked;
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY deviceLocked=%@ session=%@", deviceLocked ? @"YES" : @"NO", self.sessionIdentifier ?: @"none"]);
    if (wasLocked && !deviceLocked &&
        (_lifecycleState == NNPDisplayLifecycleStatePreparing ||
         _lifecycleState == NNPDisplayLifecycleStateActive)) {
        [self stopLockedVisibleModeWithReason:@"unlock"];
    } else if (deviceLocked && _lifecycleState == NNPDisplayLifecycleStatePreparing && self.modeSubstitutionObserved) {
        [self activateLockedVisibleSessionIfReady];
    }
}

- (void)cancelVisibleDurationTimer:(NSString *)reason {
    if (!self.visibleDurationTimer) return;
    [self.visibleDurationTimer invalidate];
    self.visibleDurationTimer = nil;
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY timer cancelled session=%@ reason=%@", self.sessionIdentifier ?: @"none", reason ?: @"unknown"]);
}

- (void)startVisibleDurationTimer {
    [self cancelVisibleDurationTimer:@"replace"];
    NSTimeInterval duration = MAX(5.0, MIN(60.0, self.maximumDuration));
    NSUInteger generation = self.sessionGeneration;
    NSString *session = [self.sessionIdentifier copy];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:duration];
    NNPDiagnosticSetDouble(@"Phase7TimerDeadline", deadline.timeIntervalSince1970);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY timer started session=%@ duration=%.1fs deadline=%.3f", session ?: @"none", duration, deadline.timeIntervalSince1970]);
    __weak typeof(self) weakSelf = self;
    self.visibleDurationTimer = [NSTimer scheduledTimerWithTimeInterval:duration repeats:NO block:^(__unused NSTimer *timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.sessionGeneration != generation || strongSelf.sessionIdentifier.length == 0 || ![strongSelf.sessionIdentifier isEqualToString:session] ||
            strongSelf.lifecycleState != NNPDisplayLifecycleStateActive || !strongSelf.deviceLocked || !strongSelf.modeSubstitutionObserved) {
            NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY stale timeout ignored session=%@ current=%@ generation=%lu currentGeneration=%lu lifecycle=%ld locked=%@ substituted=%@", session ?: @"none", strongSelf.sessionIdentifier ?: @"none", (unsigned long)generation, (unsigned long)strongSelf.sessionGeneration, (long)strongSelf.lifecycleState, strongSelf.deviceLocked ? @"YES" : @"NO", strongSelf.modeSubstitutionObserved ? @"YES" : @"NO"]);
            return;
        }
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY timeout callback session=%@ deadline=%.3f autoOff=SUPPRESSED_FAIL_OPEN", strongSelf.sessionIdentifier ?: @"none", deadline.timeIntervalSince1970]);
        [strongSelf stopLockedVisibleModeWithReason:@"maximum-duration"];
    }];
}

- (void)activateLockedVisibleSessionIfReady {
    if (self.lifecycleState != NNPDisplayLifecycleStatePreparing || !self.deviceLocked || !self.modeSubstitutionObserved) return;
    self.lockedVisibleActivated = YES;
    NNPDiagnosticSetBool(@"Phase7LockedVisibleActive", YES);
    NNPDiagnosticSetDouble(@"Phase7LockedTimestamp", NSDate.date.timeIntervalSince1970);
    self.lifecycleState = NNPDisplayLifecycleStateActive;
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY locked-visible active session=%@ modeSubstitution=YES", self.sessionIdentifier ?: @"none"]);
    [self startVisibleDurationTimer];
}

- (void)noteDisplayModeSubstitutionRequested:(long long)requestedMode substitutedMode:(long long)substitutedMode {
    if (self.lifecycleState != NNPDisplayLifecycleStatePreparing && self.lifecycleState != NNPDisplayLifecycleStateActive) return;
    self.modeSubstitutionObserved = YES;
    NNPDiagnosticSetBool(@"Phase7ModeSubstitution", YES);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY mode substitution observed session=%@ requested=%lld substituted=%lld deviceLocked=%@", self.sessionIdentifier ?: @"none", requestedMode, substitutedMode, self.deviceLocked ? @"YES" : @"NO"]);
    [self activateLockedVisibleSessionIfReady];
}

- (BOOL)startLockedVisibleMode {
    if (_lifecycleState == NNPDisplayLifecycleStateActive ||
        _lifecycleState == NNPDisplayLifecycleStatePreparing) return YES;
    if (_lifecycleState == NNPDisplayLifecycleStateStopping) return NO;
    // A preference change or SpringBoard restart can make the feature
    // eligible while the device is already locked. Do not start a new
    // display-mode experiment in that existing lock session. An Active or
    // Preparing state has already been reached while unlocked and is allowed
    // to continue through the subsequent lock transition above.
    if (self.deviceLocked) {
        NNPDiagnosticSetBool(@"LockedVisibleActivationDeferred", YES);
        NNPDiagnosticLogTransition(@"DISPLAY activation deferred; device already locked");
        return NO;
    }
    NNPDiagnosticSetBool(@"LockedVisibleActivationDeferred", NO);
    if (![self isLockedVisibleSupported]) {
        self.lifecycleState = NNPDisplayLifecycleStateUnsupported;
        NNPDiagnosticSetBool(@"LockedVisibleSupported", NO);
        NNPDiagnosticLogTransition(@"DISPLAY unsupported; no display mutation attempted");
        return NO;
    }
    self.sessionGeneration = ++NNPNextSessionGeneration;
    self.sessionIdentifier = [NSString stringWithFormat:@"S%lu", (unsigned long)self.sessionGeneration];
    self.modeSubstitutionObserved = NO;
    self.lockedVisibleActivated = NO;
    [self cancelVisibleDurationTimer:@"new-session"];
    NNPPhase7SetSessionID(self.sessionIdentifier);
    NNPDiagnosticSetBool(@"Phase7ModeSubstitution", NO);
    NNPDiagnosticSetBool(@"Phase7LockedVisibleActive", NO);
    NNPDiagnosticSetDouble(@"Phase7ArmedTimestamp", NSDate.date.timeIntervalSince1970);
    self.lifecycleState = NNPDisplayLifecycleStatePreparing;
    NNPPhase7SetExperimentArmed(YES);
    NNPDiagnosticSetBool(@"LockedVisibleSupported", YES);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY experiment armed session=%@ duration=%.1fs deviceLocked=%@ waitingForModeSubstitution=YES", self.sessionIdentifier, self.maximumDuration, self.deviceLocked ? @"YES" : @"NO"]);
    return YES;
}

- (void)stopLockedVisibleMode {
    [self stopLockedVisibleModeWithReason:@"requested"];
}

- (void)stopLockedVisibleModeWithReason:(NSString *)reason {
    if (_lifecycleState == NNPDisplayLifecycleStateDisabled ||
        _lifecycleState == NNPDisplayLifecycleStateIdle ||
        _lifecycleState == NNPDisplayLifecycleStateUnsupported) return;
    if (_lifecycleState == NNPDisplayLifecycleStateStopping) return;
    NSString *session = [self.sessionIdentifier copy] ?: @"none";
    BOOL substitutedDuringLockedSession = self.deviceLocked && self.modeSubstitutionObserved;
    // Disarm before any other cleanup so a nested/native transition cannot be
    // intercepted while this session is being torn down.
    NNPPhase7SetExperimentArmed(NO);
    self.lifecycleState = NNPDisplayLifecycleStateStopping;
    [self cancelVisibleDurationTimer:reason];
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY cleanup fail-open session=%@ substituted=%@ deviceLocked=%@ reason=%@ autoOff=SUPPRESSED", session, self.modeSubstitutionObserved ? @"YES" : @"NO", self.deviceLocked ? @"YES" : @"NO", reason ?: @"unknown"]);
    self.lifecycleState = NNPDisplayLifecycleStateIdle;
    NNPDiagnosticSetBool(@"Phase7LockedVisibleActive", NO);
    NNPDiagnosticSetBool(@"Phase7RestoreRequested", NO);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY experiment stopped session=%@ reason=%@ substituted=%@ lockedSession=%@ restoreRequested=NO autoOff=SUPPRESSED deviceLocked=%@", session, reason ?: @"unknown", self.modeSubstitutionObserved ? @"YES" : @"NO", substitutedDuringLockedSession ? @"YES" : @"NO", self.deviceLocked ? @"YES" : @"NO"]);
    self.modeSubstitutionObserved = NO;
    self.lockedVisibleActivated = NO;
    self.sessionIdentifier = nil;
    NNPPhase7SetSessionID(@"none");
}

- (void)dealloc {
    [self cancelVisibleDurationTimer:@"dealloc"];
    if (NNPCurrentDisplayController == self) NNPCurrentDisplayController = nil;
}
@end
