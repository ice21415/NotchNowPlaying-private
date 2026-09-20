#import <UIKit/UIKit.h>
#import <unistd.h>
#import "NNPController.h"
#ifndef NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
#define NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT 0
#endif
#ifndef NNP_PHASE2D2_DIAGNOSTIC
#define NNP_PHASE2D2_DIAGNOSTIC 0
#endif
#if NNP_PHASE2D2_DIAGNOSTIC || NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
#import "NNPDiagnostics.h"
#endif

%ctor {
#if NNP_PHASE2D2_DIAGNOSTIC || NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
    NNPDiagnosticRecordStartup([NSString stringWithFormat:@"TWEAK_LOADED pid=%d process=%@ bundle=%@", getpid(), NSProcessInfo.processInfo.processName ?: @"unknown", NSBundle.mainBundle.bundleIdentifier ?: @"unknown"]);
#endif
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[NNPController sharedController] install];
    });
}
