#import "NNPMengoWakeGesture.h"
#import "NNPController.h"
#import "NNPDiagnostics.h"
#import "NNPMengoWakePolicy.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#include <math.h>

static char NNPMengoWakePointKey;
static void (*NNPOriginalWakeRecognition)(id, SEL, id);
static void (*NNPOriginalRawRecognition)(id, SEL, CFTypeRef);

BOOL NNPMengoWakeNormalizedPoint(id gesture, CGPoint *point) {
    NSDictionary *sample = objc_getAssociatedObject(gesture, &NNPMengoWakePointKey);
    if (!sample) return NO;
    if (!NNPMengoWakeSampleFresh([sample[@"time"] doubleValue], NSProcessInfo.processInfo.systemUptime)) return NO;
    if (point) *point = [sample[@"point"] CGPointValue];
    return YES;
}
static void NNPMengoRawRecognition(id gesture, SEL selector, CFTypeRef event) {
    objc_setAssociatedObject(gesture, &NNPMengoWakePointKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (event && NSThread.isMainThread && [[NNPController sharedController] shouldHandleMengoWakeTap]) {
        static CFTypeRef (*getEvent)(CFTypeRef, uint32_t, uint32_t);
        static double (*getFloat)(CFTypeRef, uint32_t);
        static uint32_t (*getType)(CFTypeRef);
        static CFArrayRef (*getChildren)(CFTypeRef);
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
            getEvent = dlsym(handle, "IOHIDEventGetEvent");
            getFloat = dlsym(handle, "IOHIDEventGetFloatValue");
            getType = dlsym(handle, "IOHIDEventGetType");
            getChildren = dlsym(handle, "IOHIDEventGetChildren");
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
                    if (NNPMengoWakePositionValid(x, y)) {
                        objc_setAssociatedObject(gesture, &NNPMengoWakePointKey,
                            @{@"point": [NSValue valueWithCGPoint:CGPointMake(x, y)], @"time": @(NSProcessInfo.processInfo.systemUptime)},
                            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
        Method wake = NNPMengoRecognitionMethod(NSClassFromString(@"SBTapToWakeController"), "tapToWakeDidRecognize:", '@');
        if (wake) NNPOriginalWakeRecognition = (void (*)(id, SEL, id))method_setImplementation(wake, (IMP)NNPMengoWakeRecognition);
        NNPDiagnosticSetBool(@"MengoNativeWakeGestureHookInstalled", NNPOriginalWakeRecognition != NULL);
        NNPDiagnosticSetBool(@"MengoNativeWakeCoordinateHookInstalled", NNPOriginalRawRecognition != NULL);
    });
}
