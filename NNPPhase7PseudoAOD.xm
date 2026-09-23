#import "NNPDisplayController.h"
#import "NNPDiagnostics.h"
#import <objc/message.h>

static volatile BOOL gNNPPhase7Armed = NO;
static volatile BOOL gNNPPhase7Restore = NO;
static __thread BOOL gNNPPhase7InsideTransitionHook = NO;
// The provider is owned by the system display service. A raw unsafe reference
// could become dangling before timeout or cleanup restores mode 0. Weak
// ownership fails open when the provider has gone away instead of messaging a
// released SpringBoard object.
static __weak id gNNPPhase7Provider;

void NNPPhase7SetExperimentArmed(BOOL armed) {
    gNNPPhase7Armed = armed;
    if (!armed) gNNPPhase7Restore = NO;
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 armed=%@", armed ? @"YES" : @"NO"]);
}

void NNPPhase7RestoreNormalDisplay(void) {
    id provider = gNNPPhase7Provider;
    if (!provider) { NNPDiagnosticLogTransition(@"PHASE7 restore requested but provider unavailable"); return; }
    SEL selector = NSSelectorFromString(@"transitionToDisplayMode:withDuration:");
    if (![provider respondsToSelector:selector]) { NNPDiagnosticLogTransition(@"PHASE7 restore requested but selector unavailable"); return; }
    NNPDiagnosticLogTransition(@"PHASE7 restore displayMode=0 requested");
    gNNPPhase7Restore = YES;
    ((void (*)(id, SEL, long long, double))objc_msgSend)(provider, selector, 0, 0.0);
    gNNPPhase7Restore = NO;
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
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"PHASE7 displayMode 0 -> 4 duration=%.3f", duration]);
        %orig(4, duration);
        gNNPPhase7InsideTransitionHook = NO;
        return;
    }
    %orig;
    gNNPPhase7InsideTransitionHook = NO;
}
%end
