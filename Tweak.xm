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
#if NNP_PHASE2D2_DIAGNOSTIC || NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT || NNP_PHASE2G_OBSERVER
#import "NNPDiagnostics.h"
#endif

%ctor {
#if NNP_PHASE2D2_DIAGNOSTIC || NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT || NNP_PHASE2G_OBSERVER
    NNPDiagnosticRecordStartup([NSString stringWithFormat:@"TWEAK_LOADED pid=%d process=%@ bundle=%@", getpid(), NSProcessInfo.processInfo.processName ?: @"unknown", NSBundle.mainBundle.bundleIdentifier ?: @"unknown"]);
#else
    NNPDiagnosticRecordStartup([NSString stringWithFormat:@"TWEAK_LOADED pid=%d process=%@ bundle=%@", getpid(), NSProcessInfo.processInfo.processName ?: @"unknown", NSBundle.mainBundle.bundleIdentifier ?: @"unknown"]);
#endif
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
#if NNP_PHASE2J_READONLY_RUNTIME
        gNNPBackBoardReadOnlyDiagnostics = [NNPBackBoardReadOnlyDiagnostics new];
        [gNNPBackBoardReadOnlyDiagnostics start];
#endif
        [[NNPController sharedController] install];
    });
}
