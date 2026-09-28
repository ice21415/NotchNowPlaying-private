#import "NNPNotificationDiagnostics.h"
#import "NNPDiagnostics.h"
#import "NNPPreferences.h"
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <stdint.h>
#import <stdlib.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <os/lock.h>

static CFStringRef const NNPNotificationPreferencesDomain = CFSTR("com.user.notchnowplaying");
static NSString * const NNPNotificationTracePreference = @"NotificationWakeTraceEnabled";
static NSString * const NNPNotificationSnakeWakePreference = @"NotificationSnakeWakeEnabled";
// Source 12 is the source value observed immediately after NC notification dispatches
// on the target iOS 17.1.2 device; it is not a public enum name.
static const NSInteger NNPObservedNotificationBacklightSource = 12;
static const double NNPNotificationWakeCorrelationWindowSeconds = 2.0;
static _Atomic(bool) gNNPNotificationTraceEnabled = false;
static _Atomic(bool) gNNPNotificationSnakeWakeEnabled = false;
static _Atomic(bool) gNNPNotificationTraceLocked = false;
static _Atomic(bool) gNNPNotificationTraceAODActive = false;
static _Atomic(uint64_t) gNNPLastAODNotificationDispatchTicks = 0;
static os_unfair_lock gNNPPendingNotificationPayloadLock = OS_UNFAIR_LOCK_INIT;
static NSDictionary *gNNPPendingNotificationPayload;
static _Atomic(unsigned int) gNNPNotificationTraceNotificationCount = 0;
static _Atomic(unsigned int) gNNPNotificationTraceBacklightCount = 0;
static IMP gNNPOriginalNotificationDispatch;
static IMP gNNPOriginalBacklightState;
static BOOL gNNPNotificationDispatchHookInstalled;
static BOOL gNNPBacklightStateHookInstalled;
static dispatch_once_t gNNPNotificationDiagnosticsStartOnce;
static dispatch_once_t gNNPNotificationTimebaseOnce;
static mach_timebase_info_data_t gNNPNotificationTimebase;

static uint64_t NNPNotificationTicksForSeconds(double seconds) {
    dispatch_once(&gNNPNotificationTimebaseOnce, ^{
        mach_timebase_info(&gNNPNotificationTimebase);
    });
    if (gNNPNotificationTimebase.numer == 0) return 0;
    return (uint64_t)(seconds * 1000000000.0 *
        (double)gNNPNotificationTimebase.denom / (double)gNNPNotificationTimebase.numer);
}

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

static id NNPNotificationObjectForSelector(id object, const char *selectorName) {
    SEL selector = sel_registerName(selectorName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSString *NNPNotificationStringForSelector(id object, const char *selectorName, NSUInteger maximumLength) {
    id value = NNPNotificationObjectForSelector(object, selectorName);
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length) return nil;
    if (text.length <= maximumLength) return [text copy];
    NSUInteger end = maximumLength;
    NSRange composedRange = [text rangeOfComposedCharacterSequenceAtIndex:end - 1];
    return [[text substringToIndex:NSMaxRange(composedRange)] copy];
}

static NSDictionary *NNPNotificationPayloadFromRequest(id request) {
    id content = NNPNotificationObjectForSelector(request, "content");
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    NSString *bundleIdentifier = NNPNotificationSourceBundle(request);
    if (![bundleIdentifier isEqualToString:@"unknown"]) payload[@"bundleIdentifier"] = bundleIdentifier;

    NSString *appName = NNPNotificationStringForSelector(content, "header", 80);
    NSString *title = NNPNotificationStringForSelector(content, "title", 120);
    NSString *subtitle = NNPNotificationStringForSelector(content, "subtitle", 160);
    NSString *message = NNPNotificationStringForSelector(content, "message", 360);
    if (!message.length) message = NNPNotificationStringForSelector(content, "body", 360);
    if (!message.length) message = NNPNotificationStringForSelector(content, "hiddenPreviewsBodyPlaceholder", 160);
    id icon = NNPNotificationObjectForSelector(content, "icon");
    Class imageClass = NSClassFromString(@"UIImage");

    if (appName.length) payload[@"appName"] = appName;
    if (title.length) payload[@"title"] = title;
    if (subtitle.length) payload[@"subtitle"] = subtitle;
    if (message.length) payload[@"message"] = message;
    if (imageClass && [icon isKindOfClass:imageClass]) payload[@"contentIcon"] = icon;
    return [payload copy];
}

static void NNPNotificationSetPendingPresentationPayload(NSDictionary *payload) {
    os_unfair_lock_lock(&gNNPPendingNotificationPayloadLock);
    gNNPPendingNotificationPayload = [payload copy];
    os_unfair_lock_unlock(&gNNPPendingNotificationPayloadLock);
}

static void NNPNotificationDispatchReplacement(id self, SEL selector, id request) {
    if (atomic_load_explicit(&gNNPNotificationSnakeWakeEnabled, memory_order_acquire) &&
        atomic_load_explicit(&gNNPNotificationTraceLocked, memory_order_acquire) &&
        atomic_load_explicit(&gNNPNotificationTraceAODActive, memory_order_acquire)) {
        uint64_t dispatchTicks = mach_absolute_time();
        atomic_store_explicit(&gNNPLastAODNotificationDispatchTicks, dispatchTicks, memory_order_release);
        NNPNotificationSetPendingPresentationPayload(NNPNotificationPayloadFromRequest(request));
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (atomic_load_explicit(&gNNPLastAODNotificationDispatchTicks, memory_order_acquire) == dispatchTicks) {
                atomic_store_explicit(&gNNPLastAODNotificationDispatchTicks, 0, memory_order_release);
                NNPNotificationSetPendingPresentationPayload(nil);
            }
        });
    }

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

static void NNPInstallNotificationHooks(BOOL installBacklightTraceHook) {
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

        if (installBacklightTraceHook && !gNNPBacklightStateHookInstalled) {
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
    id traceValue = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)NNPNotificationTracePreference,
                                                                NNPNotificationPreferencesDomain));
    id snakeValue = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)NNPNotificationSnakeWakePreference,
                                                                NNPNotificationPreferencesDomain));
    BOOL traceEnabled = traceValue ? [traceValue boolValue] : NO;
    BOOL snakeWakeEnabled = snakeValue ? [snakeValue boolValue] : NO;
    BOOL wasTraceEnabled = atomic_exchange_explicit(&gNNPNotificationTraceEnabled, traceEnabled, memory_order_acq_rel);
    BOOL wasSnakeWakeEnabled = atomic_exchange_explicit(&gNNPNotificationSnakeWakeEnabled, snakeWakeEnabled, memory_order_acq_rel);
    NNPDiagnosticSetBool(@"NotificationWakeTraceEnabled", traceEnabled);
    NNPDiagnosticSetBool(@"NotificationSnakeWakeEnabled", snakeWakeEnabled);

    if (traceEnabled && !wasTraceEnabled) {
        atomic_store_explicit(&gNNPNotificationTraceNotificationCount, 0, memory_order_relaxed);
        atomic_store_explicit(&gNNPNotificationTraceBacklightCount, 0, memory_order_relaxed);
        NNPDiagnosticLog(@"NOTIFICATION_TRACE enabled; notification content is never written to diagnostic logs");
    } else if (!traceEnabled && wasTraceEnabled) {
        NNPDiagnosticLog(@"NOTIFICATION_TRACE disabled");
    }

    if (!snakeWakeEnabled) {
        atomic_store_explicit(&gNNPLastAODNotificationDispatchTicks, 0, memory_order_release);
        NNPNotificationSetPendingPresentationPayload(nil);
    }
    if (traceEnabled || snakeWakeEnabled) {
        NNPInstallNotificationHooks(traceEnabled);
    }
    if (snakeWakeEnabled != wasSnakeWakeEnabled) {
        NNPDiagnosticLog(snakeWakeEnabled
            ? @"NOTIFICATION_SNAKE enabled; only correlated locked-AOD wake requests are eligible"
            : @"NOTIFICATION_SNAKE disabled");
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
    atomic_store_explicit(&gNNPNotificationTraceLocked, locked, memory_order_release);
    atomic_store_explicit(&gNNPNotificationTraceAODActive, aodActive, memory_order_release);
    if (!locked || !aodActive) {
        atomic_store_explicit(&gNNPLastAODNotificationDispatchTicks, 0, memory_order_release);
        NNPNotificationSetPendingPresentationPayload(nil);
    }
}

BOOL NNPNotificationDiagnosticsIsNotificationBacklightSource(NSInteger source) {
    return source == NNPObservedNotificationBacklightSource;
}

BOOL NNPNotificationDiagnosticsConsumeWakeForSnakeAnimation(NSInteger state, NSInteger source) {
    if (state != 1) return NO;

    uint64_t dispatchTicks = atomic_exchange_explicit(&gNNPLastAODNotificationDispatchTicks, 0,
                                                       memory_order_acq_rel);
    BOOL eligible = source == NNPObservedNotificationBacklightSource &&
        atomic_load_explicit(&gNNPNotificationSnakeWakeEnabled, memory_order_acquire) &&
        atomic_load_explicit(&gNNPNotificationTraceLocked, memory_order_acquire) &&
        atomic_load_explicit(&gNNPNotificationTraceAODActive, memory_order_acquire);
    if (!eligible || !dispatchTicks) {
        NNPNotificationSetPendingPresentationPayload(nil);
        return NO;
    }

    uint64_t now = mach_absolute_time();
    uint64_t window = NNPNotificationTicksForSeconds(NNPNotificationWakeCorrelationWindowSeconds);
    if (!window || !gNNPNotificationTimebase.numer || !gNNPNotificationTimebase.denom ||
        now < dispatchTicks || now - dispatchTicks > window) {
        NNPNotificationSetPendingPresentationPayload(nil);
        return NO;
    }

    double ageSeconds = ((double)(now - dispatchTicks) * (double)gNNPNotificationTimebase.numer /
                         (double)gNNPNotificationTimebase.denom) / 1000000000.0;
    NNPDiagnosticLogTransition([NSString stringWithFormat:
        @"NOTIFICATION_SNAKE matched state=%ld source=%ld age=%.3fs; preserving locked AOD",
        (long)state, (long)source, ageSeconds]);
    return YES;
}

NSDictionary *NNPNotificationDiagnosticsConsumePendingPresentationPayload(void) {
    os_unfair_lock_lock(&gNNPPendingNotificationPayloadLock);
    NSDictionary *payload = [gNNPPendingNotificationPayload copy];
    gNNPPendingNotificationPayload = nil;
    os_unfair_lock_unlock(&gNNPPendingNotificationPayloadLock);
    return payload;
}
