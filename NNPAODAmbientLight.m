#import "NNPAODAmbientLight.h"
#import "NNPDiagnostics.h"
#import "NNPAODPowerPolicy.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <math.h>

typedef CFTypeRef (*NNPHIDCreate)(CFAllocatorRef);
typedef CFArrayRef (*NNPHIDServices)(CFTypeRef);
typedef CFTypeRef (*NNPHIDProperty)(CFTypeRef, CFStringRef);
typedef CFTypeRef (*NNPHIDEvent)(CFTypeRef, uint32_t, CFTypeRef, uint32_t);
typedef double (*NNPHIDFloat)(CFTypeRef, uint32_t);
typedef uint64_t (*NNPHIDTimestamp)(CFTypeRef);

@implementation NNPAODAmbientLight {
    dispatch_queue_t _queue;
    NSTimer *_timer;
    BOOL _active;
    BOOL _pending;
    NSUInteger _generation;
    CFTypeRef _client;
    CFTypeRef _service;
    NNPHIDCreate _create;
    NNPHIDServices _services;
    NNPHIDProperty _property;
    NNPHIDEvent _event;
    NNPHIDFloat _floatValue;
    NNPHIDTimestamp _timestamp;
    BOOL _loaded;
    NNPAODAmbientSamplingPolicy _samplingPolicy;
    NSUInteger _sampleCount;
}
- (instancetype)init {
    if ((self = [super init])) _queue = dispatch_queue_create("com.user.notchnowplaying.ambient", DISPATCH_QUEUE_SERIAL);
    return self;
}
- (BOOL)prepareSensor {
    if (!_loaded) {
        _loaded = YES;
        void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) return NO;
        _create = (NNPHIDCreate)dlsym(handle, "IOHIDEventSystemClientCreate");
        _services = (NNPHIDServices)dlsym(handle, "IOHIDEventSystemClientCopyServices");
        _property = (NNPHIDProperty)dlsym(handle, "IOHIDServiceClientCopyProperty");
        _event = (NNPHIDEvent)dlsym(handle, "IOHIDServiceClientCopyEvent");
        _floatValue = (NNPHIDFloat)dlsym(handle, "IOHIDEventGetFloatValue");
        _timestamp = (NNPHIDTimestamp)dlsym(handle, "IOHIDEventGetTimeStamp");
    }
    if (!_create || !_services || !_property || !_event || !_floatValue || !_timestamp) return NO;
    if (!_client) _client = _create(kCFAllocatorDefault);
    if (!_client) return NO;
    if (_service) return YES;
    CFArrayRef services = _services(_client);
    if (!services) return NO;
    for (CFIndex index = 0; index < CFArrayGetCount(services); index++) {
        CFTypeRef service = CFArrayGetValueAtIndex(services, index);
        CFTypeRef page = _property(service, CFSTR("PrimaryUsagePage"));
        CFTypeRef usage = _property(service, CFSTR("PrimaryUsage"));
        int p = 0, u = 0;
        if (page && CFGetTypeID(page) == CFNumberGetTypeID()) CFNumberGetValue(page, kCFNumberIntType, &p);
        if (usage && CFGetTypeID(usage) == CFNumberGetTypeID()) CFNumberGetValue(usage, kCFNumberIntType, &u);
        if (page) CFRelease(page);
        if (usage) CFRelease(usage);
        // iOS 17.1.2 CBALSNode uses Apple's vendor ALS usage 0xff00 / 4.
        if (p != 0xff00 || u != 4) continue;
        _service = CFRetain(service);
        break;
    }
    CFRelease(services);
    return _service != NULL;
}
- (void)sample {
    if (!_active || _pending) return;
    _pending = YES;
    NSUInteger generation = _generation;
    dispatch_async(_queue, ^{
        double lux = -1, age = -1;
        BOOL valid = NO;
        if ([self prepareSensor]) {
            CFTypeRef event = self->_event(self->_service, 12, NULL, 0);
            if (event) {
                lux = self->_floatValue(event, 12u << 16);
                uint64_t stamp = self->_timestamp(event), now = mach_absolute_time();
                mach_timebase_info_data_t timebase;
                mach_timebase_info(&timebase);
                if (stamp && stamp <= now) age = (double)(now - stamp) * timebase.numer / timebase.denom / 1e9;
                valid = isfinite(lux) && lux >= 0 && lux <= 200000 && age >= 0 && age <= 30;
                CFRelease(event);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_pending = NO;
            if (!self->_active) return;
            if (generation != self->_generation) {
                [self sample];
                return;
            }
            NNPDiagnosticSetBool(@"AODAmbientSampleValid", valid);
            NNPDiagnosticSetDouble(@"AODAmbientLux", lux);
#if NNP_ENABLE_VERBOSE_DIAGNOSTICS
            NNPDiagnosticSetInteger(@"AODAmbientSampleCount", ++self->_sampleCount);
            NNPDiagnosticSetDouble(@"AODAmbientSampleAge", age);
#endif
            if (self.sampleHandler) self.sampleHandler(lux, valid);
            if (self->_active && generation == self->_generation) {
                [self scheduleNextSampleAfter:NNPAODAmbientNextSampleInterval(&self->_samplingPolicy, lux, valid)];
            }
        });
    });
}
- (void)scheduleNextSampleAfter:(NSTimeInterval)interval {
    if (!_active) return;
    [_timer invalidate];
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer timerWithTimeInterval:interval repeats:NO block:^(__unused NSTimer *timer) { [weakSelf sample]; }];
    _timer.tolerance = MIN(3.0, interval * 0.2);
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    NNPDiagnosticSetDouble(@"AODAmbientSampleInterval", interval);
}
- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active;
    _generation++;
    _samplingPolicy = (NNPAODAmbientSamplingPolicy){0};
    [_timer invalidate];
    _timer = nil;
    NNPDiagnosticSetBool(@"AODAmbientSensorActive", active);
    if (!active) {
        NNPDiagnosticSetDouble(@"AODAmbientSampleInterval", 0);
        dispatch_async(_queue, ^{
            if (self->_service) CFRelease(self->_service);
            if (self->_client) CFRelease(self->_client);
            self->_service = NULL;
            self->_client = NULL;
        });
        return;
    }
    [self scheduleNextSampleAfter:5];
    [self sample];
}
- (void)dealloc {
    [_timer invalidate];
    if (_service) CFRelease(_service);
    if (_client) CFRelease(_client);
}
@end
