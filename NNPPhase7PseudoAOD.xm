#import "NNPDisplayController.h"
#import "NNPDiagnostics.h"
#import "NNPNotificationDiagnostics.h"
#import <mach/mach_time.h>
#import <pthread.h>
#import <stdatomic.h>
#import <stdint.h>
#import <objc/runtime.h>
#import <math.h>
#import <string.h>
#import <dlfcn.h>
#import <ptrauth.h>

#ifndef NNP_PHASE7_DRY_RUN
#define NNP_PHASE7_DRY_RUN 0
#endif

typedef void (*NNPMSHookFunction)(void *symbol, void *replacement, void **result);

#if NNP_PHASE7_DRY_RUN != 2
typedef void (*NNPBacklightFactorFunction)(int displayID, float factor, float fadeDuration);
static NNPBacklightFactorFunction gNNPOriginalBacklightFactorFunction;
#endif

static _Atomic(bool) gNNPPhase7Armed = false;
static _Atomic(int) gNNPPhase7Lifecycle = NNPDisplayLifecycleStateDisabled;
static _Atomic(bool) gNNPPhase7DeviceLocked = false;
static _Atomic(bool) gNNPPhase7ModeSubstitutionObserved = false;
static _Atomic(bool) gNNPPhase7TimerActive = false;
static _Atomic(float) gNNPPhase7AODBrightnessMultiplier = 1.0f;
static _Atomic(float) gNNPPhase7BaseDimmedFactor = 0.0f;
static _Atomic(uint64_t) gNNPPhase7FactorCallCount = 0;
static _Atomic(float) gNNPPhase7LastFactorInput = 0.0f;
static _Atomic(float) gNNPPhase7LastFactorOutput = 0.0f;
static _Atomic(bool) gNNPPhase7LastFactorHadProvider = false;
static _Atomic(bool) gNNPPhase7BlankRequestSuppressed = false;
static _Atomic(bool) gNNPPhase7RevealOnWakePending = false;
static _Atomic(uint64_t) gNNPPhase7NotificationWakeSuppressionDeadlineTicks = 0;
static _Atomic(uint64_t) gNNPPhase7NotificationUnblankSuppressionDeadlineTicks = 0;
static const double NNPPhase7NotificationWakeSuppressionSeconds = 5.0;
static _Atomic(int) gNNPPhase7LastRequestedMode = -1;
static _Atomic(int) gNNPPhase7LastForwardedMode = -1;
static _Atomic(uint64_t) gNNPPhase7LastTransitionTicks = 0;
static _Atomic(uint64_t) gNNPPhase7IncidentDeadlineTicks = 0;
static _Atomic(uint64_t) gNNPPhase7LastMainHeartbeatTicks = 0;
static NSString *gNNPPhase7SessionID = @"none";
static dispatch_source_t gNNPPhase7HeartbeatTimer;
static dispatch_once_t gNNPPhase7HeartbeatOnce;
static mach_timebase_info_data_t gNNPPhase7Timebase;
#if NNP_PHASE7_DRY_RUN != 2
static _Atomic(void *) gNNPPhase7ProviderForFactorHook = NULL;
static _Atomic(bool) gNNPPhase7FactorWasSubstituted = false;
static _Atomic(float) gNNPPhase7OriginalFactor = 0.0f;
static _Atomic(float) gNNPPhase7SubstitutedFactor = 0.0f;
#endif

#if NNP_PHASE7_DRY_RUN != 2
typedef void (*NNPProviderTransitionIMP)(id self, SEL _cmd, long long mode, double duration);
typedef void (*NNPSetScreenBlankedFunction)(BOOL blanked);
typedef void (*NNPBacklightStateIMP)(id self, SEL _cmd, NSInteger state, NSInteger source, BOOL animated, id completion);
static NNPProviderTransitionIMP gNNPOriginalProviderTransition;
static NNPSetScreenBlankedFunction gNNPOriginalSetScreenBlanked;
static NNPBacklightStateIMP gNNPOriginalBacklightState;
static void NNPPhase7BacklightFactorReplacement(int displayID, float factor, float fadeDuration);
static void NNPPhase7ProviderTransitionReplacement(id self, SEL _cmd, long long mode, double duration);
static void NNPPhase7SetScreenBlankedReplacement(BOOL blanked);
static void NNPPhase7BacklightStateReplacement(id self, SEL _cmd, NSInteger state, NSInteger source, BOOL animated, id completion);

BOOL NNPPhase7EnsureBacklightFactorHook(void) {
    static dispatch_once_t onceToken;
    static BOOL installed;
    dispatch_once(&onceToken, ^{
        // Resolve ElleKit/Substrate compatibility at runtime. A direct
        // undefined MSHookFunction binding can keep SpringBoard from loading
        // the entire tweak on rootless/roothide injection environments.
        NNPMSHookFunction hookFunction = (NNPMSHookFunction)dlsym(RTLD_DEFAULT, "MSHookFunction");
        if (!hookFunction) {
            NNPDiagnosticSetBool(@"Phase7FactorHookInstalled", NO);
            NNPDiagnosticLog(@"PHASE7 MSHookFunction unavailable; feature remains fail-open");
            return;
        }
        const char *symbolName = "BKSHIDServicesSetBacklightFactorWithFadeDurationAsync";
        void *symbol = dlsym(RTLD_DEFAULT, symbolName);
        void *backBoardServices = NULL;
        if (!symbol) {
            backBoardServices = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY | RTLD_LOCAL);
            if (backBoardServices) symbol = dlsym(backBoardServices, symbolName);
        }
        if (!symbol) {
            NNPDiagnosticSetBool(@"Phase7FactorHookInstalled", NO);
            NNPDiagnosticLog(@"PHASE7 HID factor hook unavailable; runtime symbol lookup failed");
            return;
        }
        hookFunction(symbol, (void *)&NNPPhase7BacklightFactorReplacement, (void **)&gNNPOriginalBacklightFactorFunction);
        installed = gNNPOriginalBacklightFactorFunction != NULL;

        if (!backBoardServices) {
            backBoardServices = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY | RTLD_LOCAL);
        }
        void *blankedSymbol = dlsym(RTLD_DEFAULT, "BKSDisplayServicesSetScreenBlanked");
        if (!blankedSymbol && backBoardServices) {
            blankedSymbol = dlsym(backBoardServices, "BKSDisplayServicesSetScreenBlanked");
        }
        BOOL blankingHookInstalled = NO;
        if (blankedSymbol) {
            hookFunction(blankedSymbol, (void *)&NNPPhase7SetScreenBlankedReplacement,
                         (void **)&gNNPOriginalSetScreenBlanked);
            blankingHookInstalled = gNNPOriginalSetScreenBlanked != NULL;
        }
        NNPDiagnosticSetBool(@"Phase7BlankingHookInstalled", blankingHookInstalled);
        if (!blankingHookInstalled) {
            NNPDiagnosticLog(@"PHASE7 BKS screen-blank hook unavailable; experiment remains disarmed");
        }

        Class backlightControllerClass = NSClassFromString(@"SBBacklightController");
        SEL backlightStateSelector = NSSelectorFromString(@"setBacklightState:source:animated:completion:");
        Method backlightStateMethod = backlightControllerClass
            ? class_getInstanceMethod(backlightControllerClass, backlightStateSelector) : NULL;
        BOOL wakeHookInstalled = NO;
        if (backlightStateMethod) {
            IMP original = method_getImplementation(backlightStateMethod);
            const char *types = method_getTypeEncoding(backlightStateMethod);
            if (class_addMethod(backlightControllerClass, backlightStateSelector,
                                (IMP)NNPPhase7BacklightStateReplacement, types)) {
                gNNPOriginalBacklightState = (NNPBacklightStateIMP)original;
            } else {
                gNNPOriginalBacklightState = (NNPBacklightStateIMP)method_setImplementation(
                    backlightStateMethod, (IMP)NNPPhase7BacklightStateReplacement);
            }
            wakeHookInstalled = gNNPOriginalBacklightState != NULL;
        }
        NNPDiagnosticSetBool(@"Phase7WakeHookInstalled", wakeHookInstalled);
        NNPDiagnosticLog([NSString stringWithFormat:@"PHASE7 SpringBoard backlight wake hook %@ selector=%@",
                          wakeHookInstalled ? @"installed" : @"unavailable",
                          NSStringFromSelector(backlightStateSelector)]);

        Class providerClass = NSClassFromString(@"BLSHBacklightOSInterfaceProvider");
        SEL transitionSelector = NSSelectorFromString(@"transitionToDisplayMode:withDuration:");
        Method transitionMethod = providerClass ? class_getInstanceMethod(providerClass, transitionSelector) : NULL;
        if (installed && blankingHookInstalled && transitionMethod) {
            gNNPOriginalProviderTransition = (NNPProviderTransitionIMP)method_getImplementation(transitionMethod);
            if (!class_addMethod(providerClass, transitionSelector, (IMP)NNPPhase7ProviderTransitionReplacement, method_getTypeEncoding(transitionMethod))) {
                gNNPOriginalProviderTransition = (NNPProviderTransitionIMP)method_setImplementation(transitionMethod, (IMP)NNPPhase7ProviderTransitionReplacement);
            }
            installed = gNNPOriginalProviderTransition != NULL;
        } else {
            installed = NO;
        }
        NNPDiagnosticSetBool(@"Phase7FactorHookInstalled", installed);
        NNPDiagnosticLog([NSString stringWithFormat:@"PHASE7 deferred HID/provider/BKS-blank hooks %@ after runtime lookup", installed ? @"installed" : @"failed"]);
    });
    return installed;
}
#endif

static double NNPPhase7SecondsForTicks(uint64_t ticks) {
    if (!gNNPPhase7Timebase.denom) mach_timebase_info(&gNNPPhase7Timebase);
    return ((double)ticks * (double)gNNPPhase7Timebase.numer / (double)gNNPPhase7Timebase.denom) / 1000000000.0;
}

static uint64_t NNPPhase7TicksForSeconds(double seconds) {
    if (!gNNPPhase7Timebase.denom) mach_timebase_info(&gNNPPhase7Timebase);
    if (!gNNPPhase7Timebase.numer) return 0;
    return (uint64_t)(seconds * 1000000000.0 *
        (double)gNNPPhase7Timebase.denom / (double)gNNPPhase7Timebase.numer);
}

static NSString *NNPPhase7LifecycleName(int state) {
    switch (state) {
        case NNPDisplayLifecycleStateIdle: return @"idle";
        case NNPDisplayLifecycleStatePreparing: return @"preparing";
        case NNPDisplayLifecycleStateActive: return @"active";
        case NNPDisplayLifecycleStateStopping: return @"stopping";
        case NNPDisplayLifecycleStateUnsupported: return @"unsupported";
        case NNPDisplayLifecycleStateFailed: return @"failed";
        default: return @"disabled";
    }
}

void NNPPhase7UpdateForensicsState(NSInteger lifecycleState, BOOL deviceLocked, BOOL modeSubstitutionObserved, BOOL timerActive) {
    atomic_store_explicit(&gNNPPhase7Lifecycle, (int)lifecycleState, memory_order_relaxed);
    atomic_store_explicit(&gNNPPhase7DeviceLocked, deviceLocked, memory_order_relaxed);
    atomic_store_explicit(&gNNPPhase7ModeSubstitutionObserved, modeSubstitutionObserved, memory_order_relaxed);
    atomic_store_explicit(&gNNPPhase7TimerActive, timerActive, memory_order_relaxed);
    if (!deviceLocked) {
        atomic_store_explicit(&gNNPPhase7RevealOnWakePending, false, memory_order_release);
        atomic_store_explicit(&gNNPPhase7NotificationWakeSuppressionDeadlineTicks, 0, memory_order_release);
        atomic_store_explicit(&gNNPPhase7NotificationUnblankSuppressionDeadlineTicks, 0, memory_order_release);
    }
}

void NNPPhase7StartIncidentDiagnostics(void) {
    dispatch_once(&gNNPPhase7HeartbeatOnce, ^{
        mach_timebase_info(&gNNPPhase7Timebase);
        atomic_store_explicit(&gNNPPhase7LastMainHeartbeatTicks, mach_absolute_time(), memory_order_relaxed);
        dispatch_queue_t queue = dispatch_queue_create("com.user.notchnowplaying.phase7-forensics", DISPATCH_QUEUE_SERIAL);
        gNNPPhase7HeartbeatTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(gNNPPhase7HeartbeatTimer,
                                  dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                                  5 * NSEC_PER_SEC,
                                  NSEC_PER_SEC);
        dispatch_source_set_event_handler(gNNPPhase7HeartbeatTimer, ^{
            uint64_t now = mach_absolute_time();
            uint64_t deadline = atomic_load_explicit(&gNNPPhase7IncidentDeadlineTicks, memory_order_relaxed);
            if (!deadline || now > deadline) return;

            uint64_t mainTicks = atomic_load_explicit(&gNNPPhase7LastMainHeartbeatTicks, memory_order_relaxed);
            int requested = atomic_load_explicit(&gNNPPhase7LastRequestedMode, memory_order_relaxed);
            int forwarded = atomic_load_explicit(&gNNPPhase7LastForwardedMode, memory_order_relaxed);
            uint64_t transitionTicks = atomic_load_explicit(&gNNPPhase7LastTransitionTicks, memory_order_relaxed);
            uint64_t factorCalls = atomic_load_explicit(&gNNPPhase7FactorCallCount, memory_order_relaxed);
            float factorInput = atomic_load_explicit(&gNNPPhase7LastFactorInput, memory_order_relaxed);
            float factorOutput = atomic_load_explicit(&gNNPPhase7LastFactorOutput, memory_order_relaxed);
            bool factorHadProvider = atomic_load_explicit(&gNNPPhase7LastFactorHadProvider, memory_order_relaxed);
            NNPDiagnosticLog([NSString stringWithFormat:@"PHASE7_FORENSICS heartbeat uptime=%.3f armed=%@ lifecycle=%@ locked=%@ substituted=%@ timerActive=%@ lastMode=%d->%d lastModeAge=%.3f mainQueueAge=%.3f factorCalls=%llu lastFactor=%.5f->%.5f provider=%@",
                              NNPPhase7SecondsForTicks(now),
                              atomic_load_explicit(&gNNPPhase7Armed, memory_order_relaxed) ? @"YES" : @"NO",
                              NNPPhase7LifecycleName(atomic_load_explicit(&gNNPPhase7Lifecycle, memory_order_relaxed)),
                              atomic_load_explicit(&gNNPPhase7DeviceLocked, memory_order_relaxed) ? @"YES" : @"NO",
                              atomic_load_explicit(&gNNPPhase7ModeSubstitutionObserved, memory_order_relaxed) ? @"YES" : @"NO",
                              atomic_load_explicit(&gNNPPhase7TimerActive, memory_order_relaxed) ? @"YES" : @"NO",
                              requested, forwarded,
                              transitionTicks ? NNPPhase7SecondsForTicks(now - transitionTicks) : -1.0,
                              mainTicks ? NNPPhase7SecondsForTicks(now - mainTicks) : -1.0,
                              (unsigned long long)factorCalls, factorInput, factorOutput,
                              factorHadProvider ? @"YES" : @"NO"]);

            dispatch_async(dispatch_get_main_queue(), ^{
                atomic_store_explicit(&gNNPPhase7LastMainHeartbeatTicks, mach_absolute_time(), memory_order_relaxed);
            });
        });
        dispatch_resume(gNNPPhase7HeartbeatTimer);
        NNPDiagnosticLog(@"PHASE7_FORENSICS heartbeat monitor started interval=5s captureWindow=120s mainQueueProbe=YES");
    });
}

void NNPPhase7SetExperimentArmed(BOOL armed) {
    bool wasArmed = atomic_exchange_explicit(&gNNPPhase7Armed, armed, memory_order_acq_rel);
    if (armed && !wasArmed) {
        atomic_store_explicit(&gNNPPhase7BaseDimmedFactor, 0.0f, memory_order_relaxed);
        atomic_store_explicit(&gNNPPhase7FactorCallCount, 0, memory_order_relaxed);
        atomic_store_explicit(&gNNPPhase7LastFactorInput, 0.0f, memory_order_relaxed);
        atomic_store_explicit(&gNNPPhase7LastFactorOutput, 0.0f, memory_order_relaxed);
        atomic_store_explicit(&gNNPPhase7LastFactorHadProvider, false, memory_order_relaxed);
    }
#if NNP_PHASE7_DRY_RUN != 2
    if (!armed && wasArmed &&
        atomic_exchange_explicit(&gNNPPhase7BlankRequestSuppressed, false, memory_order_acq_rel) &&
        atomic_load_explicit(&gNNPPhase7DeviceLocked, memory_order_relaxed)) {
        NNPSetScreenBlankedFunction original = gNNPOriginalSetScreenBlanked;
        if (original) {
            NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 experiment ended while locked; restoring BKS blank overlay session=%@",
                                        gNNPPhase7SessionID ?: @"none"]);
            original(YES);
        }
    }
    if (!armed) {
        atomic_store_explicit(&gNNPPhase7RevealOnWakePending, false, memory_order_release);
        atomic_store_explicit(&gNNPPhase7NotificationWakeSuppressionDeadlineTicks, 0, memory_order_release);
        atomic_store_explicit(&gNNPPhase7NotificationUnblankSuppressionDeadlineTicks, 0, memory_order_release);
    }
#endif
    NNPDiagnosticSetBool(@"Phase7ExperimentArmed", armed);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 armed=%@ session=%@", armed ? @"YES" : @"NO", gNNPPhase7SessionID ?: @"none"]);
}

void NNPPhase7SetSessionID(NSString *sessionID) {
    gNNPPhase7SessionID = [sessionID.length ? sessionID : @"none" copy];
    NNPDiagnosticSetString(@"Phase7SessionID", gNNPPhase7SessionID);
}

void NNPPhase7SetAODBrightnessMultiplier(float multiplier) {
    float safeMultiplier = isfinite(multiplier) ? fminf(4.0f, fmaxf(1.0f, multiplier)) : 1.0f;
    atomic_store_explicit(&gNNPPhase7AODBrightnessMultiplier, safeMultiplier, memory_order_release);
    NNPDiagnosticSetDouble(@"Phase7AODBrightnessMultiplier", safeMultiplier);
}

#if NNP_PHASE7_DRY_RUN != 2
static BOOL NNPPhase7ReadDimmedFactor(void *providerObject, float *factorOut) {
    if (!providerObject || !factorOut) return NO;
    id provider = (__bridge id)providerObject;
    Ivar dimmedFactorIvar = class_getInstanceVariable(object_getClass(provider), "_backlightDimmedFactor");
    if (!dimmedFactorIvar) return NO;
    ptrdiff_t offset = ivar_getOffset(dimmedFactorIvar);
    if (offset <= 0) return NO;
    float value = 0.0f;
    memcpy(&value, (const uint8_t *)(__bridge const void *)provider + offset, sizeof(value));
    if (!isfinite(value) || value <= 0.0f || value >= 1.0f) return NO;
    *factorOut = value;
    return YES;
}

static void NNPPhase7BacklightFactorReplacement(int displayID, float factor, float fadeDuration) {
    void *provider = atomic_load_explicit(&gNNPPhase7ProviderForFactorHook, memory_order_acquire);
    bool armed = atomic_load_explicit(&gNNPPhase7Armed, memory_order_acquire);
    uint64_t callCount = armed
        ? atomic_fetch_add_explicit(&gNNPPhase7FactorCallCount, 1, memory_order_relaxed) + 1
        : 0;
    float incomingFactor = factor;
    BOOL shouldSubstitute = displayID == 1 && factor == 0.0f && armed;
    if (shouldSubstitute) {
        float dimmedFactor = 0.0f;
        if (!NNPPhase7ReadDimmedFactor(provider, &dimmedFactor)) {
            dimmedFactor = atomic_load_explicit(&gNNPPhase7BaseDimmedFactor, memory_order_relaxed);
        } else {
            atomic_store_explicit(&gNNPPhase7BaseDimmedFactor, dimmedFactor, memory_order_relaxed);
        }
        if (isfinite(dimmedFactor) && dimmedFactor > 0.0f && dimmedFactor < 1.0f) {
            float multiplier = atomic_load_explicit(&gNNPPhase7AODBrightnessMultiplier, memory_order_acquire);
            float aodFactor = fminf(0.20f, dimmedFactor * multiplier);
            atomic_store_explicit(&gNNPPhase7FactorWasSubstituted, true, memory_order_release);
            atomic_store_explicit(&gNNPPhase7OriginalFactor, factor, memory_order_relaxed);
            atomic_store_explicit(&gNNPPhase7SubstitutedFactor, aodFactor, memory_order_relaxed);
            factor = aodFactor;

            float previousOutput = atomic_exchange_explicit(&gNNPPhase7LastFactorOutput, factor, memory_order_relaxed);
            atomic_store_explicit(&gNNPPhase7LastFactorInput, incomingFactor, memory_order_relaxed);
            atomic_store_explicit(&gNNPPhase7LastFactorHadProvider, provider != NULL, memory_order_relaxed);
            if (callCount <= 8 || fabsf(previousOutput - factor) > 0.0001f) {
                NNPDiagnosticLog([NSString stringWithFormat:@"PHASE7 factor callback #%llu display=%d input=%.6f output=%.6f baseDim=%.6f multiplier=%.2fx provider=%@ armed=YES",
                                  (unsigned long long)callCount, displayID, incomingFactor, factor,
                                  dimmedFactor, multiplier, provider ? @"YES" : @"NO"]);
            }
        } else {
            atomic_store_explicit(&gNNPPhase7LastFactorInput, incomingFactor, memory_order_relaxed);
            atomic_store_explicit(&gNNPPhase7LastFactorOutput, factor, memory_order_relaxed);
            atomic_store_explicit(&gNNPPhase7LastFactorHadProvider, provider != NULL, memory_order_relaxed);
            if (callCount <= 8) {
                NNPDiagnosticLog([NSString stringWithFormat:@"PHASE7 factor callback #%llu display=%d input=%.6f passed through; dimmed factor unavailable provider=%@",
                                  (unsigned long long)callCount, displayID, incomingFactor, provider ? @"YES" : @"NO"]);
            }
        }
    } else if (armed) {
        atomic_store_explicit(&gNNPPhase7LastFactorInput, incomingFactor, memory_order_relaxed);
        atomic_store_explicit(&gNNPPhase7LastFactorOutput, factor, memory_order_relaxed);
        atomic_store_explicit(&gNNPPhase7LastFactorHadProvider, provider != NULL, memory_order_relaxed);
    }
    if (gNNPOriginalBacklightFactorFunction) {
        gNNPOriginalBacklightFactorFunction(displayID, factor, fadeDuration);
    }
}

static void NNPPhase7SetScreenBlankedReplacement(BOOL blanked) {
    NNPSetScreenBlankedFunction original = gNNPOriginalSetScreenBlanked;
    if (!original) return;

    void *returnAddress = __builtin_return_address(0);
    IMP caller = ptrauth_strip((IMP)returnAddress, ptrauth_key_function_pointer);
    Dl_info callerInfo = {0};
    BOOL fromBacklightServicesHost =
        dladdr((const void *)caller, &callerInfo) != 0 && callerInfo.dli_fname &&
        strstr(callerInfo.dli_fname, "/BacklightServicesHost.framework/") != NULL;

    if (!blanked && fromBacklightServicesHost) {
        uint64_t deadline = atomic_load_explicit(&gNNPPhase7NotificationUnblankSuppressionDeadlineTicks,
                                                  memory_order_acquire);
        uint64_t now = mach_absolute_time();
        if (deadline && now <= deadline &&
            atomic_load_explicit(&gNNPPhase7Armed, memory_order_acquire) &&
            atomic_load_explicit(&gNNPPhase7DeviceLocked, memory_order_acquire)) {
            NNPDiagnosticLogTransition(@"PHASE7 suppressed paired BKS unblank after notification wake replacement");
            return;
        }
        if (deadline) {
            atomic_store_explicit(&gNNPPhase7NotificationUnblankSuppressionDeadlineTicks, 0,
                                  memory_order_release);
        }
    }

    BOOL suppress = blanked && fromBacklightServicesHost &&
        atomic_load_explicit(&gNNPPhase7Armed, memory_order_relaxed);
    if (suppress) {
        atomic_store_explicit(&gNNPPhase7BlankRequestSuppressed, true, memory_order_release);
        atomic_store_explicit(&gNNPPhase7RevealOnWakePending, true, memory_order_release);
        uintptr_t callerOffset = callerInfo.dli_fbase
            ? (uintptr_t)caller - (uintptr_t)callerInfo.dli_fbase : 0;
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 suppressed BKS screen blank request caller=%s+0x%llx; BLS state and display mode unchanged session=%@",
                                    callerInfo.dli_fname,
                                    (unsigned long long)callerOffset,
                                    gNNPPhase7SessionID ?: @"none"]);
        return;
    }
    if (!blanked) {
        atomic_store_explicit(&gNNPPhase7BlankRequestSuppressed, false, memory_order_release);
        bool shouldReveal = fromBacklightServicesHost &&
            atomic_load_explicit(&gNNPPhase7Armed, memory_order_acquire) &&
            atomic_load_explicit(&gNNPPhase7DeviceLocked, memory_order_acquire) &&
            atomic_exchange_explicit(&gNNPPhase7RevealOnWakePending, false, memory_order_acq_rel);
        if (shouldReveal) {
            NNPDiagnosticLogTransition(@"PHASE7 BLS unblank received after suppressed lock blank; revealing native Lock Screen");
            NNPPhase7NotifyDisplayWake();
        }
    }
    original(blanked);
}

static void NNPPhase7BacklightStateReplacement(id self, SEL _cmd, NSInteger state, NSInteger source, BOOL animated, id completion) {
    NNPBacklightStateIMP original = gNNPOriginalBacklightState;
    if (!original) return;

    bool armed = atomic_load_explicit(&gNNPPhase7Armed, memory_order_acquire);
    bool locked = atomic_load_explicit(&gNNPPhase7DeviceLocked, memory_order_acquire);
    bool activeAOD = atomic_load_explicit(&gNNPPhase7Lifecycle, memory_order_acquire) == NNPDisplayLifecycleStateActive &&
        atomic_load_explicit(&gNNPPhase7ModeSubstitutionObserved, memory_order_acquire);

    // A single notification can produce a second state=1 request after its
    // first request was intercepted. Keep that follow-on request from waking
    // SpringBoard for the duration of the snake animation. Physical-button
    // wakes use a different source and still reveal the native Lock Screen.
    if (state == 1) {
        uint64_t deadline = atomic_load_explicit(&gNNPPhase7NotificationWakeSuppressionDeadlineTicks,
                                                  memory_order_acquire);
        if (deadline) {
            uint64_t now = mach_absolute_time();
            if (now <= deadline && NNPNotificationDiagnosticsIsNotificationBacklightSource(source) && armed && locked) {
                NNPDiagnosticLogTransition([NSString stringWithFormat:
                    @"PHASE7 suppressed follow-on notification backlight wake state=%ld source=%ld while snake animation is active",
                    (long)state, (long)source]);
                return;
            }
            atomic_store_explicit(&gNNPPhase7NotificationWakeSuppressionDeadlineTicks, 0,
                                  memory_order_release);
            atomic_store_explicit(&gNNPPhase7NotificationUnblankSuppressionDeadlineTicks, 0,
                                  memory_order_release);
        }
    }

    bool notificationWakeMatched = NNPNotificationDiagnosticsConsumeWakeForSnakeAnimation(state, source);

    if (state == 1 && armed && locked && activeAOD && notificationWakeMatched) {
        if (NNPPhase7PresentNotificationSnakeAnimation()) {
            uint64_t now = mach_absolute_time();
            uint64_t graceTicks = NNPPhase7TicksForSeconds(NNPPhase7NotificationWakeSuppressionSeconds);
            atomic_store_explicit(&gNNPPhase7NotificationWakeSuppressionDeadlineTicks,
                                  graceTicks ? now + graceTicks : 0, memory_order_release);
            uint64_t unblankGraceTicks = NNPPhase7TicksForSeconds(2.0);
            atomic_store_explicit(&gNNPPhase7NotificationUnblankSuppressionDeadlineTicks,
                                  unblankGraceTicks ? now + unblankGraceTicks : 0, memory_order_release);
            NNPDiagnosticLogTransition(@"PHASE7 kept AOD active and replaced correlated notification wake with snake animation");
            // The lock session is already active; omitting this correlated wake
            // request keeps the pseudo-AOD presentation and lock state intact.
            return;
        }
        NNPDiagnosticLogTransition(@"PHASE7 notification wake animation unavailable; passing wake request through");
    }

    if (state == 1) {
        atomic_store_explicit(&gNNPPhase7NotificationWakeSuppressionDeadlineTicks, 0, memory_order_release);
        atomic_store_explicit(&gNNPPhase7NotificationUnblankSuppressionDeadlineTicks, 0, memory_order_release);
    }

    bool shouldReveal = state == 1 &&
        armed && locked &&
        atomic_exchange_explicit(&gNNPPhase7RevealOnWakePending, false, memory_order_acq_rel);
    if (shouldReveal) {
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 SpringBoard backlight state=%ld source=%ld; revealing native Lock Screen before wake transition",
                                   (long)state, (long)source]);
        NNPPhase7NotifyDisplayWake();
    }
    original(self, _cmd, state, source, animated, completion);
}

static void NNPPhase7ProviderTransitionReplacement(id self, SEL _cmd, long long mode, double duration) {
    NNPProviderTransitionIMP original = gNNPOriginalProviderTransition;
    if (!original) return;
    if (mode != 0 || !atomic_load_explicit(&gNNPPhase7Armed, memory_order_relaxed)) {
        original(self, _cmd, mode, duration);
        return;
    }

    uint64_t now = mach_absolute_time();
    if (!gNNPPhase7Timebase.denom) mach_timebase_info(&gNNPPhase7Timebase);
    uint64_t windowTicks = (uint64_t)(120.0 * 1000000000.0 * (double)gNNPPhase7Timebase.denom / (double)gNNPPhase7Timebase.numer);
    atomic_store_explicit(&gNNPPhase7IncidentDeadlineTicks, now + windowTicks, memory_order_relaxed);
    atomic_store_explicit(&gNNPPhase7LastRequestedMode, (int)mode, memory_order_relaxed);
    atomic_store_explicit(&gNNPPhase7LastForwardedMode, (int)mode, memory_order_relaxed);
    atomic_store_explicit(&gNNPPhase7LastTransitionTicks, now, memory_order_relaxed);

    void *previousProvider = atomic_exchange_explicit(&gNNPPhase7ProviderForFactorHook, (__bridge void *)self, memory_order_acq_rel);
    bool previousAdjusted = atomic_exchange_explicit(&gNNPPhase7FactorWasSubstituted, false, memory_order_acq_rel);
    float previousOriginal = atomic_load_explicit(&gNNPPhase7OriginalFactor, memory_order_relaxed);
    float previousSubstituted = atomic_load_explicit(&gNNPPhase7SubstitutedFactor, memory_order_relaxed);
    original(self, _cmd, mode, duration);
    atomic_store_explicit(&gNNPPhase7ProviderForFactorHook, previousProvider, memory_order_release);

    atomic_store_explicit(&gNNPPhase7LastTransitionTicks, mach_absolute_time(), memory_order_relaxed);
    bool factorWasSubstituted = atomic_load_explicit(&gNNPPhase7FactorWasSubstituted, memory_order_acquire);
    float originalFactor = atomic_load_explicit(&gNNPPhase7OriginalFactor, memory_order_relaxed);
    float substitutedFactor = atomic_load_explicit(&gNNPPhase7SubstitutedFactor, memory_order_relaxed);
    if (factorWasSubstituted) {
        NNPDiagnosticSetDouble(@"Phase7SystemDimmedBacklightFactor", atomic_load_explicit(&gNNPPhase7BaseDimmedFactor, memory_order_relaxed));
        NNPDiagnosticSetDouble(@"Phase7OriginalBacklightFactor", originalFactor);
        NNPDiagnosticSetDouble(@"Phase7DimmedBacklightFactor", substitutedFactor);
        NNPDiagnosticSetDouble(@"Phase7AODBrightnessMultiplier", atomic_load_explicit(&gNNPPhase7AODBrightnessMultiplier, memory_order_relaxed));
        NNPDiagnosticSetBool(@"Phase7BacklightFactorSubstitution", YES);
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 HID backlight factor %.6f -> %.6f (systemDim=%.6f AODMultiplier=%.2fx); displayMode remained 0 duration=%.3f session=%@",
                                    originalFactor, substitutedFactor, atomic_load_explicit(&gNNPPhase7BaseDimmedFactor, memory_order_relaxed), atomic_load_explicit(&gNNPPhase7AODBrightnessMultiplier, memory_order_relaxed), duration, gNNPPhase7SessionID ?: @"none"]);
        NNPPhase7NotifyBacklightFactorSubstitution(originalFactor, substitutedFactor);
    } else {
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 native mode 0 passed through; dim factor unavailable or not applied duration=%.3f", duration]);
    }
    atomic_store_explicit(&gNNPPhase7FactorWasSubstituted, previousAdjusted, memory_order_release);
    atomic_store_explicit(&gNNPPhase7OriginalFactor, previousOriginal, memory_order_relaxed);
    atomic_store_explicit(&gNNPPhase7SubstitutedFactor, previousSubstituted, memory_order_relaxed);
}
#else
BOOL NNPPhase7EnsureBacklightFactorHook(void) { return NO; }
#endif
