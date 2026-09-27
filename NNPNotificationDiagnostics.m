#import "NNPNotificationDiagnostics.h"
#import "NNPDiagnostics.h"
#import "NNPPreferences.h"
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <stdlib.h>
#import <dlfcn.h>

static CFStringRef const NNPNotificationPreferencesDomain = CFSTR("com.user.notchnowplaying");
static NSString * const NNPNotificationTracePreference = @"NotificationWakeTraceEnabled";
static _Atomic(bool) gNNPNotificationTraceEnabled = false;
static _Atomic(bool) gNNPNotificationTraceLocked = false;
static _Atomic(bool) gNNPNotificationTraceAODActive = false;
static _Atomic(unsigned int) gNNPNotificationTraceNotificationCount = 0;
static _Atomic(unsigned int) gNNPNotificationTraceBacklightCount = 0;
static IMP gNNPOriginalNotificationDispatch;
static IMP gNNPOriginalBacklightState;
static BOOL gNNPNotificationDispatchHookInstalled;
static BOOL gNNPBacklightStateHookInstalled;
static dispatch_once_t gNNPNotificationDiagnosticsStartOnce;

static void NNPNotificationTraceLogLimited(_Atomic(unsigned int) *counter, NSString *event) {
    unsigned int count = atomic_fetch_add_explicit(counter, 1, memory_order_relaxed) + 1;
    if (count <= 128) {
        NNPDiagnosticLog(event);
    } else if (count == 129) {
        NNPDiagnosticLog(@"NOTIFICATION_TRACE event limit reached; further events omitted until trace is re-enabled");
    }
}

static BOOL NNPMethodReturnsVoidWithArgumentCount(Method method, unsigned int expectedCount) {
    if (!method || method_getNumberOfArguments(method) != expectedCount) return NO;
    char *returnType = method_copyReturnType(method);
    BOOL isVoid = returnType && returnType[0] == 'v';
    free(returnType);
    return isVoid;
}

static BOOL NNPMethodHasObjectArgument(Method method, unsigned int index) {
    if (!method || index >= method_getNumberOfArguments(method)) return NO;
    char *argumentType = method_copyArgumentType(method, index);
    BOOL isObject = argumentType && argumentType[0] == '@';
    free(argumentType);
    return isObject;
}

static NSString *NNPNotificationSourceBundle(id request) {
    SEL selector = NSSelectorFromString(@"sectionIdentifier");
    if (!request || ![request respondsToSelector:selector]) return @"unknown";
    id (*sendObject)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id value = sendObject(request, selector);
    return [value isKindOfClass:NSString.class] && [value length] ? value : @"unknown";
}

static void NNPNotificationDispatchReplacement(id self, SEL selector, id request) {
    if (atomic_load_explicit(&gNNPNotificationTraceEnabled, memory_order_acquire)) {
        NSString *section = NNPNotificationSourceBundle(request);
        NSString *requestClass = request ? NSStringFromClass(object_getClass(request)) : @"nil";
        BOOL locked = atomic_load_explicit(&gNNPNotificationTraceLocked, memory_order_relaxed);
        BOOL aodActive = atomic_load_explicit(&gNNPNotificationTraceAODActive, memory_order_relaxed);
        NNPNotificationTraceLogLimited(&gNNPNotificationTraceNotificationCount,
            [NSString stringWithFormat:@"NOTIFICATION_TRACE received source=%@ requestClass=%@ locked=%@ aodActive=%@",
             section, requestClass, locked ? @"YES" : @"NO", aodActive ? @"YES" : @"NO"]);
    }
    ((void (*)(id, SEL, id))gNNPOriginalNotificationDispatch)(self, selector, request);
}

static void NNPBacklightStateTraceReplacement(id self, SEL selector, NSInteger state, NSInteger source, BOOL animated, id completion) {
    if (atomic_load_explicit(&gNNPNotificationTraceEnabled, memory_order_acquire)) {
        BOOL locked = atomic_load_explicit(&gNNPNotificationTraceLocked, memory_order_relaxed);
        BOOL aodActive = atomic_load_explicit(&gNNPNotificationTraceAODActive, memory_order_relaxed);
        NNPNotificationTraceLogLimited(&gNNPNotificationTraceBacklightCount,
            [NSString stringWithFormat:@"NOTIFICATION_TRACE backlight state=%ld source=%ld animated=%@ locked=%@ aodActive=%@",
             (long)state, (long)source, animated ? @"YES" : @"NO",
             locked ? @"YES" : @"NO", aodActive ? @"YES" : @"NO"]);
    }
    ((void (*)(id, SEL, NSInteger, NSInteger, BOOL, id))gNNPOriginalBacklightState)(self, selector, state, source, animated, completion);
}

static BOOL NNPInstallDiagnosticHook(Class cls, SEL selector, IMP replacement, IMP *originalOut, unsigned int argumentCount) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!NNPMethodReturnsVoidWithArgumentCount(method, argumentCount)) return NO;
    if (argumentCount == 3 && !NNPMethodHasObjectArgument(method, 2)) return NO;

    IMP original = method_getImplementation(method);
    if (!original || original == replacement) return NO;
    const char *types = method_getTypeEncoding(method);
    if (!class_addMethod(cls, selector, replacement, types)) {
        method = class_getInstanceMethod(cls, selector);
        if (!method) return NO;
        original = method_setImplementation(method, replacement);
    }
    if (!original || original == replacement) return NO;
    *originalOut = original;
    return YES;
}

static void NNPInstallNotificationTraceHooks(void) {
    @synchronized ([NSProcessInfo processInfo]) {
        if (!gNNPNotificationDispatchHookInstalled) {
            if (!dlsym(RTLD_DEFAULT, "OBJC_CLASS_$_NCNotificationDispatcher")) {
                dlopen("/System/Library/PrivateFrameworks/UserNotificationsKit.framework/UserNotificationsKit",
                       RTLD_LAZY | RTLD_LOCAL);
            }
            Class dispatcherClass = NSClassFromString(@"NCNotificationDispatcher");
            SEL selector = NSSelectorFromString(@"postNotificationWithRequest:");
            gNNPNotificationDispatchHookInstalled = NNPInstallDiagnosticHook(
                dispatcherClass, selector, (IMP)NNPNotificationDispatchReplacement,
                &gNNPOriginalNotificationDispatch, 3);
            NNPDiagnosticSetBool(@"NotificationDispatchTraceHookInstalled", gNNPNotificationDispatchHookInstalled);
            NNPDiagnosticLog([NSString stringWithFormat:@"NOTIFICATION_TRACE dispatch hook %@ class=NCNotificationDispatcher selector=%@",
                              gNNPNotificationDispatchHookInstalled ? @"installed" : @"unavailable",
                              NSStringFromSelector(selector)]);
        }

        if (!gNNPBacklightStateHookInstalled) {
            Class backlightClass = NSClassFromString(@"SBBacklightController");
            SEL selector = NSSelectorFromString(@"setBacklightState:source:animated:completion:");
            gNNPBacklightStateHookInstalled = NNPInstallDiagnosticHook(
                backlightClass, selector, (IMP)NNPBacklightStateTraceReplacement,
                &gNNPOriginalBacklightState, 6);
            NNPDiagnosticSetBool(@"NotificationBacklightTraceHookInstalled", gNNPBacklightStateHookInstalled);
            NNPDiagnosticLog([NSString stringWithFormat:@"NOTIFICATION_TRACE backlight hook %@ class=SBBacklightController selector=%@",
                              gNNPBacklightStateHookInstalled ? @"installed" : @"unavailable",
                              NSStringFromSelector(selector)]);
        }
    }
}

static void NNPNotificationDiagnosticsReloadPreference(void) {
    CFPreferencesAppSynchronize(NNPNotificationPreferencesDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)NNPNotificationTracePreference,
                                                           NNPNotificationPreferencesDomain));
    BOOL enabled = value ? [value boolValue] : NO;
    BOOL wasEnabled = atomic_exchange_explicit(&gNNPNotificationTraceEnabled, enabled, memory_order_acq_rel);
    NNPDiagnosticSetBool(@"NotificationWakeTraceEnabled", enabled);
    if (enabled == wasEnabled) return;

    if (enabled) {
        atomic_store_explicit(&gNNPNotificationTraceNotificationCount, 0, memory_order_relaxed);
        atomic_store_explicit(&gNNPNotificationTraceBacklightCount, 0, memory_order_relaxed);
        NNPDiagnosticLog(@"NOTIFICATION_TRACE enabled; content and notification identifiers are not recorded");
        NNPInstallNotificationTraceHooks();
    } else {
        NNPDiagnosticLog(@"NOTIFICATION_TRACE disabled");
    }
}

static void NNPNotificationPreferencesChanged(__unused CFNotificationCenterRef center, __unused void *observer,
                                              __unused CFStringRef name, __unused const void *object,
                                              __unused CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NNPNotificationDiagnosticsReloadPreference();
    });
}

void NNPNotificationDiagnosticsStart(void) {
    dispatch_once(&gNNPNotificationDiagnosticsStartOnce, ^{
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            NNPNotificationPreferencesChanged,
            (__bridge CFStringRef)NNPPreferencesDidChangeNotification, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        NNPNotificationDiagnosticsReloadPreference();
    });
}

void NNPNotificationDiagnosticsSetDisplayState(BOOL locked, BOOL aodActive) {
    atomic_store_explicit(&gNNPNotificationTraceLocked, locked, memory_order_relaxed);
    atomic_store_explicit(&gNNPNotificationTraceAODActive, aodActive, memory_order_relaxed);
}
