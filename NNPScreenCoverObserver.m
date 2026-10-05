#import "NNPScreenCoverObserver.h"
#import "NNPDiagnostics.h"
#import <UIKit/UIKit.h>
@implementation NNPScreenCoverObserver {
    BOOL _active, _covered, _ownedProximity;
    NSTimer *_confirmation;
    NSUInteger _generation;
}
- (BOOL)covered { return _covered; }
- (BOOL)readCovered {
    UIDevice *device = UIDevice.currentDevice;
    BOOL near = device.proximityMonitoringEnabled && device.proximityState;
    BOOL down = device.orientation == UIDeviceOrientationFaceDown;
    NNPDiagnosticSetBool(@"CoverProximityNear", near);
    NNPDiagnosticSetBool(@"CoverFaceDown", down);
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
    [_confirmation invalidate]; _confirmation = nil;
    NSUInteger generation = ++_generation;
    if (target == _covered) return;
    __weak typeof(self) weakSelf = self;
    _confirmation = [NSTimer scheduledTimerWithTimeInterval:target ? 0.8 : 0.25 repeats:NO
        block:^(__unused NSTimer *timer) {
            NNPScreenCoverObserver *owner = weakSelf;
            if (!owner || !owner->_active || generation != owner->_generation) return;
            owner->_confirmation = nil;
            [owner publish:[owner readCovered]];
        }];
}
- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active;
    ++_generation;
    [_confirmation invalidate]; _confirmation = nil;
    UIDevice *device = UIDevice.currentDevice;
    if (!active) {
        [NSNotificationCenter.defaultCenter removeObserver:self];
        if (_ownedProximity) device.proximityMonitoringEnabled = NO;
        _ownedProximity = NO;
        [device endGeneratingDeviceOrientationNotifications];
        [self publish:NO];
        return;
    }
    _ownedProximity = !device.proximityMonitoringEnabled;
    if (_ownedProximity) device.proximityMonitoringEnabled = YES;
    [device beginGeneratingDeviceOrientationNotifications];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:)
        name:UIDeviceProximityStateDidChangeNotification object:device];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:)
        name:UIDeviceOrientationDidChangeNotification object:device];
    NNPDiagnosticSetBool(@"CoverProximityMonitoringAvailable", device.proximityMonitoringEnabled);
    [self changed:nil];
}
- (void)dealloc {
    [_confirmation invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_active) {
        if (_ownedProximity) UIDevice.currentDevice.proximityMonitoringEnabled = NO;
        [UIDevice.currentDevice endGeneratingDeviceOrientationNotifications];
    }
}
@end
