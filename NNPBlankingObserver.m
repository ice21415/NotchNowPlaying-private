#import "NNPBlankingObserver.h"
#import "NNPDiagnostics.h"
#import <objc/runtime.h>
#import <mach/mach_time.h>
#import <unistd.h>

#ifndef NNP_PHASE2G_ARM_AT_START
#define NNP_PHASE2G_ARM_AT_START 0
#endif

static NSString * const NNPObserverLog = @"[NotchNowPlaying/BlankingObserver]";

static NSArray<NSString *> *NNPNotificationNames(void) {
    return @[
        @"com.apple.springboard.hasBlankedScreen",
        @"com.apple.backboardd.display-disabled",
        @"com.apple.backboardd.backlight.changed"
    ];
}

@interface NNPBlankingObserver ()
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL completed;
@property(nonatomic) BOOL sawLogicalLock;
@property(nonatomic) NSUInteger sequence;
@property(nonatomic) mach_timebase_info_data_t timebase;
@end

static void NNPDarwinNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NNPBlankingObserver *target = (__bridge NNPBlankingObserver *)observer;
    NSString *eventName = name ? [(__bridge NSString *)name copy] : @"unknown-notification";
    [target performSelectorOnMainThread:@selector(recordNotification:) withObject:eventName waitUntilDone:NO];
}

@implementation NNPBlankingObserver

- (instancetype)init {
    self = [super init];
    if (self) mach_timebase_info(&_timebase);
    return self;
}

- (NSString *)wallTimestamp { return [[NSDate date] description]; }

- (NSNumber *)monotonicMilliseconds {
    uint64_t nanos = mach_absolute_time() * self.timebase.numer / self.timebase.denom;
    return @(nanos / 1000000ULL);
}

- (void)recordEvent:(NSString *)event details:(NSDictionary *)details {
    if (!self.active || !event.length) return;
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:@{
        @"event": event,
        @"wallTimestamp": [self wallTimestamp],
        @"monotonicMilliseconds": [self monotonicMilliseconds],
        @"sequence": @(++self.sequence),
        @"SpringBoardPID": @(getpid())
    }];
    if (details.count) [entry addEntriesFromDictionary:details];
    NNPDiagnosticAppendEvent(entry);
    NSLog(@"%@ %@", NNPObserverLog, event);
}

- (void)recordNotification:(NSString *)name {
    [self recordEvent:name details:@{ @"source": @"DarwinNotificationCenter" }];
}

- (void)recordLogicalLock:(BOOL)locked {
    if (!self.active) return;
    [self recordEvent:(locked ? @"LOGICAL_LOCK=1" : @"LOGICAL_LOCK=0") details:nil];
    if (locked) self.sawLogicalLock = YES;
    if (!locked && self.sawLogicalLock) {
        self.completed = YES;
        self.active = NO;
        NNPDiagnosticSetBool(@"BlankingObserverExperimentArmed", NO);
        NNPDiagnosticSetBool(@"BlankingObserverExperimentCompleted", YES);
        NSLog(@"%@ completed one lock/wake/unlock cycle", NNPObserverLog);
    }
}

- (void)recordRuntimeClass:(NSString *)name selectors:(NSArray<NSString *> *)selectors {
    Class cls = NSClassFromString(name);
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:@{
        @"class": name,
        @"present": @(cls != Nil),
        @"invoked": @NO
    }];
    NSMutableDictionary *selectorResults = [NSMutableDictionary dictionary];
    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        selectorResults[selectorName] = @{
            @"instanceMethod": @(cls && class_getInstanceMethod(cls, selector) != NULL),
            @"classMethod": @(cls && class_getClassMethod(cls, selector) != NULL)
        };
    }
    result[@"selectors"] = selectorResults;
    NSMutableArray *all = [NNPDiagnosticCopyValue(@"RuntimeClasses") mutableCopy] ?: [NSMutableArray array];
    [all addObject:result];
    if (all.count > 16) [all removeObjectsInRange:NSMakeRange(0, all.count - 16)];
    NNPDiagnosticSetValue(@"RuntimeClasses", all);
}

- (void)start {
    if (self.active || self.completed) return;
    BOOL armed = [NNPDiagnosticCopyValue(@"BlankingObserverExperimentArmed") boolValue];
#if NNP_PHASE2G_ARM_AT_START
    if (!self.completed) armed = YES;
#endif
    if (!armed) return;
    self.active = YES;
    NNPDiagnosticSetBool(@"BlankingObserverExperimentArmed", YES);
    NNPDiagnosticSetBool(@"BlankingObserverExperimentCompleted", NO);
    NNPDiagnosticSetValue(@"BlankingObserverEvents", @[]);
    [self recordEvent:@"OBSERVER_STARTED" details:@{ @"registration": @"DarwinNotificationCenter" }];

    [self recordRuntimeClass:@"SBBacklightController" selectors:@[@"sharedInstance", @"screenIsOn", @"setIdleTimerDisabled:forReason:"]];
    [self recordRuntimeClass:@"SBLockScreenManager" selectors:@[@"sharedInstance", @"isUILocked"]];
    [self recordRuntimeClass:@"BKDisplayBrightnessController" selectors:@[@"sharedInstance", @"brightnessLevel"]];
    [self recordRuntimeClass:@"BKBacklightClient" selectors:@[@"init", @"setBacklightLocked:forReason:"]];
    [self recordRuntimeClass:@"BKDisplayBlankingObserver" selectors:@[@"init", @"invalidate"]];
    [self recordRuntimeClass:@"BLSBacklight" selectors:@[@"sharedBacklight", @"registerForBacklightUpdates"]];

    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    for (NSString *name in NNPNotificationNames()) {
        CFNotificationCenterAddObserver(center, (__bridge const void *)(self), NNPDarwinNotificationCallback, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    NNPDiagnosticSetBool(@"ObserverRegistrationSucceeded", YES);
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), NULL, NULL);
}

@end
