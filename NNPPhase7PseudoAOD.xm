#import "NNPDisplayController.h"
#import "NNPDiagnostics.h"
#import <objc/message.h>

static volatile BOOL gNNPPhase7Armed = NO;
static volatile BOOL gNNPPhase7Restore = NO;
static __thread BOOL gNNPPhase7InsideTransitionHook = NO;
static NSString *gNNPPhase7SessionID = @"none";
// The provider is owned by the system display service. A raw unsafe reference
// could become dangling before timeout or cleanup restores mode 0. Weak
// ownership fails open when the provider has gone away instead of messaging a
// released SpringBoard object.
static __weak id gNNPPhase7Provider;

void NNPPhase7SetExperimentArmed(BOOL armed) {
    gNNPPhase7Armed = armed;
    if (!armed) gNNPPhase7Restore = NO;
    NNPDiagnosticSetBool(@"Phase7ExperimentArmed", armed);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 armed=%@ session=%@", armed ? @"YES" : @"NO", gNNPPhase7SessionID ?: @"none"]);
}

void NNPPhase7SetSessionID(NSString *sessionID) {
    gNNPPhase7SessionID = [sessionID.length ? sessionID : @"none" copy];
    NNPDiagnosticSetString(@"Phase7SessionID", gNNPPhase7SessionID);
}

BOOL NNPPhase7RestoreNormalDisplay(void) {
    id provider = gNNPPhase7Provider;
    if (!provider) { NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 restore failed session=%@ provider unavailable", gNNPPhase7SessionID ?: @"none"]); return NO; }
    SEL selector = NSSelectorFromString(@"transitionToDisplayMode:withDuration:");
    if (![provider respondsToSelector:selector]) { NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 restore failed session=%@ selector unavailable", gNNPPhase7SessionID ?: @"none"]); return NO; }
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 restore displayMode=0 requested session=%@", gNNPPhase7SessionID ?: @"none"]);
    gNNPPhase7Restore = YES;
    ((void (*)(id, SEL, long long, double))objc_msgSend)(provider, selector, 0, 0.0);
    gNNPPhase7Restore = NO;
    return YES;
}

%hook BLSHBacklightOSInterfaceProvider
- (void)transitionToDisplayMode:(long long)mode withDuration:(double)duration {
    gNNPPhase7Provider = self;
    if (gNNPPhase7InsideTransitionHook) {
        %orig;
        return;
    }
    gNNPPhase7InsideTransitionHook = YES;
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 display transition requested mode=%lld duration=%.3f armed=%@ restore=%@", mode, duration, gNNPPhase7Armed ? @"YES" : @"NO", gNNPPhase7Restore ? @"YES" : @"NO"]);
    if (gNNPPhase7Armed && !gNNPPhase7Restore && mode == 0) {
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
