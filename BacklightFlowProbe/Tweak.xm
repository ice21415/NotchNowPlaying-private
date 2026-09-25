#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <mach/mach_time.h>
#import <sys/stat.h>
#import <unistd.h>
#import <stdint.h>
#import <string.h>

static dispatch_queue_t NNPProbeWriteQueue;
static NSMutableString *NNPProbePreferenceTrace;
static CFStringRef const NNPProbePreferencesDomain = CFSTR("com.user.nnpbacklightflowprobe");
static NSString * const NNPProbeDirectory = @"/var/mobile/Library/NotchNowPlaying";
static NSString * const NNPProbeLogPath = @"/var/mobile/Library/NotchNowPlaying/backlight-flow-probe.log";
static const char *NNPProbeFallbackLogPath = "/tmp/backlight-flow-probe.log";

static void NNPProbeAppendToPath(const char *path, const void *bytes, size_t length) {
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    const uint8_t *cursor = (const uint8_t *)bytes;
    size_t remaining = length;
    while (remaining) {
        ssize_t written = write(fd, cursor, remaining);
        if (written <= 0) break;
        cursor += written;
        remaining -= (size_t)written;
    }
    close(fd);
}

static double NNPProbeMonotonicSeconds(void) {
    static mach_timebase_info_data_t timebase;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&timebase); });
    uint64_t ticks = mach_continuous_time();
    return ((double)ticks * (double)timebase.numer) /
           ((double)timebase.denom * 1000000000.0);
}

static void NNPProbeWriteBootstrapMarker(void) {
    NSString *marker = [NSString stringWithFormat:@"probe-bootstrap %.6f pid=%d\n",
                        NNPProbeMonotonicSeconds(), getpid()];
    NSData *data = [marker dataUsingEncoding:NSUTF8StringEncoding];
    NNPProbeAppendToPath(NNPProbeLogPath.UTF8String, data.bytes, data.length);
    NNPProbeAppendToPath(NNPProbeFallbackLogPath, data.bytes, data.length);
    CFPreferencesSetAppValue(CFSTR("Bootstrap"), (__bridge CFPropertyListRef)marker,
                             NNPProbePreferencesDomain);
    CFPreferencesSetAppValue(CFSTR("Trace"), CFSTR(""), NNPProbePreferencesDomain);
    (void)CFPreferencesAppSynchronize(NNPProbePreferencesDomain);
}

static void NNPProbeAppendPreferenceRecord(NSString *line) {
    if (!NNPProbePreferenceTrace) NNPProbePreferenceTrace = [NSMutableString string];
    [NNPProbePreferenceTrace appendString:line];
    if (NNPProbePreferenceTrace.length > 32768) {
        NSRange nextLine = [NNPProbePreferenceTrace rangeOfString:@"\n"];
        if (nextLine.location != NSNotFound) {
            [NNPProbePreferenceTrace deleteCharactersInRange:
                NSMakeRange(0, nextLine.location + nextLine.length)];
        }
    }
    CFPreferencesSetAppValue(CFSTR("Trace"),
                             (__bridge CFPropertyListRef)NNPProbePreferenceTrace,
                             NNPProbePreferencesDomain);
    (void)CFPreferencesAppSynchronize(NNPProbePreferencesDomain);
}

static void NNPProbeEnsureWriteQueue(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NNPProbeWriteQueue = dispatch_queue_create(
            "com.user.nnpbacklightflowprobe.write", DISPATCH_QUEUE_SERIAL);
    });
}

static void NNPProbeLog(NSString *event) {
    if (!event.length) return;
    NNPProbeEnsureWriteQueue();
    NSString *line = [NSString stringWithFormat:@"%.6f pid=%d %@\n",
                      NNPProbeMonotonicSeconds(), getpid(), event];
    dispatch_async(NNPProbeWriteQueue, ^{
        mkdir(NNPProbeDirectory.UTF8String, 0755);
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NNPProbeAppendToPath(NNPProbeLogPath.UTF8String, data.bytes, data.length);
        NNPProbeAppendToPath(NNPProbeFallbackLogPath, data.bytes, data.length);
        NNPProbeAppendPreferenceRecord(line);
    });
}

static id NNPProbeReadObjectGetter(id object, NSString *name) {
    if (!object || !name.length) return nil;
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 ||
        signature.methodReturnType[0] != '@') return nil;
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = object;
    invocation.selector = selector;
    [invocation invoke];
    __unsafe_unretained id value = nil;
    [invocation getReturnValue:&value];
    return value;
}

static NSString *NNPProbeReadGetter(id object, NSString *name) {
    if (!object || !name.length) return @"<nil-target>";
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2) return @"<unavailable>";

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = object;
    invocation.selector = selector;
    [invocation invoke];

    const char *type = signature.methodReturnType;
    while (type && strchr("rnNoORV", type[0])) type++;
    if (!type || type[0] == 'v') return @"<void>";
    if (type[0] == '@') {
        __unsafe_unretained id value = nil;
        [invocation getReturnValue:&value];
        if (!value) return @"nil";
        NSString *className = NSStringFromClass(object_getClass(value)) ?: @"object";
        if ([value isKindOfClass:NSString.class] ||
            [value isKindOfClass:NSNumber.class] ||
            [value isKindOfClass:NSDate.class]) {
            return [NSString stringWithFormat:@"%@(%@)", className, value];
        }
        return [NSString stringWithFormat:@"%@", className];
    }
    if (type[0] == '#') {
        Class value = Nil;
        [invocation getReturnValue:&value];
        return value ? NSStringFromClass(value) : @"nil-class";
    }
    if (type[0] == ':') {
        SEL value = NULL;
        [invocation getReturnValue:&value];
        return value ? NSStringFromSelector(value) : @"nil-selector";
    }

    NSUInteger length = signature.methodReturnLength;
    if (length == 0 || length > sizeof(uint64_t)) return @"<unsupported-scalar>";
    uint64_t bits = 0;
    [invocation getReturnValue:&bits];
    if (type[0] == 'c' || type[0] == 's' || type[0] == 'i' || type[0] == 'l' || type[0] == 'q') {
        int64_t signedValue = 0;
        memcpy(&signedValue, &bits, length);
        return [NSString stringWithFormat:@"%lld", (long long)signedValue];
    }
    return [NSString stringWithFormat:@"%llu", (unsigned long long)bits];
}

static void NNPProbeLogRequest(NSString *stage, id request) {
    NSString *className = request ? NSStringFromClass(object_getClass(request)) : @"<nil>";
    if (!request) {
        NNPProbeLog([NSString stringWithFormat:@"%@ request=%p requestClass=%@", stage, (void *)request, className]);
        return;
    }
    NSArray<NSString *> *fields = @[
        @"requestedActivityState", @"sourceEvent", @"sourceEventMetadata",
        @"explanation", @"timestamp"
    ];
    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:fields.count];
    for (NSString *field in fields) {
        [values addObject:[NSString stringWithFormat:@"%@=%@", field,
                          NNPProbeReadGetter(request, field)]];
    }
    NNPProbeLog([NSString stringWithFormat:@"%@ request=%p requestClass=%@ %@",
                 stage, (void *)request, className, [values componentsJoinedByString:@" "]]);
}

static NSString *NNPProbeImplementationSummary(Class cls, SEL selector) {
    if (!cls || !selector) return @"<missing-class-or-selector>";
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return @"<missing-method>";

    IMP implementation = method_getImplementation(method);
    const char *encoding = method_getTypeEncoding(method);
    Dl_info info = {0};
    BOOL resolved = dladdr((const void *)implementation, &info) != 0;
    uintptr_t offset = 0;
    if (resolved && info.dli_fbase) {
        offset = (uintptr_t)implementation - (uintptr_t)info.dli_fbase;
    }
    return [NSString stringWithFormat:@"imp=%p types=%s image=%s offset=0x%llx",
            (void *)implementation, encoding ?: "?",
            (resolved && info.dli_fname) ? info.dli_fname : "<unresolved>",
            (unsigned long long)offset];
}

static NSString *NNPProbeRawEventState(id event) {
    if (!event || ![NSStringFromClass(object_getClass(event)) isEqualToString:@"BLSBacklightChangeEvent"]) {
        return @"<not-concrete-event>";
    }
    Ivar stateIvar = class_getInstanceVariable(object_getClass(event), "_state");
    const char *stateEncoding = stateIvar ? ivar_getTypeEncoding(stateIvar) : NULL;
    if (!stateIvar || !stateEncoding || strcmp(stateEncoding, "q") != 0) {
        return @"<state-ivar-unavailable>";
    }
    ptrdiff_t offset = ivar_getOffset(stateIvar);
    int64_t rawState = 0;
    const void *eventStorage = (__bridge const void *)event;
    memcpy(&rawState, (const uint8_t *)eventStorage + offset, sizeof(rawState));
    return [NSString stringWithFormat:@"%lld@+0x%llx", (long long)rawState,
            (unsigned long long)offset];
}

%hook SBBacklightController

- (void)_performBacklightChangeRequest:(id)request completion:(id)completion {
    NNPProbeLogRequest(@"springboard-request", request);
    %orig;
}

%end

%hook BLSBacklight

- (id)performChangeRequest:(id)request {
    NNPProbeLogRequest(@"bls-client-request", request);
    return %orig;
}

%end

%hook BLSHBacklightStateMachine

- (id)performChangeRequest:(id)request {
    NNPProbeLogRequest(@"bls-host-request", request);
    return %orig;
}

%end

%hook BLSHBacklightTransitionStateMachine

- (void)performEvent:(id)event {
    id changeRequest = NNPProbeReadObjectGetter(event, @"changeRequest");
    Class eventClass = event ? object_getClass(event) : Nil;
    NNPProbeLog([NSString stringWithFormat:@"bls-event event=%p class=%@ eventID=%@ state=%@ rawState=%@ previousState=%@ request=%p requestClass=%@ stateGetter={%@}",
                 (void *)event,
                 event ? NSStringFromClass(object_getClass(event)) : @"<nil>",
                 NNPProbeReadGetter(event, @"eventID"),
                 NNPProbeReadGetter(event, @"state"),
                 NNPProbeRawEventState(event),
                 NNPProbeReadGetter(event, @"previousState"),
                 (void *)changeRequest,
                 changeRequest ? NSStringFromClass(object_getClass(changeRequest)) : @"<nil>",
                 NNPProbeImplementationSummary(eventClass, NSSelectorFromString(@"state"))]);
    if (changeRequest) NNPProbeLogRequest(@"bls-event-request", changeRequest);
    %orig;
}

%end

%hook BLSBacklightChangeEvent

- (id)initWithEventID:(unsigned long long)eventID
                state:(long long)state
        previousState:(long long)previousState
        changeRequest:(id)request {
    NNPProbeLog([NSString stringWithFormat:
        @"bls-event-init begin receiver=%p eventID=%llu stateArgument=%lld previousStateArgument=%lld request=%p",
        (void *)self, eventID, state, previousState, (void *)request]);
    if (request) NNPProbeLogRequest(@"bls-event-init-request", request);

    id result = %orig(eventID, state, previousState, request);
    Class eventClass = result ? object_getClass(result) : Nil;
    NNPProbeLog([NSString stringWithFormat:
        @"bls-event-init end result=%p class=%@ stateArgument=%lld getterState=%@ rawState=%@ previousState=%@ request=%p stateGetter={%@}",
        (void *)result,
        result ? NSStringFromClass(eventClass) : @"<nil>",
        state,
        NNPProbeReadGetter(result, @"state"),
        NNPProbeRawEventState(result),
        NNPProbeReadGetter(result, @"previousState"),
        (void *)NNPProbeReadObjectGetter(result, @"changeRequest"),
        NNPProbeImplementationSummary(eventClass, NSSelectorFromString(@"state"))]);
    return result;
}

%end

%hook BLSHBacklightDisplayStateMachine

- (void)setDisplayMode:(long long)mode withRampDuration:(double)duration {
    NNPProbeLog([NSString stringWithFormat:@"bls-target-mode mode=%lld ramp=%.6f", mode, duration]);
    %orig;
}

- (void)displayState:(id)displayState didUpdateToMode:(long long)mode {
    NNPProbeLog([NSString stringWithFormat:@"bls-mode-completed mode=%lld stateClass=%@",
                 mode, displayState ? NSStringFromClass(object_getClass(displayState)) : @"<nil>"]);
    %orig;
}

%end

%hook BLSHBacklightOSInterfaceProvider

- (void)transitionToDisplayMode:(long long)mode withDuration:(double)duration {
    NNPProbeLog([NSString stringWithFormat:@"provider-mode mode=%lld duration=%.6f", mode, duration]);
    %orig;
}

- (void)setCABlanked:(BOOL)blanked {
    NNPProbeLog([NSString stringWithFormat:@"provider-ca-blanked value=%d", blanked]);
    %orig;
}

- (void)willUnblank {
    NNPProbeLog(@"provider-will-unblank");
    %orig;
}

%end

%ctor {
    NNPProbeWriteBootstrapMarker();
    NNPProbeLog(@"probe-loaded");
}

%hook SBLockHardwareButtonActions

- (void)performSinglePressAction {
    NNPProbeLog(@"side-button-single-press-action");
    %orig;
}

%end
