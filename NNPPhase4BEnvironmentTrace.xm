#import <Foundation/Foundation.h>

static CFStringRef const NNPPhase4BEnvironmentDomain = CFSTR("com.user.notchnowplaying.phase4b");
static long long gNNPPhase4BEnvironmentSequence;

static void NNPPhase4BEnvironmentSet(NSString *key, id value) {
    if (!key.length || !value) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             NNPPhase4BEnvironmentDomain);
    CFPreferencesAppSynchronize(NNPPhase4BEnvironmentDomain);
}

%hook BLSHBacklightEnvironmentStateMachine

- (void)setPresentation:(id)presentation withTargetBacklightState:(long long)state {
    %orig;
    gNNPPhase4BEnvironmentSequence++;
    gNNPPhase4BEnvironmentSequence;
    NNPPhase4BEnvironmentSet(@"EnvSetPresentationCount", @(gNNPPhase4BEnvironmentSequence));
    NNPPhase4BEnvironmentSet(@"LastEnvTargetBacklightState", @(state));
    NNPPhase4BEnvironmentSet(@"LastEnvPresentationClass",
                             presentation ? NSStringFromClass([presentation class]) : @"nil");
    NNPPhase4BEnvironmentSet(@"LastEnvMachineClass", NSStringFromClass([self class]));
    NNPPhase4BEnvironmentSet(@"Sequence", @(gNNPPhase4BEnvironmentSequence));
}

%end

%ctor {
    NNPPhase4BEnvironmentSet(@"BuildIdentity", @"phase4b-environment-hook");
    NNPPhase4BEnvironmentSet(@"EnvSetPresentationCount", @0);
    NNPPhase4BEnvironmentSet(@"Sequence", @0);
}
