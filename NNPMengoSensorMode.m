#import "NNPMengoSensorMode.h"
#import "NNPDiagnostics.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdatomic.h>

static atomic_bool NNPMengoSensorActive;
static void (*NNPOriginalSensorUpdate)(id, SEL, long long, long long);
static SEL NNPSensorSelector;

static BOOL NNPReadSensorInteger(id controller, NSString *name, long long *value) {
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([controller class], selector);
    char type[16] = {0};
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != 'q') return NO;
    *value = ((long long (*)(id, SEL))objc_msgSend)(controller, selector);
    return YES;
}
static void NNPRecordSensorFlag(id controller, NSString *selectorName, NSString *key) {
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod([controller class], selector);
    char type[16] = {0};
    if (!method || method_getNumberOfArguments(method) != 2) return;
    method_getReturnType(method, type, sizeof(type));
    if (type[0] == 'B' || type[0] == 'c')
        NNPDiagnosticSetBool(key, ((BOOL (*)(id, SEL))objc_msgSend)(controller, selector));
}
static void NNPMengoSensorUpdate(id controller, SEL selector, long long state, long long source) {
    BOOL active = atomic_load_explicit(&NNPMengoSensorActive, memory_order_acquire);
    if (NNPOriginalSensorUpdate) NNPOriginalSensorUpdate(controller, selector, active ? 1 : state, source);
    if (active) {
        NNPDiagnosticSetInteger(@"MengoNativeSensorInputState", state);
        NNPRecordSensorFlag(controller, @"isDigitizerDisabled", @"MengoSystemDigitizerDisabled");
        NNPRecordSensorFlag(controller, @"isTapToWakeEnabled", @"MengoSystemTapToWakeEnabled");
    }
}

@implementation NNPMengoSensorMode {
    BOOL _active, _failed;
    id _controller;
}
- (void)setActive:(BOOL)active {
    if (_active == active) return;
    if (active && _failed) return;
    if (!active) {
        _active = NO;
        atomic_store_explicit(&NNPMengoSensorActive, NO, memory_order_release);
        NNPDiagnosticSetBool(@"MengoNativeSensorPolicyActive", NO);
    }
    if (active) {
        Class cls = NSClassFromString(@"SBBacklightController");
        SEL shared = NSSelectorFromString(@"sharedInstance");
        Method factory = class_getClassMethod(cls, shared);
        char type[16] = {0};
        if (!factory || method_getNumberOfArguments(factory) != 2) return;
        method_getReturnType(factory, type, sizeof(type));
        if (type[0] != '@') return;
        _controller = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
        NNPSensorSelector = NSSelectorFromString(@"_updateHIDUISensorModeForBacklightState:source:");
        Method method = class_getInstanceMethod(cls, NNPSensorSelector);
        char first[16] = {0}, second[16] = {0};
        if (!method || method_getNumberOfArguments(method) != 4) return;
        method_getReturnType(method, type, sizeof(type));
        method_getArgumentType(method, 2, first, sizeof(first));
        method_getArgumentType(method, 3, second, sizeof(second));
        if (type[0] != 'v' || first[0] != 'q' || second[0] != 'q') return;
        if (!NNPOriginalSensorUpdate)
            NNPOriginalSensorUpdate = (void (*)(id, SEL, long long, long long))method_setImplementation(method, (IMP)NNPMengoSensorUpdate);
    }
    long long state, source;
    if (!NNPOriginalSensorUpdate || !NNPReadSensorInteger(_controller, @"backlightState", &state) ||
        !NNPReadSensorInteger(_controller, @"lastBacklightChangeSource", &source)) {
        _controller = nil;
        return;
    }
    _active = active;
    atomic_store_explicit(&NNPMengoSensorActive, active, memory_order_release);
    // Replay only SpringBoard's sensor configuration; never set backlightState.
    NNPOriginalSensorUpdate(_controller, NNPSensorSelector, active ? 1 : state, source);
    long long after = state;
    NNPReadSensorInteger(_controller, @"backlightState", &after);
    NNPDiagnosticSetInteger(@"MengoSensorReplayBacklightBefore", state);
    NNPDiagnosticSetInteger(@"MengoSensorReplayBacklightAfter", after);
    NNPDiagnosticSetBool(@"MengoSensorReplayBacklightUnchanged", state == after);
    if (active && state != after) {
        _failed = YES; _active = NO;
        atomic_store_explicit(&NNPMengoSensorActive, NO, memory_order_release);
        NNPOriginalSensorUpdate(_controller, NNPSensorSelector, after, source);
        active = NO;
    }
    NNPDiagnosticSetBool(@"MengoNativeSensorPolicyActive", active);
    NNPRecordSensorFlag(_controller, @"isDigitizerDisabled", @"MengoSystemDigitizerDisabled");
    NNPRecordSensorFlag(_controller, @"isTapToWakeEnabled", @"MengoSystemTapToWakeEnabled");
    if (!active) _controller = nil;
}
- (void)dealloc {
    if (!_active) return;
    atomic_store_explicit(&NNPMengoSensorActive, NO, memory_order_release);
    long long state, source;
    if (NNPOriginalSensorUpdate && NNPReadSensorInteger(_controller, @"backlightState", &state) &&
        NNPReadSensorInteger(_controller, @"lastBacklightChangeSource", &source))
        NNPOriginalSensorUpdate(_controller, NNPSensorSelector, state, source);
}
@end
