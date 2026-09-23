#import "NNPDisplayController.h"
#import "NNPDiagnostics.h"

static volatile BOOL gNNPPhase7Armed = NO;
static __thread BOOL gNNPPhase7InsideTransitionHook = NO;
static NSString *gNNPPhase7SessionID = @"none";

void NNPPhase7SetExperimentArmed(BOOL armed) {
    gNNPPhase7Armed = armed;
    NNPDiagnosticSetBool(@"Phase7ExperimentArmed", armed);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 armed=%@ session=%@", armed ? @"YES" : @"NO", gNNPPhase7SessionID ?: @"none"]);
}

void NNPPhase7SetSessionID(NSString *sessionID) {
    gNNPPhase7SessionID = [sessionID.length ? sessionID : @"none" copy];
    NNPDiagnosticSetString(@"Phase7SessionID", gNNPPhase7SessionID);
}

%hook BLSHBacklightOSInterfaceProvider
- (void)transitionToDisplayMode:(long long)mode withDuration:(double)duration {
    if (!gNNPPhase7Armed) {
        %orig;
        return;
    }
    if (gNNPPhase7InsideTransitionHook) {
        %orig;
        return;
    }
    gNNPPhase7InsideTransitionHook = YES;
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 display transition requested mode=%lld duration=%.3f armed=YES session=%@", mode, duration, gNNPPhase7SessionID ?: @"none"]);
    if (mode == 0) {
        NNPDiagnosticSetInteger(@"Phase7OriginalDisplayMode", mode);
        NNPDiagnosticSetInteger(@"Phase7SubstitutedDisplayMode", 4);
        NNPDiagnosticSetBool(@"Phase7ModeSubstitution", YES);
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 displayMode 0 -> 4 duration=%.3f session=%@", duration, gNNPPhase7SessionID ?: @"none"]);
        %orig(4, duration);
        NNPPhase7NotifyDisplayModeSubstitution(mode, 4);
        gNNPPhase7InsideTransitionHook = NO;
        return;
    }
    %orig;
    gNNPPhase7InsideTransitionHook = NO;
}
%end
