#import "NNPScreenCoverObserver.h"
#import "NNPCoverConfirmation.h"
#import "NNPDiagnostics.h"
#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <math.h>

static BOOL NNPCoverSetter(id object, SEL selector, char argument) {
    Method method = class_getInstanceMethod([object class], selector);
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char result[16] = {0}, input[16] = {0};
    method_getReturnType(method, result, sizeof(result));
    method_getArgumentType(method, 2, input, sizeof(input));
    return result[0] == 'v' && (input[0] == argument || (argument == 'B' && input[0] == 'c'));
}
@implementation NNPScreenCoverObserver {
    BOOL _active, _covered, _ownedProximity, _sensing, _lastNear, _faceDown, _haveLastAccel;
    CMMotionManager *_motion;
    id _proximityAssertion;
    BOOL (*_nativeNear)(void);
    BOOL (*_nativeActive)(void);
    NNPCoverConfirmation *_confirmation;
    NSUInteger _motionGeneration;
    NSUInteger _stillSamples;
    NSTimer *_windowTimer, *_periodicTimer;
    NSTimeInterval _windowEnd;
    double _lastX, _lastY, _lastZ;
}

// The proximity sensor is the expensive part (backboardd wakes continuously while it is on), so it only
// runs in short windows: at activation, when the accelerometer sees movement, and periodically.
static const NSTimeInterval NNPCoverMotionWindow = 2.5;
static const NSTimeInterval NNPCoverPeriodicWindow = 2.0;
static const NSTimeInterval NNPCoverPeriodicInterval = 15.0;
static const double NNPCoverMotionThreshold = 0.12;
static const NSUInteger NNPCoverStillSamplesBeforeSlowing = 20;

- (BOOL)covered { return _covered; }
- (NSTimeInterval)baseAccelerometerInterval { return _lowPower ? 2.0 : 0.5; }
- (void)applyAccelerometerInterval {
    NSTimeInterval base = [self baseAccelerometerInterval];
    NSTimeInterval interval = _stillSamples >= NNPCoverStillSamplesBeforeSlowing ? MIN(5.0, base * 2.5) : base;
    if (_motion && fabs(_motion.accelerometerUpdateInterval - interval) > 0.01) _motion.accelerometerUpdateInterval = interval;
}
- (void)setLowPower:(BOOL)lowPower {
    if (_lowPower == lowPower) return;
    _lowPower = lowPower;
    [self applyAccelerometerInterval];
}
- (BOOL)readProximityNear {
    UIDevice *device = UIDevice.currentDevice;
    return _nativeNear && _proximityAssertion ? _nativeNear() :
        (device.proximityMonitoringEnabled && device.proximityState);
}
- (BOOL)readCovered {
    UIDevice *device = UIDevice.currentDevice;
    BOOL near = _lastNear;
    if (_sensing) { near = [self readProximityNear]; _lastNear = near; }
    BOOL down = _faceDown || device.orientation == UIDeviceOrientationFaceDown;
    NNPDiagnosticSetBool(@"CoverProximityNear", near);
    NNPDiagnosticSetBool(@"CoverFaceDown", down);
    NNPDiagnosticSetBool(@"CoverNativeProximityActive", _sensing);
    return near || down;
}
- (void)publish:(BOOL)covered {
    if (_covered == covered) return;
    _covered = covered;
    NNPDiagnosticSetBool(@"ScreenCoverDetected", covered);
    if (self.stateChanged) self.stateChanged(covered);
}
- (void)changed:(__unused NSNotification *)note {
    if (!_active) return;
    BOOL target = [self readCovered];
    [_confirmation update:target];
}
- (void)startNativeProximity {
    void *handle = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY | RTLD_LOCAL);
    _nativeNear = dlsym(handle, "BKSHIDServicesGetObjectWithinProximity");
    _nativeActive = dlsym(handle, "BKSHIDServicesProximityDetectionActive");
    BOOL (*valid)(int) = dlsym(handle, "BKSHIDServicesProximityDetectionModeIsValid");
    NSString *(*name)(int) = dlsym(handle, "NSStringFromBKSHIDServicesProximityDetectionMode");
    if (!_nativeNear || !valid || !name || !valid(6) || ![name(6) isEqualToString:@"lowPowerActive"]) return;
    Class cls = NSClassFromString(@"BKSHIDUISensorMode");
    SEL build = NSSelectorFromString(@"buildModeForReason:builder:");
    Method factory = class_getClassMethod(cls, build);
    char result[16] = {0};
    if (!factory || method_getNumberOfArguments(factory) != 4) return;
    method_getReturnType(factory, result, sizeof(result));
    if (result[0] != '@') return;
    id mode = ((id (*)(id, SEL, id, id))objc_msgSend)(cls, build, @"NNP AOD cover detection", ^(id builder) {
        SEL proximity = NSSelectorFromString(@"setProximityDetectionMode:");
        SEL digitizer = NSSelectorFromString(@"setDigitizerEnabled:");
        if (!NNPCoverSetter(builder, proximity, 'i') || !NNPCoverSetter(builder, digitizer, 'B')) return;
        ((void (*)(id, SEL, int))objc_msgSend)(builder, proximity, 6);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(builder, digitizer, YES);
    });
    Class serviceClass = NSClassFromString(@"BKSHIDUISensorService");
    if (!mode || ![serviceClass respondsToSelector:NSSelectorFromString(@"sharedInstance")]) return;
    id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, NSSelectorFromString(@"sharedInstance"));
    SEL request = NSSelectorFromString(@"requestUISensorMode:");
    Method method = class_getInstanceMethod([service class], request);
    if (!method || method_getNumberOfArguments(method) != 3) return;
    method_getReturnType(method, result, sizeof(result));
    if (result[0] != '@') return;
    _proximityAssertion = ((id (*)(id, SEL, id))objc_msgSend)(service, request, mode);
    NNPDiagnosticSetBool(@"CoverNativeProximityAssertion", _proximityAssertion != nil);
}
- (void)stopNativeProximity {
    SEL invalidate = NSSelectorFromString(@"invalidate");
    Method method = class_getInstanceMethod([_proximityAssertion class], invalidate);
    if (method && method_getNumberOfArguments(method) == 2)
        ((void (*)(id, SEL))objc_msgSend)(_proximityAssertion, invalidate);
    _proximityAssertion = nil;
    NNPDiagnosticSetBool(@"CoverNativeProximityAssertion", NO);
}
- (void)beginSensing {
    if (_sensing || !_active) return;
    _sensing = YES;
    UIDevice *device = UIDevice.currentDevice;
    _ownedProximity = !device.proximityMonitoringEnabled;
    if (_ownedProximity) device.proximityMonitoringEnabled = YES;
    [self startNativeProximity];
}
- (void)endSensingKeepingReading:(BOOL)keepReading {
    if (!_sensing) return;
    if (keepReading) _lastNear = [self readProximityNear];
    _sensing = NO;
    [self stopNativeProximity];
    if (_ownedProximity) UIDevice.currentDevice.proximityMonitoringEnabled = NO;
    _ownedProximity = NO;
}
- (void)openSensingWindow:(NSTimeInterval)duration {
    if (!_active) return;
    [self beginSensing];
    NSTimeInterval end = NSProcessInfo.processInfo.systemUptime + duration;
    if (_windowTimer && _windowEnd >= end) return;
    _windowEnd = end;
    [_windowTimer invalidate];
    __weak typeof(self) weakSelf = self;
    _windowTimer = [NSTimer scheduledTimerWithTimeInterval:duration repeats:NO block:^(__unused NSTimer *timer) {
        NNPScreenCoverObserver *owner = weakSelf;
        if (!owner) return;
        owner->_windowTimer = nil;
        [owner endSensingKeepingReading:YES];
        [owner changed:nil];
    }];
    _windowTimer.tolerance = 0.3;
}
- (void)teardownSensing {
    [_windowTimer invalidate]; _windowTimer = nil;
    [_periodicTimer invalidate]; _periodicTimer = nil;
    [self endSensingKeepingReading:NO];
}
- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active;
    NSUInteger motionGeneration = ++_motionGeneration;
    [_confirmation reset];
    UIDevice *device = UIDevice.currentDevice;
    if (!active) {
        [_motion stopAccelerometerUpdates]; _motion = nil;
        [self teardownSensing];
        _faceDown = NO;
        _lastNear = NO;
        _haveLastAccel = NO;
        _stillSamples = 0;
        [NSNotificationCenter.defaultCenter removeObserver:self];
        [self publish:NO];
        return;
    }
    __weak typeof(self) confirmationOwner = self;
    if (!_confirmation) {
        _confirmation = [NNPCoverConfirmation new];
        _confirmation.onChange = ^(BOOL covered) { [confirmationOwner publish:covered]; };
    }
    _lastNear = NO;
    _haveLastAccel = NO;
    _stillSamples = 0;
    [self openSensingWindow:3.0];
    __weak typeof(self) periodicOwner = self;
    _periodicTimer = [NSTimer scheduledTimerWithTimeInterval:NNPCoverPeriodicInterval repeats:YES block:^(__unused NSTimer *timer) {
        [periodicOwner openSensingWindow:NNPCoverPeriodicWindow];
    }];
    _periodicTimer.tolerance = 3.0;
    _motion = [CMMotionManager new];
    _motion.accelerometerUpdateInterval = [self baseAccelerometerInterval];
    NNPDiagnosticSetBool(@"CoverMotionAvailable", _motion.accelerometerAvailable);
    __weak typeof(self) weakSelf = self;
    [_motion startAccelerometerUpdatesToQueue:NSOperationQueue.mainQueue withHandler:^(CMAccelerometerData *data, NSError *error) {
        NNPScreenCoverObserver *owner = weakSelf;
        if (!owner || !owner->_active || owner->_motionGeneration != motionGeneration ||
            !data || error || !isfinite(data.acceleration.z)) return;
        double age = NSProcessInfo.processInfo.systemUptime - data.timestamp;
        if (age < 0 || age > 6.0) return;
        CMAcceleration a = data.acceleration;
        BOOL moved = owner->_haveLastAccel &&
            (fabs(a.x - owner->_lastX) + fabs(a.y - owner->_lastY) + fabs(a.z - owner->_lastZ)) > NNPCoverMotionThreshold;
        owner->_lastX = a.x; owner->_lastY = a.y; owner->_lastZ = a.z;
        owner->_haveLastAccel = YES;
        if (moved) {
            owner->_stillSamples = 0;
            [owner applyAccelerometerInterval];
            [owner openSensingWindow:NNPCoverMotionWindow];
        } else if (++owner->_stillSamples == NNPCoverStillSamplesBeforeSlowing) {
            [owner applyAccelerometerInterval];
        }
        owner->_faceDown = owner->_faceDown ? a.z > 0.65 : a.z > 0.85;
        NNPDiagnosticSetBool(@"CoverMotionSampleReceived", YES);
        [owner changed:nil];
    }];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:)
        name:UIDeviceProximityStateDidChangeNotification object:device];
    NNPDiagnosticSetBool(@"CoverProximityMonitoringAvailable", YES);
    [self changed:nil];
}
- (void)dealloc {
    [_motion stopAccelerometerUpdates];
    [self teardownSensing];
    [_confirmation reset];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
@end
