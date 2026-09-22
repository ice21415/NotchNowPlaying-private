#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static CFStringRef const NNPPhase4BDomain = CFSTR("com.user.notchnowplaying.phase4b");
static BOOL gNNPPhase4BAwakeRecorded;
static BOOL gNNPPhase4BLockRecorded;
static long long gNNPPhase4BSequence;

static void NNPPhase4BSet(NSString *key, id value) {
    if (!key.length || !value) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             NNPPhase4BDomain);
    CFPreferencesAppSynchronize(NNPPhase4BDomain);
}

static void NNPPhase4BRecordTarget(id machine) {
    Ivar targetIvar = class_getInstanceVariable(object_getClass(machine), "_lock_targetState");
    if (!targetIvar) targetIvar = class_getInstanceVariable([machine class], "_lock_targetState");
    id target = targetIvar ? object_getIvar(machine, targetIvar) : nil;
    if (!target) return;

    SEL modeSelector = NSSelectorFromString(@"displayMode");
    if (![target respondsToSelector:modeSelector]) return;
    long long mode = ((long long (*)(id, SEL))objc_msgSend)(target, modeSelector);

    id presentation = nil;
    Ivar presentationIvar = class_getInstanceVariable([target class], "_presentation");
    if (presentationIvar) presentation = object_getIvar(target, presentationIvar);
    NSString *presentationClass = presentation ? NSStringFromClass([presentation class]) : @"nil";

    BOOL isAwakeMode = (mode == 4);
    BOOL isLockMode = (mode == 0 || mode == 1);
    if (!isAwakeMode && !isLockMode) return;
    if (isAwakeMode && gNNPPhase4BAwakeRecorded) return;
    if (isLockMode && gNNPPhase4BLockRecorded) return;

    Class blsClass = NSClassFromString(@"BLSBacklight");
    SEL sharedSelector = NSSelectorFromString(@"sharedBacklight");
    SEL stateSelector = NSSelectorFromString(@"backlightState");
    id backlight = (blsClass && class_respondsToSelector(object_getClass(blsClass), sharedSelector))
        ? ((id (*)(id, SEL))objc_msgSend)((id)blsClass, sharedSelector) : nil;
    if (!backlight || ![backlight respondsToSelector:stateSelector]) return;

    long long providerState = ((long long (*)(id, SEL))objc_msgSend)(backlight, stateSelector);
    gNNPPhase4BSequence++;
    NSString *prefix = isAwakeMode ? @"Awake" : @"Lock";
    NNPPhase4BSet([prefix stringByAppendingString:@"ProviderState"], @(providerState));
    NNPPhase4BSet([prefix stringByAppendingString:@"DisplayMode"], @(mode));
    NNPPhase4BSet([prefix stringByAppendingString:@"PresentationClass"], presentationClass);
    NNPPhase4BSet(@"Sequence", @(gNNPPhase4BSequence));
    NNPPhase4BSet(@"LastTargetClass", NSStringFromClass([target class]));
    if (isAwakeMode) gNNPPhase4BAwakeRecorded = YES;
    if (isLockMode) gNNPPhase4BLockRecorded = YES;
}

%hook BLSHBacklightTransitionStateMachine

- (void)performEvent:(id)event {
    %orig;
    NNPPhase4BRecordTarget(self);
}

%end
