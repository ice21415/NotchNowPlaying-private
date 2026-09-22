#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static CFStringRef const NNPPhase4BDisplayModeDomain =
    CFSTR("com.user.notchnowplaying.phase4b");
static long long gNNPPhase4BDisplayModeSequence;

static void NNPPhase4BDisplayModeSet(NSString *key, id value) {
    if (!key.length || !value) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             NNPPhase4BDisplayModeDomain);
    CFPreferencesAppSynchronize(NNPPhase4BDisplayModeDomain);
}

%hook BLSHBacklightDisplayStateMachine

- (void)setDisplayMode:(long long)mode withRampDuration:(double)duration {
    %orig;

    gNNPPhase4BDisplayModeSequence++;
    NNPPhase4BDisplayModeSet(@"DisplayModeCallCount",
                             @(gNNPPhase4BDisplayModeSequence));
    NNPPhase4BDisplayModeSet(@"LastDisplayMode", @(mode));
    NNPPhase4BDisplayModeSet(@"LastRampDuration", @(duration));
    NNPPhase4BDisplayModeSet(@"LastDisplayModeReceiverClass",
                             NSStringFromClass(object_getClass(self)));
    NNPPhase4BDisplayModeSet(@"DisplayModeSequence",
                             @(gNNPPhase4BDisplayModeSequence));
}

%end

%ctor {
    NNPPhase4BDisplayModeSet(@"DisplayModeHookBuildIdentity",
                             @"phase4b-display-mode");
    NNPPhase4BDisplayModeSet(@"DisplayModeCallCount", @0);
    NNPPhase4BDisplayModeSet(@"DisplayModeSequence", @0);
}
