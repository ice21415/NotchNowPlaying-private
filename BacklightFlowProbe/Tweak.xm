#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <fcntl.h>
#import <mach/mach_time.h>
#import <sys/stat.h>
#import <unistd.h>
#import <stdint.h>
#import <string.h>

static dispatch_queue_t NNPProbeWriteQueue;
static NSString * const NNPProbeDirectory = @"/var/mobile/Library/NotchNowPlaying";
static NSString * const NNPProbeLogPath = @"/var/mobile/Library/NotchNowPlaying/backlight-flow-probe.log";

static void NNPProbeWriteBootstrapMarker(void) {
    int fd = open(NNPProbeLogPath.UTF8String, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    static const char marker[] = "probe-bootstrap\n";
    (void)write(fd, marker, sizeof(marker) - 1);
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
        int fd = open(NNPProbeLogPath.UTF8String,
                      O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd < 0) return;
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        const uint8_t *bytes = (const uint8_t *)data.bytes;
        size_t remaining = data.length;
        while (remaining) {
            ssize_t written = write(fd, bytes, remaining);
            if (written <= 0) break;
            bytes += written;
            remaining -= (size_t)written;
        }
        close(fd);
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
        NNPProbeLog([NSString stringWithFormat:@"%@ requestClass=%@", stage, className]);
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
    NNPProbeLog([NSString stringWithFormat:@"%@ requestClass=%@ %@",
                 stage, className, [values componentsJoinedByString:@" "]]);
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
    NNPProbeLog([NSString stringWithFormat:@"bls-event class=%@ eventID=%@ state=%@ previousState=%@ requestClass=%@",
                 event ? NSStringFromClass(object_getClass(event)) : @"<nil>",
                 NNPProbeReadGetter(event, @"eventID"),
                 NNPProbeReadGetter(event, @"state"),
                 NNPProbeReadGetter(event, @"previousState"),
                 changeRequest ? NSStringFromClass(object_getClass(changeRequest)) : @"<nil>"]);
    if (changeRequest) NNPProbeLogRequest(@"bls-event-request", changeRequest);
    %orig;
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
