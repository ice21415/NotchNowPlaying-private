#import "NNPPowerStats.h"
#import "NNPPowerStatsShared.h"
#import "NNPDiagnostics.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach/mach.h>

typedef mach_port_t NNPIOObject;
typedef CFMutableDictionaryRef (*NNPIOServiceMatchingFn)(const char *);
typedef NNPIOObject (*NNPIOServiceGetMatchingServiceFn)(mach_port_t, CFDictionaryRef);
typedef kern_return_t (*NNPIORegistryCreatePropertiesFn)(NNPIOObject, CFMutableDictionaryRef *, CFAllocatorRef, uint32_t);
typedef kern_return_t (*NNPIOObjectReleaseFn)(NNPIOObject);

static const NSTimeInterval NNPPowerStatsMaxGap = 150.0;
static const NSTimeInterval NNPPowerStatsPersistInterval = 300.0;

static double NNPNumber(NSDictionary *dictionary, NSString *key, double fallback) {
    id value = dictionary[key];
    return [value isKindOfClass:NSNumber.class] ? [(NSNumber *)value doubleValue] : fallback;
}

@implementation NNPPowerStats {
    NSMutableArray<NSMutableDictionary *> *_hours;
    NSTimeInterval _lastSampleTime;
    double _lastRawMAh;
    BOOL _lastCharging;
    NSTimeInterval _lastPersistTime;
    BOOL _dirty;
    NNPIOServiceMatchingFn _serviceMatching;
    NNPIOServiceGetMatchingServiceFn _getMatchingService;
    NNPIORegistryCreatePropertiesFn _createProperties;
    NNPIOObjectReleaseFn _release;
    const mach_port_t *_masterPort;
}

+ (instancetype)sharedStats {
    static NNPPowerStats *stats;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ stats = [NNPPowerStats new]; });
    return stats;
}

- (instancetype)init {
    if ((self = [super init])) {
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        if (iokit) {
            _serviceMatching = (NNPIOServiceMatchingFn)dlsym(iokit, "IOServiceMatching");
            _getMatchingService = (NNPIOServiceGetMatchingServiceFn)dlsym(iokit, "IOServiceGetMatchingService");
            _createProperties = (NNPIORegistryCreatePropertiesFn)dlsym(iokit, "IORegistryEntryCreateCFProperties");
            _release = (NNPIOObjectReleaseFn)dlsym(iokit, "IOObjectRelease");
            _masterPort = (const mach_port_t *)dlsym(iokit, "kIOMasterPortDefault");
        }
        _hours = [NSMutableArray array];
        CFPreferencesAppSynchronize((__bridge CFStringRef)NNPStatsDomain);
        id stored = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)NNPStatsHoursKey, (__bridge CFStringRef)NNPStatsDomain));
        if ([stored isKindOfClass:NSArray.class]) {
            for (id entry in (NSArray *)stored) {
                if ([entry isKindOfClass:NSDictionary.class]) [_hours addObject:[entry mutableCopy]];
            }
        }
    }
    return self;
}

- (NSDictionary *)readBattery {
    if (!_serviceMatching || !_getMatchingService || !_createProperties || !_release || !_masterPort) return nil;
    NNPIOObject service = _getMatchingService(*_masterPort, _serviceMatching("AppleSmartBattery"));
    if (!service) return nil;
    CFMutableDictionaryRef properties = NULL;
    kern_return_t result = _createProperties(service, &properties, kCFAllocatorDefault, 0);
    _release(service);
    if (result != KERN_SUCCESS || !properties) return nil;
    NSDictionary *registry = CFBridgingRelease(properties);
    double amperage = registry[@"InstantAmperage"] ? NNPNumber(registry, @"InstantAmperage", 0) : NNPNumber(registry, @"Amperage", 0);
    // The registry reports unsigned 64-bit values for negative currents.
    if (amperage > 1e15) amperage = (double)(int64_t)(uint64_t)amperage;
    BOOL charging = [registry[@"IsCharging"] boolValue] || [registry[@"ExternalConnected"] boolValue];
    return @{
        @"percent": @(NNPNumber(registry, @"CurrentCapacity", -1)),
        @"rawMAh": @(NNPNumber(registry, @"AppleRawCurrentCapacity", 0)),
        @"maxMAh": @(NNPNumber(registry, @"AppleRawMaxCapacity", 0)),
        @"designMAh": @(NNPNumber(registry, @"DesignCapacity", 0)),
        @"cycles": @(NNPNumber(registry, @"CycleCount", 0)),
        @"tempC": @(NNPNumber(registry, @"Temperature", 0) / 100.0),
        @"voltage": @(NNPNumber(registry, @"Voltage", 0)),
        @"amperage": @(amperage),
        @"charging": @(charging),
        @"updated": @([NSDate date].timeIntervalSince1970),
    };
}

- (NSMutableDictionary *)bucketForHour:(long long)hour {
    NSMutableDictionary *last = _hours.lastObject;
    if (last && (long long)NNPNumber(last, @"h", -1) == hour) return last;
    NSMutableDictionary *bucket = [@{ @"h": @(hour), @"idleS": @0, @"mediaS": @0, @"dischS": @0, @"chgS": @0,
                                      @"usedMAh": @0, @"pwrSum": @0, @"pwrN": @0, @"pct1": @(-1) } mutableCopy];
    [_hours addObject:bucket];
    while (_hours.count > NNPStatsMaxHours) [_hours removeObjectAtIndex:0];
    return bucket;
}

- (void)add:(double)value forKey:(NSString *)key to:(NSMutableDictionary *)bucket {
    bucket[key] = @(NNPNumber(bucket, key, 0) + value);
}

- (void)sampleWithMode:(NNPPowerStatsMode)mode {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSDictionary *battery = [self readBattery];
    NSMutableDictionary *bucket = [self bucketForHour:(long long)(now / 3600.0)];
    NSTimeInterval dt = (_lastSampleTime > 0 && now - _lastSampleTime <= NNPPowerStatsMaxGap) ? now - _lastSampleTime : 0;
    if (dt > 0) [self add:dt forKey:mode == NNPPowerStatsModeIdle ? @"idleS" : @"mediaS" to:bucket];

    if (battery) {
        BOOL charging = [battery[@"charging"] boolValue];
        double rawMAh = NNPNumber(battery, @"rawMAh", 0);
        double percent = NNPNumber(battery, @"percent", -1);
        if (percent >= 0) bucket[@"pct1"] = @(percent);
        if (dt > 0) {
            if (charging) {
                [self add:dt forKey:@"chgS" to:bucket];
            } else {
                [self add:dt forKey:@"dischS" to:bucket];
                double amperage = NNPNumber(battery, @"amperage", 0);
                double voltage = NNPNumber(battery, @"voltage", 0);
                if (amperage < 0 && voltage > 0) {
                    [self add:voltage * (-amperage) / 1000.0 forKey:@"pwrSum" to:bucket];
                    [self add:1 forKey:@"pwrN" to:bucket];
                }
                if (!_lastCharging && _lastRawMAh > 0 && rawMAh > 0 && rawMAh < _lastRawMAh) {
                    [self add:_lastRawMAh - rawMAh forKey:@"usedMAh" to:bucket];
                }
            }
        }
        _lastRawMAh = rawMAh;
        _lastCharging = charging;
    }
    _lastSampleTime = now;
    _dirty = YES;
    if (now - _lastPersistTime >= NNPPowerStatsPersistInterval) [self persistBattery:battery];
}

- (void)persistBattery:(NSDictionary *)battery {
    if (!_dirty) return;
    _lastPersistTime = [NSDate date].timeIntervalSince1970;
    _dirty = NO;
    CFStringRef domain = (__bridge CFStringRef)NNPStatsDomain;
    CFPreferencesSetAppValue((__bridge CFStringRef)NNPStatsHoursKey, (__bridge CFArrayRef)[_hours copy], domain);
    NSDictionary *snapshot = battery ?: [self readBattery];
    if (snapshot) CFPreferencesSetAppValue((__bridge CFStringRef)NNPStatsBatteryKey, (__bridge CFDictionaryRef)snapshot, domain);
    CFPreferencesAppSynchronize(domain);
    NNPDiagnosticSetBool(@"PowerStatsBatteryReadable", snapshot != nil);
    NNPDiagnosticSetInteger(@"PowerStatsHourBuckets", (NSInteger)_hours.count);
}

- (void)endRun {
    NSDictionary *battery = _dirty ? [self readBattery] : nil;
    _dirty = _dirty || _lastSampleTime > 0;
    [self persistBattery:battery];
    _lastSampleTime = 0;
    _lastRawMAh = 0;
}

@end
