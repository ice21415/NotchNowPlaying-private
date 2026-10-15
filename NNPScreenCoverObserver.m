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
    BOOL _active, _covered, _ownedProximity;
    BOOL _faceDown;
    CMMotionManager *_motion;
    id _proximityAssertion;
    BOOL (*_nativeNear)(void);
    BOOL (*_nativeActive)(void);
    NNPCoverConfirmation *_confirmation;
    NSUInteger _motionGeneration;
}
- (BOOL)covered { return _covered; }
- (void)setLowPower:(BOOL)lowPower {
    if (_lowPower == lowPower) return;
    _lowPower = lowPower;
    _motion.accelerometerUpdateInterval = lowPower ? 2.0 : 0.5;
}
- (BOOL)readCovered {
    UIDevice *device = UIDevice.currentDevice;
    BOOL near = _nativeNear && _proximityAssertion ? _nativeNear() :
        (device.proximityMonitoringEnabled && device.proximityState);
    BOOL down = _faceDown || device.orientation == UIDeviceOrientationFaceDown;
    NNPDiagnosticSetBool(@"CoverProximityNear", near);
    NNPDiagnosticSetBool(@"CoverFaceDown", down);
    NNPDiagnosticSetBool(@"CoverNativeProximityActive", _nativeActive && _nativeActive());
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
- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active;
    NSUInteger motionGeneration = ++_motionGeneration;
    [_confirmation reset];
    UIDevice *device = UIDevice.currentDevice;
    if (!active) {
        [_motion stopAccelerometerUpdates]; _motion = nil;
        [self stopNativeProximity];
        _faceDown = NO;
        [NSNotificationCenter.defaultCenter removeObserver:self];
        if (_ownedProximity) device.proximityMonitoringEnabled = NO;
        _ownedProximity = NO;
        [device endGeneratingDeviceOrientationNotifications];
        [self publish:NO];
        return;
    }
    _ownedProximity = !device.proximityMonitoringEnabled;
    if (_ownedProximity) device.proximityMonitoringEnabled = YES;
    __weak typeof(self) confirmationOwner = self;
    if (!_confirmation) {
        _confirmation = [NNPCoverConfirmation new];
        _confirmation.onChange = ^(BOOL covered) { [confirmationOwner publish:covered]; };
    }
    [self startNativeProximity];
    _motion = [CMMotionManager new];
    _motion.accelerometerUpdateInterval = _lowPower ? 2.0 : 0.5;
    NNPDiagnosticSetBool(@"CoverMotionAvailable", _motion.accelerometerAvailable);
    __weak typeof(self) weakSelf = self;
    [_motion startAccelerometerUpdatesToQueue:NSOperationQueue.mainQueue withHandler:^(CMAccelerometerData *data, NSError *error) {
        NNPScreenCoverObserver *owner = weakSelf;
        if (!owner || !owner->_active || owner->_motionGeneration != motionGeneration ||
            !data || error || !isfinite(data.acceleration.z)) return;
        double age = NSProcessInfo.processInfo.systemUptime - data.timestamp;
        if (age < 0 || age > 3.0) return;
        owner->_faceDown = owner->_faceDown ? data.acceleration.z > 0.65 : data.acceleration.z > 0.85;
        NNPDiagnosticSetBool(@"CoverMotionSampleReceived", YES);
        [owner changed:nil];
    }];
    [device beginGeneratingDeviceOrientationNotifications];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:)
        name:UIDeviceProximityStateDidChangeNotification object:device];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:)
        name:UIDeviceOrientationDidChangeNotification object:device];
    NNPDiagnosticSetBool(@"CoverProximityMonitoringAvailable", device.proximityMonitoringEnabled);
    [self changed:nil];
}
- (void)dealloc {
    [_motion stopAccelerometerUpdates];
    [self stopNativeProximity];
    [_confirmation reset];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_active) {
        if (_ownedProximity) UIDevice.currentDevice.proximityMonitoringEnabled = NO;
        [UIDevice.currentDevice endGeneratingDeviceOrientationNotifications];
    }
}
@end
