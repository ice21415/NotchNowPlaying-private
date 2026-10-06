#import "NNPMengoWakeGesture.h"
#import "NNPController.h"
#import "NNPDiagnostics.h"
#import "NNPMengoWakePolicy.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#include <math.h>

static char NNPMengoWakePointKey;
static char NNPMengoWakeTouchScopeKey;
static void (*NNPOriginalWakeRecognition)(id, SEL, id);
static void (*NNPOriginalRawRecognition)(id, SEL, CFTypeRef);
static void (*NNPOriginalWakeTouchesEnded)(id, SEL, id, id);

void NNPMengoRememberUIKitWakePoint(id gesture, CGPoint normalized) {
    if (!NNPMengoWakePositionValid(normalized.x, normalized.y)) return;
    objc_setAssociatedObject(gesture, &NNPMengoWakePointKey,
        @{@"point": [NSValue valueWithCGPoint:normalized], @"time": @(NSProcessInfo.processInfo.systemUptime), @"UIKit": @YES},
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NNPDiagnosticSetString(@"MengoWakeCoordinateSource", @"UIKit touch");
}
static void NNPMengoWakeTouchesEnded(id gesture, SEL selector, id touches, id event) {
    objc_setAssociatedObject(gesture, &NNPMengoWakePointKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (NSThread.isMainThread) [[NNPController sharedController] captureMengoWakeTouches:touches gesture:gesture];
    objc_setAssociatedObject(gesture, &NNPMengoWakeTouchScopeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (NNPOriginalWakeTouchesEnded) NNPOriginalWakeTouchesEnded(gesture, selector, touches, event);
    objc_setAssociatedObject(gesture, &NNPMengoWakeTouchScopeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

BOOL NNPMengoWakeNormalizedPoint(id gesture, CGPoint *point) {
    NSDictionary *sample = objc_getAssociatedObject(gesture, &NNPMengoWakePointKey);
    if (!sample) return NO;
    if (!NNPMengoWakeSampleFresh([sample[@"time"] doubleValue], NSProcessInfo.processInfo.systemUptime)) return NO;
    if (point) *point = [sample[@"point"] CGPointValue];
    return YES;
}
static void NNPMengoRawRecognition(id gesture, SEL selector, CFTypeRef event) {
    NSDictionary *sample = objc_getAssociatedObject(gesture, &NNPMengoWakePointKey);
    BOOL hasUIKitPoint = objc_getAssociatedObject(gesture, &NNPMengoWakeTouchScopeKey) &&
        [sample[@"UIKit"] boolValue] && NNPMengoWakeSampleFresh([sample[@"time"] doubleValue], NSProcessInfo.processInfo.systemUptime);
    if (!hasUIKitPoint) objc_setAssociatedObject(gesture, &NNPMengoWakePointKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (event && NSThread.isMainThread && [[NNPController sharedController] shouldHandleMengoWakeTap]) {
        NNPDiagnosticSetString(@"MengoWakeCoordinateSource", hasUIKitPoint ? @"UIKit touch" : @"unavailable");
        static CFTypeRef (*getEvent)(CFTypeRef, uint32_t, uint32_t);
        static double (*getFloat)(CFTypeRef, uint32_t);
        static uint32_t (*getType)(CFTypeRef);
        static CFArrayRef (*getChildren)(CFTypeRef);
        static CFIndex (*getInteger)(CFTypeRef, uint32_t);
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
            getEvent = dlsym(handle, "IOHIDEventGetEvent");
            getFloat = dlsym(handle, "IOHIDEventGetFloatValue");
            getType = dlsym(handle, "IOHIDEventGetType");
            getChildren = dlsym(handle, "IOHIDEventGetChildren");
            getInteger = dlsym(handle, "IOHIDEventGetIntegerValue");
        });
        CFTypeRef digitizer = getEvent ? getEvent(event, 11, 0) : NULL;
        if (getType) {
            uint32_t type = getType(event);
            NNPDiagnosticSetInteger(@"MengoWakeRawEventType", type);
            if (!digitizer && type == 11) digitizer = event;
        }
        BOOL foundDigitizer = NO;
        if (getFloat && getType) {
            CFTypeRef events[16] = { digitizer ?: event };
            int count = 1;
            for (int index = 0; index < count; index++) {
                CFTypeRef current = events[index];
                if (getType(current) == 11) {
                    foundDigitizer = YES;
                    double x = getFloat(current, 11u << 16), y = getFloat(current, (11u << 16) | 1);
                    if (isfinite(x)) NNPDiagnosticSetDouble(@"MengoWakeRawX", x);
                    if (isfinite(y)) NNPDiagnosticSetDouble(@"MengoWakeRawY", y);
                    BOOL pixels = getInteger && getInteger(current, 2) != 0;
                    NNPDiagnosticSetBool(@"MengoWakeRawPixelUnits", pixels);
                    CGRect bounds = UIScreen.mainScreen.bounds;
                    double nx, ny;
                    CFArrayRef children = getChildren ? getChildren(current) : NULL;
                    BOOL collection = getInteger && getInteger(current, 1) != 0;
                    BOOL containerWithChildren = collection && children && CFArrayGetCount(children) > 0;
                    if (!containerWithChildren && NNPMengoWakeConvertPosition(x, y, pixels, CGRectGetWidth(bounds), CGRectGetHeight(bounds),
                        UIScreen.mainScreen.scale, &nx, &ny)) {
                        if (!hasUIKitPoint) {
                        objc_setAssociatedObject(gesture, &NNPMengoWakePointKey,
                            @{@"point": [NSValue valueWithCGPoint:CGPointMake(nx, ny)], @"time": @(NSProcessInfo.processInfo.systemUptime)},
                            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        NNPDiagnosticSetString(@"MengoWakeCoordinateSource", pixels ? @"HID render pixels" : @"HID normalized or screen points");
                        }
                        break;
                    }
                }
                CFArrayRef children = getChildren ? getChildren(current) : NULL;
                if (children) for (CFIndex child = 0; child < CFArrayGetCount(children) && count < 16; child++)
                    events[count++] = CFArrayGetValueAtIndex(children, child);
            }
        }
        NNPDiagnosticSetBool(@"MengoWakeDigitizerPresent", foundDigitizer);
    }
    if (NNPOriginalRawRecognition) NNPOriginalRawRecognition(gesture, selector, event);
}
static void NNPMengoWakeRecognition(id owner, SEL selector, id gesture) {
    if (NSThread.isMainThread && [[NNPController sharedController] handleMengoWakeGesture:gesture]) return;
    if (NNPOriginalWakeRecognition) NNPOriginalWakeRecognition(owner, selector, gesture);
}
static Method NNPMengoRecognitionMethod(Class cls, const char *name, char argument) {
    Method method = class_getInstanceMethod(cls, sel_registerName(name));
    if (!method || method_getNumberOfArguments(method) != 3) return NULL;
    char result[16] = {0}, input[64] = {0};
    method_getReturnType(method, result, sizeof(result));
    method_getArgumentType(method, 2, input, sizeof(input));
    return result[0] == 'v' && input[0] == argument ? method : NULL;
}
void NNPMengoInstallWakeGestureHook(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method raw = NNPMengoRecognitionMethod(NSClassFromString(@"SBFTapToWakeGestureRecognizer"),
            "_succesfullyRecognizeFromEvent:", '^');
        if (raw) NNPOriginalRawRecognition = (void (*)(id, SEL, CFTypeRef))method_setImplementation(raw, (IMP)NNPMengoRawRecognition);
        Method ended = class_getInstanceMethod(NSClassFromString(@"SBFTapToWakeGestureRecognizer"), @selector(touchesEnded:withEvent:));
        if (ended && method_getNumberOfArguments(ended) == 4) {
            char result[16] = {0}, first[16] = {0}, second[16] = {0};
            method_getReturnType(ended, result, sizeof(result));
            method_getArgumentType(ended, 2, first, sizeof(first));
            method_getArgumentType(ended, 3, second, sizeof(second));
            if (result[0] == 'v' && first[0] == '@' && second[0] == '@') {
                IMP previous = method_getImplementation(ended);
                BOOL added = class_addMethod(NSClassFromString(@"SBFTapToWakeGestureRecognizer"),
                    @selector(touchesEnded:withEvent:), (IMP)NNPMengoWakeTouchesEnded, method_getTypeEncoding(ended));
                if (!added) previous = method_setImplementation(ended, (IMP)NNPMengoWakeTouchesEnded);
                NNPOriginalWakeTouchesEnded = (void (*)(id, SEL, id, id))previous;
            }
        }
        Method wake = NNPMengoRecognitionMethod(NSClassFromString(@"SBTapToWakeController"), "tapToWakeDidRecognize:", '@');
        if (wake) NNPOriginalWakeRecognition = (void (*)(id, SEL, id))method_setImplementation(wake, (IMP)NNPMengoWakeRecognition);
        NNPDiagnosticSetBool(@"MengoNativeWakeGestureHookInstalled", NNPOriginalWakeRecognition != NULL);
        NNPDiagnosticSetBool(@"MengoNativeWakeCoordinateHookInstalled", NNPOriginalRawRecognition != NULL);
        NNPDiagnosticSetBool(@"MengoUIKitWakeCoordinateHookInstalled", NNPOriginalWakeTouchesEnded != NULL);
    });
}
