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
@property(nonatomic, copy) void (^stateChangedHandler)(void);
@property(nonatomic) BOOL deviceLocked;
@property(nonatomic) NSTimeInterval maximumDuration;
- (BOOL)isLockedVisibleSupported;
- (BOOL)startLockedVisibleMode;
- (void)stopLockedVisibleMode;
@end

// Implemented only by the Phase 7 experimental build. They are no-ops in
// the production implementation.
FOUNDATION_EXPORT void NNPPhase7SetExperimentArmed(BOOL armed);
FOUNDATION_EXPORT void NNPPhase7SetSessionID(NSString *sessionID);
FOUNDATION_EXPORT void NNPPhase7NotifyBacklightFactorSubstitution(float originalFactor, float dimmedFactor);
FOUNDATION_EXPORT void NNPPhase7NotifyDisplayWake(void);
FOUNDATION_EXPORT void NNPPhase7StartIncidentDiagnostics(void);
FOUNDATION_EXPORT BOOL NNPPhase7EnsureBacklightFactorHook(void);
FOUNDATION_EXPORT void NNPPhase7UpdateForensicsState(NSInteger lifecycleState, BOOL deviceLocked, BOOL modeSubstitutionObserved, BOOL timerActive);
