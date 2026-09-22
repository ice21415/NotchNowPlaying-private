#import <UIKit/UIKit.h>
#import <unistd.h>
#import "NNPController.h"
#import "NNPDiagnostics.h"
#ifndef NNP_PHASE2J_READONLY_RUNTIME
#define NNP_PHASE2J_READONLY_RUNTIME 0
#endif
#if NNP_PHASE2J_READONLY_RUNTIME
#import "NNPBackBoardReadOnlyDiagnostics.h"
static NNPBackBoardReadOnlyDiagnostics *gNNPBackBoardReadOnlyDiagnostics;
#endif
#ifndef NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
#define NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT 0
#endif
#ifndef NNP_PHASE2D2_DIAGNOSTIC
#define NNP_PHASE2D2_DIAGNOSTIC 0
#endif
#ifndef NNP_PHASE2G_OBSERVER
#define NNP_PHASE2G_OBSERVER 0
#endif
#ifndef NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG
#define NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG 0
#endif
#ifndef NNP_PHASE4A_CTOR_PREFERENCES_PROBE
#define NNP_PHASE4A_CTOR_PREFERENCES_PROBE 0
#endif
#ifndef NNP_PHASE4A_DELAYED_TRACE_PROBE
#define NNP_PHASE4A_DELAYED_TRACE_PROBE 0
#endif
#ifndef NNP_PHASE4A_UI_STATE_PROBE
#define NNP_PHASE4A_UI_STATE_PROBE 0
#endif
#ifndef NNP_PHASE4A_DELAYED_NOOP_TEST
#define NNP_PHASE4A_DELAYED_NOOP_TEST 0
#endif
#ifndef NNP_PHASE4A_DELAYED_STATIC_BOOL_TEST
#define NNP_PHASE4A_DELAYED_STATIC_BOOL_TEST 0
#endif
#ifndef NNP_PHASE4A_DELAYED_CFPREFERENCES_TEST
#define NNP_PHASE4A_DELAYED_CFPREFERENCES_TEST 0
#endif
#ifndef NNP_PHASE4A_LOCAL_NOOP_TEST
#define NNP_PHASE4A_LOCAL_NOOP_TEST 0
#endif
#ifndef NNP_PHASE4A_CROSS_FILE_NOOP_TEST
#define NNP_PHASE4A_CROSS_FILE_NOOP_TEST 0
#endif
#if NNP_PHASE4A_LOCAL_NOOP_TEST
static __attribute__((noinline)) void NNPLocalNoop(void) {
}
#endif
#if NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG || NNP_PHASE4A_CTOR_PREFERENCES_PROBE || NNP_PHASE4A_DELAYED_TRACE_PROBE || NNP_PHASE4A_UI_STATE_PROBE || NNP_PHASE4A_DELAYED_CFPREFERENCES_TEST || NNP_PHASE4A_CROSS_FILE_NOOP_TEST
#import "NNPPhase4AReadOnlyBacklight.h"
#endif
#if NNP_PHASE2D2_DIAGNOSTIC || NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT || NNP_PHASE2G_OBSERVER
#import "NNPDiagnostics.h"
#endif

%ctor {
#if NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG
    NNPPhase4ASetDiagnosticValue(@"BuildIdentity", NNPPhase4ABuildIdentity());
    NNPPhase4ASetDiagnosticBoolean(@"CtorEntered", YES);
    NNPPhase4ATrace(@"PHASE4A_COMPILED");
    NNPPhase4ATrace(@"CTOR_ENTER");
#elif NNP_PHASE4A_CTOR_PREFERENCES_PROBE
    NNPPhase4ASetDiagnosticBoolean(@"CtorPreferencesProbeEntered", YES);
#endif
#if NNP_PHASE2D2_DIAGNOSTIC || NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT || NNP_PHASE2G_OBSERVER
    NNPDiagnosticRecordStartup([NSString stringWithFormat:@"TWEAK_LOADED pid=%d process=%@ bundle=%@", getpid(), NSProcessInfo.processInfo.processName ?: @"unknown", NSBundle.mainBundle.bundleIdentifier ?: @"unknown"]);
#else
    NNPDiagnosticRecordStartup([NSString stringWithFormat:@"TWEAK_LOADED pid=%d process=%@ bundle=%@", getpid(), NSProcessInfo.processInfo.processName ?: @"unknown", NSBundle.mainBundle.bundleIdentifier ?: @"unknown"]);
#endif
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
#if NNP_PHASE4A_DELAYED_NOOP_TEST
        return;
#elif NNP_PHASE4A_DELAYED_STATIC_BOOL_TEST
        static volatile BOOL reached = YES;
        (void)reached;
        return;
#elif NNP_PHASE4A_DELAYED_CFPREFERENCES_TEST
        NNPPhase4ASetDiagnosticBoolean(@"DelayedEntered", YES);
        return;
#else
#if NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG
        NNPPhase4ASetDiagnosticBoolean(@"PostStartupEntered", YES);
        NNPPhase4ATrace(@"POST_STARTUP_BLOCK_ENTER");
#endif
#if NNP_PHASE2J_READONLY_RUNTIME
        gNNPBackBoardReadOnlyDiagnostics = [NNPBackBoardReadOnlyDiagnostics new];
        [gNNPBackBoardReadOnlyDiagnostics start];
#endif
        [[NNPController sharedController] install];
#if NNP_PHASE4A_LOCAL_NOOP_TEST
        NNPLocalNoop();
#endif
#if NNP_PHASE4A_CROSS_FILE_NOOP_TEST
        NNPPhase4ANoop();
#endif
#if NNP_PHASE4A_UI_STATE_PROBE
        long long phase4AState = 0;
        BOOL phase4AReadOK = NNPPhase4AReadBacklightState(&phase4AState);
        NNPPhase4ASetUIState(phase4AReadOK, phase4AState);
#endif
#if NNP_PHASE4A_DELAYED_TRACE_PROBE
        NNPPhase4ATrace(@"DELAYED_TRACE_PROBE");
#endif
#if NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG
        NNPPhase4ASetDiagnosticBoolean(@"Phase4ACallBegin", YES);
        NNPPhase4ATrace(@"PHASE4A_CALL_BEGIN");
        NNPPhase4AStartReadOnlyBacklightObservation();
        NNPPhase4ASetDiagnosticBoolean(@"Phase4ACallReturned", YES);
        NNPPhase4ATrace(@"PHASE4A_CALL_RETURN");
#endif
#endif
    });
}
