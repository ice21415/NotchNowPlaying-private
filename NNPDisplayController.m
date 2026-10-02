#import "NNPDisplayController.h"
#import "NNPDiagnostics.h"
#import "NNPNotificationDiagnostics.h"
#import <math.h>

#ifndef NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
#define NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE 0
#endif
#ifndef NNP_PHASE7_DRY_RUN
#define NNP_PHASE7_DRY_RUN 0
#endif

#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
#import "NNPController.h"
#endif
#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE && NNP_PHASE7_DRY_RUN == 0
#import "NNPAODNitsController.h"
#endif

#if !NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE || NNP_PHASE7_DRY_RUN == 1
void NNPPhase7SetExperimentArmed(__unused BOOL armed) {}
void NNPPhase7SetAODPresentationActive(__unused BOOL active) {}
void NNPPhase7SetSessionID(__unused NSString *sessionID) {}
void NNPPhase7SetAODBrightnessMultiplier(__unused float multiplier) {}
void NNPPhase7NotifyBacklightFactorSubstitution(__unused float originalFactor, __unused float dimmedFactor) {}
void NNPPhase7NotifyDisplayWake(void) {}
BOOL NNPPhase7PresentNotificationSnakeAnimation(void) { return NO; }
void NNPPhase7StartIncidentDiagnostics(void) {}
BOOL NNPPhase7EnsureBacklightFactorHook(void) { return NO; }
void NNPPhase7UpdateForensicsState(__unused NSInteger lifecycleState, __unused BOOL deviceLocked, __unused BOOL modeSubstitutionObserved, __unused BOOL timerActive) {}
#elif NNP_PHASE7_DRY_RUN == 2
void NNPPhase7NotifyBacklightFactorSubstitution(__unused float originalFactor, __unused float dimmedFactor) {}
void NNPPhase7NotifyDisplayWake(void) {}
BOOL NNPPhase7PresentNotificationSnakeAnimation(void) { return NO; }
#endif

@interface NNPDisplayController ()
@property(nonatomic) BOOL aodPresentationActive;
@property(nonatomic, strong) NSTimer *visibleDurationTimer;
@property(nonatomic) NSUInteger sessionGeneration;
@property(nonatomic, copy) NSString *sessionIdentifier;
@property(nonatomic) BOOL modeSubstitutionObserved;
@property(nonatomic) BOOL lockedVisibleActivated;
- (void)noteBacklightFactorSubstitutionFrom:(float)originalFactor to:(float)dimmedFactor;
- (void)activateLockedVisibleSessionIfReady;
- (void)noteDisplayWake;
- (void)cancelVisibleDurationTimer:(NSString *)reason;
- (void)startVisibleDurationTimer;
- (void)stopLockedVisibleModeWithReason:(NSString *)reason;
@end

@implementation NNPDisplayController
@synthesize lifecycleState = _lifecycleState;
@synthesize aodPresentationActive = _aodPresentationActive;
@synthesize maximumDuration = _maximumDuration;
@synthesize unlimitedDuration = _unlimitedDuration;
@synthesize aodBrightnessMultiplier = _aodBrightnessMultiplier;

static __weak NNPDisplayController *NNPCurrentDisplayController;
static NSUInteger NNPNextSessionGeneration;

#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE && NNP_PHASE7_DRY_RUN == 0
void NNPPhase7NotifyBacklightFactorSubstitution(float originalFactor, float dimmedFactor) {
    __weak NNPDisplayController *weakController = NNPCurrentDisplayController;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakController noteBacklightFactorSubstitutionFrom:originalFactor to:dimmedFactor];
    });
}

void NNPPhase7NotifyDisplayWake(void) {
    void (^reveal)(void) = ^{
        [NNPCurrentDisplayController noteDisplayWake];
        [[NNPController sharedController] revealCoverSheetControlsForWake];
    };
    if ([NSThread isMainThread]) reveal();
    else dispatch_async(dispatch_get_main_queue(), reveal);
}

BOOL NNPPhase7PresentNotificationSnakeAnimation(void) {
    if (![NSThread isMainThread]) return NO;
    return [[NNPController sharedController] showNotificationSnakeAnimation];
}
#endif

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NNPCurrentDisplayController = self;
    _lifecycleState = NNPDisplayLifecycleStateDisabled;
    _maximumDuration = 30.0;
    _unlimitedDuration = NO;
    _aodBrightnessMultiplier = 1.0f;
    NNPPhase7SetAODBrightnessMultiplier(_aodBrightnessMultiplier);
    NNPDiagnosticSetInteger(@"LockedVisibleLifecycle", _lifecycleState);
    NNPDiagnosticSetBool(@"Phase7AODPresentationActive", NO);
    NNPPhase7SetAODPresentationActive(NO);
    NNPDiagnosticSetBool(@"Phase7BacklightFactorSubstitution", NO);
    NNPPhase7UpdateForensicsState(_lifecycleState, self.deviceLocked, self.modeSubstitutionObserved, NO);
    return self;
}

- (void)setAODBrightnessMultiplier:(float)multiplier {
    float clamped = (float)MAX(1.0, MIN(4.0, multiplier));
    // Re-publish even when the Objective-C property is unchanged. The native
    // hook owns a separate atomic value, which can be reset during controller
    // reinitialization while this object's cached property remains unchanged.
    NNPPhase7SetAODBrightnessMultiplier(clamped);
    if (fabsf(_aodBrightnessMultiplier - clamped) < 0.001f) return;
    _aodBrightnessMultiplier = clamped;
    NNPDiagnosticSetDouble(@"Phase7AODBrightnessMultiplier", clamped);
#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE && NNP_PHASE7_DRY_RUN == 0
    // The native atomic affects future callbacks; update the active panel too.
    if (self.aodPresentationActive) NNPAODNitsBeginSession(self.sessionIdentifier, clamped);
#endif
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
    NNPPhase7UpdateForensicsState(_lifecycleState, self.deviceLocked, self.modeSubstitutionObserved, self.visibleDurationTimer != nil);
    NNPDiagnosticSetInteger(@"LockedVisibleLifecycle", state);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY lifecycle state=%ld", (long)state]);
    if (self.stateChangedHandler) self.stateChangedHandler();
}

- (void)setAODPresentationActive:(BOOL)active {
    if (_aodPresentationActive == active) return;
    _aodPresentationActive = active;
    NNPPhase7SetAODPresentationActive(active);
    NNPNotificationDiagnosticsSetDisplayState(self.deviceLocked, _aodPresentationActive);
    NNPDiagnosticSetBool(@"Phase7AODPresentationActive", active);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY AOD presentation active=%@", active ? @"YES" : @"NO"]);
#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE && NNP_PHASE7_DRY_RUN == 0
    if (active) NNPAODNitsBeginSession(self.sessionIdentifier, self.aodBrightnessMultiplier);
    else NNPAODNitsEndSession();
#endif
    if (self.stateChangedHandler) self.stateChangedHandler();
}

- (void)setUnlimitedDuration:(BOOL)unlimitedDuration {
    if (_unlimitedDuration == unlimitedDuration) return;
    _unlimitedDuration = unlimitedDuration;
    NNPDiagnosticSetBool(@"Phase7UnlimitedDuration", unlimitedDuration);
    if (self.lifecycleState == NNPDisplayLifecycleStateActive) {
        if (unlimitedDuration) [self cancelVisibleDurationTimer:@"unlimited-enabled"];
        else [self startVisibleDurationTimer];
    }
}

- (void)noteDisplayWake {
    [self setAODPresentationActive:NO];
}

- (void)setDeviceLocked:(BOOL)deviceLocked {
    if (_deviceLocked == deviceLocked) return;
    BOOL wasLocked = _deviceLocked;
    _deviceLocked = deviceLocked;
    NNPNotificationDiagnosticsSetDisplayState(_deviceLocked, self.aodPresentationActive);
    NNPPhase7UpdateForensicsState(_lifecycleState, _deviceLocked, self.modeSubstitutionObserved, self.visibleDurationTimer != nil);
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
    NNPDiagnosticSetDouble(@"Phase7TimerDeadline", 0.0);
    NNPPhase7UpdateForensicsState(_lifecycleState, self.deviceLocked, self.modeSubstitutionObserved, NO);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY timer cancelled session=%@ reason=%@", self.sessionIdentifier ?: @"none", reason ?: @"unknown"]);
}

- (void)startVisibleDurationTimer {
    [self cancelVisibleDurationTimer:@"replace"];
    if (self.unlimitedDuration) {
        NNPDiagnosticSetDouble(@"Phase7TimerDeadline", 0.0);
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY time limit disabled session=%@", self.sessionIdentifier ?: @"none"]);
        return;
    }
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
    NNPPhase7UpdateForensicsState(_lifecycleState, self.deviceLocked, self.modeSubstitutionObserved, YES);
}

- (void)activateLockedVisibleSessionIfReady {
    if (self.lifecycleState != NNPDisplayLifecycleStatePreparing || !self.deviceLocked || !self.modeSubstitutionObserved) return;
    self.lockedVisibleActivated = YES;
    [self setAODPresentationActive:YES];
    NNPDiagnosticSetBool(@"Phase7LockedVisibleActive", YES);
    NNPDiagnosticSetDouble(@"Phase7LockedTimestamp", NSDate.date.timeIntervalSince1970);
    self.lifecycleState = NNPDisplayLifecycleStateActive;
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY locked-visible active session=%@ modeSubstitution=YES", self.sessionIdentifier ?: @"none"]);
    [self startVisibleDurationTimer];
}

- (void)noteBacklightFactorSubstitutionFrom:(float)originalFactor to:(float)dimmedFactor {
    if (self.lifecycleState != NNPDisplayLifecycleStatePreparing && self.lifecycleState != NNPDisplayLifecycleStateActive) return;
    self.modeSubstitutionObserved = YES;
    NNPPhase7UpdateForensicsState(_lifecycleState, self.deviceLocked, self.modeSubstitutionObserved, self.visibleDurationTimer != nil);
    NNPDiagnosticSetBool(@"Phase7BacklightFactorSubstitution", YES);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"DISPLAY backlight factor adjusted session=%@ original=%.6f dimmed=%.6f deviceLocked=%@", self.sessionIdentifier ?: @"none", originalFactor, dimmedFactor, self.deviceLocked ? @"YES" : @"NO"]);
    if (self.deviceLocked && self.lifecycleState == NNPDisplayLifecycleStateActive) {
        [self setAODPresentationActive:YES];
    }
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
    if (!NNPPhase7EnsureBacklightFactorHook()) {
        self.lifecycleState = NNPDisplayLifecycleStateFailed;
        NNPDiagnosticSetBool(@"Phase7BacklightFactorSubstitution", NO);
        NNPDiagnosticLogTransition(@"DISPLAY experimental hook unavailable; no session armed");
        return NO;
    }
    self.sessionGeneration = ++NNPNextSessionGeneration;
    self.sessionIdentifier = [NSString stringWithFormat:@"S%lu", (unsigned long)self.sessionGeneration];
    self.modeSubstitutionObserved = NO;
    self.lockedVisibleActivated = NO;
    [self cancelVisibleDurationTimer:@"new-session"];
    NNPPhase7SetSessionID(self.sessionIdentifier);
    NNPDiagnosticSetBool(@"Phase7BacklightFactorSubstitution", NO);
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
    [self setAODPresentationActive:NO];
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
