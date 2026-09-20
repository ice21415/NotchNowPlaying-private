#import <UIKit/UIKit.h>
#import "NNPController.h"
#if NNP_PHASE2D2_DIAGNOSTIC
#import "NNPDiagnostics.h"
#endif

%ctor {
#if NNP_PHASE2D2_DIAGNOSTIC
    NNPDiagnosticLog([NSString stringWithFormat:@"TWEAK_LOADED bundle=%@", NSBundle.mainBundle.bundleIdentifier ?: @"unknown"]);
#endif
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[NNPController sharedController] install];
    });
}
