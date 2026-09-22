#import <Foundation/Foundation.h>
#import <dlfcn.h>
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
    if (gNNPPhase4BDisplayModeSequence == 1) {
        NNPPhase4BDisplayModeSet(@"FirstDisplayMode", @(mode));
        NNPPhase4BDisplayModeSet(@"FirstRampDuration", @(duration));
    }
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
    Class displayStateClass = NSClassFromString(@"BLSHBacklightDisplayStateMachine");
    SEL displayModeSelector = NSSelectorFromString(@"setDisplayMode:withRampDuration:");
    NNPPhase4BDisplayModeSet(@"DisplayModeClassFound", @(displayStateClass != Nil));
    NNPPhase4BDisplayModeSet(@"DisplayModeSelectorFound",
                             @(displayStateClass &&
                               class_getInstanceMethod(displayStateClass,
                                                       displayModeSelector) != NULL));
    Method displayModeMethod = displayStateClass
        ? class_getInstanceMethod(displayStateClass, displayModeSelector) : NULL;
    IMP displayModeIMP = displayModeMethod ? method_getImplementation(displayModeMethod) : NULL;
    Dl_info displayModeInfo = {0};
    if (displayModeIMP && dladdr((const void *)displayModeIMP, &displayModeInfo)) {
        NNPPhase4BDisplayModeSet(@"DisplayModeIMP",
                                 [NSString stringWithFormat:@"0x%llx",
                                  (unsigned long long)(uintptr_t)displayModeIMP]);
        NNPPhase4BDisplayModeSet(@"DisplayModeImageBase",
                                 [NSString stringWithFormat:@"0x%llx",
                                  (unsigned long long)(uintptr_t)displayModeInfo.dli_fbase]);
        if (displayModeInfo.dli_fname) {
            NNPPhase4BDisplayModeSet(@"DisplayModeImage",
                                     [NSString stringWithUTF8String:displayModeInfo.dli_fname]);
        }
    }
    NNPPhase4BDisplayModeSet(@"DisplayModeCallCount", @0);
    NNPPhase4BDisplayModeSet(@"DisplayModeSequence", @0);
}
