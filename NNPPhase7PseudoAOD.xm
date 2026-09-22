#import "NNPDisplayController.h"
#import "NNPDiagnostics.h"
#import <objc/message.h>

static volatile BOOL gNNPPhase7Armed = NO;
static volatile BOOL gNNPPhase7Restore = NO;
static __unsafe_unretained id gNNPPhase7Provider;

void NNPPhase7SetExperimentArmed(BOOL armed) {
    gNNPPhase7Armed = armed;
    if (!armed) gNNPPhase7Restore = NO;
}

void NNPPhase7RestoreNormalDisplay(void) {
    id provider = gNNPPhase7Provider;
    if (!provider) return;
    SEL selector = NSSelectorFromString(@"transitionToDisplayMode:withDuration:");
    if (![provider respondsToSelector:selector]) return;
    gNNPPhase7Restore = YES;
    ((void (*)(id, SEL, long long, double))objc_msgSend)(provider, selector, 0, 0.0);
    gNNPPhase7Restore = NO;
}

%hook BLSHBacklightOSInterfaceProvider
- (void)transitionToDisplayMode:(long long)mode withDuration:(double)duration {
    gNNPPhase7Provider = self;
    if (gNNPPhase7Armed && !gNNPPhase7Restore && mode == 0) {
        NNPDiagnosticSetInteger(@"Phase7OriginalDisplayMode", mode);
        NNPDiagnosticSetInteger(@"Phase7SubstitutedDisplayMode", 4);
        NNPDiagnosticSetBool(@"Phase7ModeSubstitution", YES);
        NNPDiagnosticLog([NSString stringWithFormat:@"PHASE7 displayMode 0 -> 4 duration=%.3f", duration]);
        %orig(4, duration);
        return;
    }
    %orig;
}
%end
