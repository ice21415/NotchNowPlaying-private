#import "NNPAODTouchAssertion.h"
#import "NNPDiagnostics.h"
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL NNPTouchMethod(id object, SEL selector, unsigned int arguments, char input) {
    Method method = class_getInstanceMethod([object class], selector);
    if (!method || method_getNumberOfArguments(method) != arguments) return NO;
    char result[16] = {0}, value[16] = {0};
    method_getReturnType(method, result, sizeof(result));
    if (arguments == 3) method_getArgumentType(method, 2, value, sizeof(value));
    return result[0] == 'v' && (arguments == 2 || value[0] == input || (input == 'B' && value[0] == 'c'));
}
@implementation NNPAODTouchAssertion {
    id _assertion;
    BOOL _active;
}
- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active;
    if (!active) {
        if (NNPTouchMethod(_assertion, @selector(invalidate), 2, 0))
            ((void (*)(id, SEL))objc_msgSend)(_assertion, @selector(invalidate));
        _assertion = nil;
        NNPDiagnosticSetBool(@"MengoFullTouchAssertionActive", NO);
        return;
    }
    Class modeClass = NSClassFromString(@"BKSHIDUISensorMode");
    SEL build = NSSelectorFromString(@"buildModeForReason:builder:");
    Method factory = class_getClassMethod(modeClass, build);
    char result[16] = {0};
    if (!factory || method_getNumberOfArguments(factory) != 4) return;
    method_getReturnType(factory, result, sizeof(result));
    if (result[0] != '@') return;
    __block BOOL configured = NO;
    id mode = ((id (*)(id, SEL, id, id))objc_msgSend)(modeClass, build, @"NNP AOD ticket interaction", ^(id builder) {
        SEL display = NSSelectorFromString(@"setDisplayState:");
        SEL digitizer = NSSelectorFromString(@"setDigitizerEnabled:");
        SEL tapWake = NSSelectorFromString(@"setTapToWakeEnabled:");
        if (!NNPTouchMethod(builder, display, 3, 'q') || !NNPTouchMethod(builder, digitizer, 3, 'B') ||
            !NNPTouchMethod(builder, tapWake, 3, 'B')) return;
        // Sensor classification only: no physical display/backlight transition.
        ((void (*)(id, SEL, long long))objc_msgSend)(builder, display, 2);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(builder, digitizer, YES);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(builder, tapWake, NO);
        for (NSString *name in @[@"setAlwaysOnGesturesEnabled:", @"setWakeOnSwipeEnabled:",
            @"setWakeOnSwipeThroughEnabled:", @"setWakeOnTapThroughEnabled:", @"setWakeOnLongPressEnabled:"]) {
            SEL setter = NSSelectorFromString(name);
            if (NNPTouchMethod(builder, setter, 3, 'B'))
                ((void (*)(id, SEL, BOOL))objc_msgSend)(builder, setter, NO);
        }
        configured = YES;
    });
    if (!configured || !mode) return;
    Class serviceClass = NSClassFromString(@"BKSHIDUISensorService");
    if (![serviceClass respondsToSelector:@selector(sharedInstance)]) return;
    id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedInstance));
    SEL request = NSSelectorFromString(@"requestUISensorMode:");
    Method method = class_getInstanceMethod([service class], request);
    if (!method || method_getNumberOfArguments(method) != 3) return;
    method_getReturnType(method, result, sizeof(result));
    if (result[0] != '@') return;
    _assertion = ((id (*)(id, SEL, id))objc_msgSend)(service, request, mode);
    NNPDiagnosticSetBool(@"MengoFullTouchAssertionActive", _assertion != nil);
}
- (void)dealloc {
    if (NNPTouchMethod(_assertion, @selector(invalidate), 2, 0))
        ((void (*)(id, SEL))objc_msgSend)(_assertion, @selector(invalidate));
}
@end
