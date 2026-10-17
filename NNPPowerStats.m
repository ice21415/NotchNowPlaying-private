#import "NNPPowerStats.h"
#import "NNPPowerStatsShared.h"
#import "NNPPowerMath.h"
#import "NNPDiagnostics.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <time.h>
#import <math.h>
#import <UIKit/UIKit.h>

typedef mach_port_t NNPIOObject;
typedef CFMutableDictionaryRef (*NNPIOServiceMatchingFn)(const char *);
typedef NNPIOObject (*NNPIOServiceGetMatchingServiceFn)(mach_port_t, CFDictionaryRef);
typedef kern_return_t (*NNPIORegistryCreatePropertiesFn)(NNPIOObject, CFMutableDictionaryRef *, CFAllocatorRef, uint32_t);
typedef kern_return_t (*NNPIOObjectReleaseFn)(NNPIOObject);

static const NSTimeInterval NNPPowerStatsMaxGap = 150.0;
static const NSTimeInterval NNPPowerStatsPersistInterval = 300.0;

static double NNPNumber(NSDictionary *dictionary, NSString *key, double fallback) {
    id value = dictionary[key];
    double number = [value isKindOfClass:NSNumber.class] ? [(NSNumber *)value doubleValue] : fallback;
    return isfinite(number) ? number : fallback;
}

@implementation NNPPowerStats {
    NSMutableArray<NSMutableDictionary *> *_hours;
    NSTimeInterval _lastSampleTime;
    NSDictionary *_lastBattery;
    NNPPowerStatsMode _lastMode;
    double _lastMonotonic;
    BOOL _lastCharging;
    NSTimeInterval _lastPersistTime;
    BOOL _dirty;
    BOOL _observingBattery;
    NSTimeInterval _lastBatteryEventTime;
    BOOL _lastBatteryCharging;
    BOOL _persistScheduled;
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
    // Convert the integer before double: unsigned -100 mA rounds to 2^64 in double.
    NSNumber *current = registry[@"Amperage"] ?: registry[@"InstantAmperage"];
    double amperage = NAN;
    if ([current isKindOfClass:NSNumber.class]) {
        amperage = NNPSignedCurrent(current.unsignedLongLongValue);
    }
    BOOL charging = [registry[@"IsCharging"] boolValue] || [registry[@"ExternalConnected"] boolValue];
    NSDictionary *telemetry = [registry[@"PowerTelemetryData"] isKindOfClass:NSDictionary.class] ? registry[@"PowerTelemetryData"] : nil;
    return @{
        @"loadAcc": @(NNPNumber(telemetry, @"AccumulatedSystemLoad", NAN)),
        @"loadCount": @(NNPNumber(telemetry, @"SystemLoadAccumulatorCount", NAN)),
        @"percent": @(NNPNumber(registry, @"CurrentCapacity", -1)),
        @"rawMAh": @(NNPNumber(registry, @"AppleRawCurrentCapacity", 0)),
        @"maxMAh": @(NNPNumber(registry, @"AppleRawMaxCapacity", 0)),
        @"designMAh": @(NNPNumber(registry, @"DesignCapacity", 0)),
        @"cycles": @(NNPNumber(registry, @"CycleCount", 0)),
        @"tempC": @(NNPNumber(registry, @"Temperature", 0) / 100.0),
        @"voltage": @(NNPNumber(registry, @"Voltage", 0)),
        @"amperage": @(amperage),
        @"gaugeTime": @(NNPNumber(registry, @"UpdateTime", 0)),
        @"charging": @(charging),
        @"updated": @([NSDate date].timeIntervalSince1970),
    };
}

- (NSMutableDictionary *)bucketForHour:(long long)hour {
    for (NSMutableDictionary *entry in _hours)
        if ((long long)NNPNumber(entry, @"h", -1) == hour) return entry;
    NSMutableDictionary *bucket = [@{ @"h": @(hour), @"idleS": @0, @"mediaS": @0, @"dischS": @0, @"chgS": @0,
                                      @"usedMAh": @0, @"pwrSum": @0, @"pwrN": @0, @"pct1": @(-1) } mutableCopy];
    [_hours addObject:bucket];
    [_hours sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"h"] compare:b[@"h"]]; }];
    long long oldest = (long long)([NSDate date].timeIntervalSince1970 / 3600.0) - NNPStatsMaxHours + 1;
    while (_hours.count && NNPNumber(_hours.firstObject, @"h", -1) < oldest) [_hours removeObjectAtIndex:0];
    return bucket;
}

- (void)add:(double)value forKey:(NSString *)key to:(NSMutableDictionary *)bucket {
    bucket[key] = @(NNPNumber(bucket, key, 0) + value);
}

// Split all interval totals across clock-hour boundaries; rates use elapsed time.
- (void)addInterval:(double)start end:(double)end values:(NSDictionary *)values {
    while (start < end) {
        long long hour = (long long)floor(start / 3600.0);
        double stop = NNPNextHourBoundary(start, end);
        NSMutableDictionary *bucket = [self bucketForHour:hour];
        for (NSString *key in values) [self add:[values[key] doubleValue] * (stop - start) forKey:key to:bucket];
        start = stop;
    }
}

- (void)updateMode:(NNPPowerStatsMode)mode {
    if (_lastSampleTime > 0 && mode != _lastMode) [self sampleWithMode:mode];
}

- (void)sampleWithMode:(NNPPowerStatsMode)mode {
    double now = [NSDate date].timeIntervalSince1970;
    double monotonic = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1e9;
    NSDictionary *battery = [self readBattery];
    double dt = _lastSampleTime > 0 ? monotonic - _lastMonotonic : 0;
    // Reject discontinuities rather than attributing unknown time or clock changes to AOD.
    if (dt > 0 && dt <= NNPPowerStatsMaxGap && fabs((now - _lastSampleTime) - dt) < 2.0) {
        NSMutableDictionary *rates = [@{(_lastMode == NNPPowerStatsModeIdle ? @"idleS" : @"mediaS"): @1} mutableCopy];
        if (battery && _lastBattery) {
            BOOL charging = [battery[@"charging"] boolValue];
            BOOL previousCharging = [_lastBattery[@"charging"] boolValue];
            if (charging && previousCharging) rates[@"chgS"] = @1;
            double v0 = NNPNumber(_lastBattery, @"voltage", 0), v1 = NNPNumber(battery, @"voltage", 0);
            BOOL voltsValid = v0 >= 2000 && v0 <= 20000 && v1 >= 2000 && v1 <= 20000;
            // Primary: the gauge's system-load accumulator, the mean of about one load sample per second over
            // the whole interval. It measures what the device draws, so it stays valid while charging.
            double power = NNPAccumulatorMeanPower(NNPNumber(_lastBattery, @"loadAcc", NAN), NNPNumber(_lastBattery, @"loadCount", NAN),
                                                   NNPNumber(battery, @"loadAcc", NAN), NNPNumber(battery, @"loadCount", NAN));
            if (power >= 0) {
                rates[@"energyMWs"] = @(power);
                rates[@"powerS"] = @1;
                rates[@"accS"] = @1;
            }
            if (!charging && !previousCharging) {
                double chargeRate = NAN;
                if (power >= 0 && voltsValid) {
                    chargeRate = NNPChargeRateFromPower(power, v0, v1);
                } else if (power < 0) {
                    // Fallback: trapezoidal integration of the two average-current endpoints.
                    double i0 = NNPNumber(_lastBattery, @"amperage", NAN), i1 = NNPNumber(battery, @"amperage", NAN);
                    double g0 = NNPNumber(_lastBattery, @"gaugeTime", 0), g1 = NNPNumber(battery, @"gaugeTime", 0);
                    BOOL fresh = g0 <= 0 || g1 <= 0 || g1 > g0;
                    if (fresh && voltsValid && isfinite(i0) && isfinite(i1) && i0 <= 0 && i1 <= 0 && i0 >= -30000 && i1 >= -30000) {
                        chargeRate = NNPChargeRate(i0, i1);
                        rates[@"energyMWs"] = @(NNPMeanPower(i0, v0, i1, v1));
                        rates[@"powerS"] = @1;
                    }
                }
                if (isfinite(chargeRate)) {
                    rates[@"dischS2"] = @1;
                    rates[@"usedMAh2"] = @(chargeRate);
                    double c0 = NNPNumber(_lastBattery, @"maxMAh", 0), c1 = NNPNumber(battery, @"maxMAh", 0);
                    if (c0 > 0 && c1 > 0) {
                        rates[@"usedPct2"] = @(chargeRate / ((c0 + c1) / 2.0) * 100.0);
                        rates[@"pctS2"] = @1;
                    }
                }
            }
        }
        [self addInterval:_lastSampleTime end:now values:rates];
    }
    NSMutableDictionary *bucket = [self bucketForHour:(long long)(now / 3600.0)];
    double percent = NNPNumber(battery, @"percent", -1);
    if (percent >= 0 && percent <= 100) bucket[@"pct1"] = @(percent);
    _lastBattery = battery; // Failed reads break the electrical baseline.
    _lastMode = mode;
    _lastSampleTime = now;
    _lastMonotonic = monotonic;
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
    if (_lastSampleTime > 0) [self sampleWithMode:_lastMode];
    [self persistBattery:nil];
    _lastSampleTime = 0;
    _lastBattery = nil;
}

- (void)startObservingBattery {
    if (_observingBattery) return;
    _observingBattery = YES;
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    __weak typeof(self) weakSelf = self;
    for (NSString *name in @[UIDeviceBatteryLevelDidChangeNotification, UIDeviceBatteryStateDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *note) { [weakSelf recordBatteryEvent]; }];
    }
    [self recordBatteryEvent];
}

// Event driven (about one event per percent), so the battery line and charging periods stay current even when
// no AOD is shown. Charging intervals are split at hour boundaries.
- (void)recordBatteryEvent {
    NSDictionary *battery = [self readBattery];
    if (!battery) return;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSMutableDictionary *bucket = [self bucketForHour:(long long)(now / 3600.0)];
    double percent = NNPNumber(battery, @"percent", -1);
    if (percent >= 0) bucket[@"pct1"] = @(percent);
    BOOL charging = [battery[@"charging"] boolValue];
    if (_lastBatteryEventTime > 0 && _lastBatteryCharging && now > _lastBatteryEventTime && now - _lastBatteryEventTime <= 3 * 3600.0)
        [self addInterval:_lastBatteryEventTime end:now values:@{@"chgAllS": @1}];
    // Take an AOD boundary sample on every battery event, including charger changes.
    if (_lastSampleTime > 0) [self sampleWithMode:_lastMode];
    _lastBatteryEventTime = now;
    _lastBatteryCharging = charging;
    _dirty = YES;
    NSTimeInterval wait = 60.0 - (now - _lastPersistTime);
    if (wait <= 0) { [self persistBattery:battery]; return; }
    if (_persistScheduled) return;
    _persistScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NNPPowerStats *stats = weakSelf;
        if (!stats) return;
        stats->_persistScheduled = NO;
        [stats persistBattery:nil];
    });
}

@end
