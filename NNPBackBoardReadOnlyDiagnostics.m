#import "NNPBackBoardReadOnlyDiagnostics.h"
#import "NNPDiagnostics.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <unistd.h>

#ifndef NNP_PHASE2J_CALL_GETTERS
#define NNP_PHASE2J_CALL_GETTERS 0
#endif

typedef BOOL (*NNPBKSStartFunction)(void);
typedef BOOL (*NNPIsScreenDisabledFunction)(id);
typedef BOOL (*NNPGetBlankingRemovesPowerFunction)(id);

@interface NNPBackBoardReadOnlyDiagnostics ()
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL identifierFound;
@property(nonatomic, strong) id displayIdentifier;
@property(nonatomic, strong) id displayObject;
@property(nonatomic) NNPIsScreenDisabledFunction isScreenDisabled;
@property(nonatomic) NNPGetBlankingRemovesPowerFunction getBlankingRemovesPower;
@property(nonatomic, strong) NSTimer *lockTimer;
@property(nonatomic) BOOL lastLocked;
@property(nonatomic) BOOL sawLock;
@property(nonatomic) NSUInteger sequence;
@property(nonatomic) mach_timebase_info_data_t timebase;
@end

static NSString *NNPBBWallTime(void) { return [[NSDate date] description]; }
static NSNumber *NNPBBMonotonicMilliseconds(mach_timebase_info_data_t timebase) {
    uint64_t nanos = mach_absolute_time() * timebase.numer / timebase.denom;
    return @(nanos / 1000000ULL);
}

static BOOL NNPBBLocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    SEL locked = NSSelectorFromString(@"isUILocked");
    if (!cls || ![cls respondsToSelector:shared]) return NO;
    id manager = ((id (*)(id, SEL))objc_msgSend)((id)cls, shared);
    if (!manager || ![manager respondsToSelector:locked]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(manager, locked);
}

static NSNumber *NNPBBScreenIsOn(void) {
    Class cls = NSClassFromString(@"SBBacklightController");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    SEL screenIsOn = NSSelectorFromString(@"screenIsOn");
    if (!cls || ![cls respondsToSelector:shared]) return nil;
    id controller = ((id (*)(id, SEL))objc_msgSend)((id)cls, shared);
    if (!controller || ![controller respondsToSelector:screenIsOn]) return nil;
    return @(((BOOL (*)(id, SEL))objc_msgSend)(controller, screenIsOn));
}

@implementation NNPBackBoardReadOnlyDiagnostics

- (void)recordEvent:(NSString *)event {
    if (!event.length) return;
    NSMutableDictionary *entry = [@{
        @"event": event,
        @"wallTimestamp": NNPBBWallTime(),
        @"monotonicMilliseconds": NNPBBMonotonicMilliseconds(_timebase),
        @"sequence": @(++_sequence),
        @"SpringBoardPID": @(getpid()),
        @"logicalLock": @(NNPBBLocked())
    } mutableCopy];
    NSNumber *screenOn = NNPBBScreenIsOn();
    if (screenOn) entry[@"screenIsOn"] = screenOn;
 #if NNP_PHASE2J_CALL_GETTERS
    if (_isScreenDisabled && _identifierFound) {
        entry[@"screenDisabled"] = @(_isScreenDisabled(_displayIdentifier));
    }
    if (_getBlankingRemovesPower && _displayObject) {
        entry[@"blankingRemovesPower"] = @(_getBlankingRemovesPower(_displayObject));
    }
 #endif
    NNPDiagnosticAppendEvent(entry);
}

- (void)recordNotification:(NSString *)name { [self recordEvent:name]; }

static void NNPBBDarwinCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NNPBackBoardReadOnlyDiagnostics *target = (__bridge NNPBackBoardReadOnlyDiagnostics *)observer;
    NSString *event = name ? [(__bridge NSString *)name copy] : @"unknown-notification";
    [target performSelectorOnMainThread:@selector(recordNotification:) withObject:event waitUntilDone:NO];
}

- (void)takeSnapshot:(NSString *)event {
    [self recordEvent:event];
    NNPDiagnosticSetBool(@"LogicalLock", NNPBBLocked());
    NSNumber *screenOn = NNPBBScreenIsOn();
    if (screenOn) NNPDiagnosticSetBool(@"ScreenIsOn", screenOn.boolValue);
    NNPDiagnosticSetString(@"LastReadTimestamp", NNPBBWallTime());
}

- (void)pollLockState:(NSTimer *)timer {
    BOOL locked = NNPBBLocked();
    if (locked != _lastLocked) {
        _lastLocked = locked;
        [self takeSnapshot:(locked ? @"LOGICAL_LOCK=1" : @"LOGICAL_LOCK=0")];
        if (locked) _sawLock = YES;
        if (!locked && _sawLock) {
            NNPDiagnosticSetBool(@"BackBoardReadOnlyVerificationCompleted", YES);
            [_lockTimer invalidate];
            _lockTimer = nil;
        }
    }
}

- (id)realMainDisplayObject {
    UIScreen *screen = [UIScreen mainScreen];
    SEL displaySelector = NSSelectorFromString(@"_display");
    if (!screen || ![screen respondsToSelector:displaySelector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(screen, displaySelector);
}

- (void)start {
    if (_started) return;
    _started = YES;
    mach_timebase_info(&_timebase);

    void *handle = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY | RTLD_LOCAL);
    NNPBKSStartFunction startFunction = (NNPBKSStartFunction)dlsym(handle ?: RTLD_DEFAULT, "BKSDisplayServicesStart");
    _isScreenDisabled = (NNPIsScreenDisabledFunction)dlsym(handle ?: RTLD_DEFAULT, "BKSDisplayServicesIsScreenDisabled");
    _getBlankingRemovesPower = (NNPGetBlankingRemovesPowerFunction)dlsym(handle ?: RTLD_DEFAULT, "BKSDisplayServicesGetBlankingRemovesPower");
    NNPDiagnosticSetBool(@"BKSStartResolved", startFunction != NULL);
    NNPDiagnosticSetBool(@"IsScreenDisabledResolved", _isScreenDisabled != NULL);
    NNPDiagnosticSetBool(@"GetBlankingRemovesPowerResolved", _getBlankingRemovesPower != NULL);
    if (!startFunction) { NNPDiagnosticSetString(@"LastError", @"BKSDisplayServicesStart unresolved"); return; }
    BOOL started = startFunction();
    NNPDiagnosticSetBool(@"BKSStartResult", started);
    if (!started) { NNPDiagnosticSetString(@"LastError", @"BKSDisplayServicesStart returned NO"); return; }

    // Phase 2I recovered this exact main-display identifier constant from the
    // client wrapper comparison; no integer display ID is substituted.
    _displayIdentifier = @"<main>";
    _identifierFound = YES;
    NNPDiagnosticSetBool(@"MainDisplayIdentifierFound", YES);
    NNPDiagnosticSetString(@"MainDisplayIdentifierClass", NSStringFromClass([_displayIdentifier class]));
    NNPDiagnosticSetString(@"MainDisplayIdentifierSource", @"Phase2I client-wrapper disassembly constant <main>");

    _displayObject = [self realMainDisplayObject];
    NNPDiagnosticSetBool(@"MainDisplayObjectFound", _displayObject != nil);
    if (_displayObject) NNPDiagnosticSetString(@"MainDisplayObjectClass", NSStringFromClass([_displayObject class]));

    [self takeSnapshot:@"AWAKE_BASELINE"];
    NSArray *names = @[@"com.apple.springboard.hasBlankedScreen", @"com.apple.backboardd.backlight.changed"];
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    for (NSString *name in names) {
        CFNotificationCenterAddObserver(center, (__bridge const void *)(self), NNPBBDarwinCallback, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    NNPDiagnosticSetBool(@"BackBoardReadOnlyObserverRegistrationSucceeded", YES);
    _lastLocked = NNPBBLocked();
    _lockTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(pollLockState:) userInfo:nil repeats:YES];
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), NULL, NULL);
    [_lockTimer invalidate];
}

@end
