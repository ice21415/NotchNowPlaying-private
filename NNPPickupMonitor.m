#import "NNPPickupMonitor.h"
#import "NNPDiagnostics.h"
#import <objc/runtime.h>
#import <objc/message.h>

static __weak NNPPickupMonitor *NNPActiveMonitor;
static void (*NNPOriginalDelegate4)(id, SEL, id, long long, long long, id);
static void (*NNPOriginalDelegate3)(id, SEL, id, long long, long long);

static void NNPPickupDeliver(long long gesture, long long orientation) {
    NNPDiagnosticTrace([NSString stringWithFormat:@"PICKUP event gesture=%lld orientation=%lld", gesture, orientation]);
    dispatch_async(dispatch_get_main_queue(), ^{
        NNPPickupMonitor *monitor = NNPActiveMonitor;
        if (monitor.event) monitor.event(gesture);
    });
}
static void NNPObservedDelegate4(id self, SEL _cmd, id manager, long long gesture, long long orientation, id detectedAt) {
    NNPPickupDeliver(gesture, orientation);
    if (NNPOriginalDelegate4) NNPOriginalDelegate4(self, _cmd, manager, gesture, orientation, detectedAt);
}
static void NNPObservedDelegate3(id self, SEL _cmd, id manager, long long gesture, long long orientation) {
    NNPPickupDeliver(gesture, orientation);
    if (NNPOriginalDelegate3) NNPOriginalDelegate3(self, _cmd, manager, gesture, orientation);
}

@interface NNPPickupOwnDelegate : NSObject
@end
@implementation NNPPickupOwnDelegate
- (void)wakeGestureManager:(id)manager didUpdateWakeGesture:(long long)gesture orientation:(long long)orientation detectedAt:(id)detectedAt { NNPPickupDeliver(gesture, orientation); }
- (void)wakeGestureManager:(id)manager didUpdateWakeGesture:(long long)gesture orientation:(long long)orientation { NNPPickupDeliver(gesture, orientation); }
@end

@implementation NNPPickupMonitor {
    BOOL _active;
    NNPPickupOwnDelegate *_ownDelegate;
    id _manager;
}
- (id)manager {
    if (_manager) return _manager;
    Class cls = NSClassFromString(@"CMWakeGestureManager");
    SEL availableSel = NSSelectorFromString(@"isWakeGestureAvailable"), sharedSel = NSSelectorFromString(@"sharedManager");
    if (!cls || ![cls respondsToSelector:availableSel] || ![cls respondsToSelector:sharedSel]) return nil;
    if (!((BOOL (*)(id, SEL))objc_msgSend)(cls, availableSel)) return nil;
    _manager = ((id (*)(id, SEL))objc_msgSend)(cls, sharedSel);
    return _manager;
}
- (void)setActive:(BOOL)active {
    if (_active == active) return;
    id manager = [self manager];
    if (!manager) { NNPDiagnosticSetBool(@"PickupMonitorAvailable", NO); return; }
    SEL delegateSel = NSSelectorFromString(@"delegate"), setDelegateSel = NSSelectorFromString(@"setDelegate:");
    SEL startSel = NSSelectorFromString(@"startWakeGestureUpdates"), stopSel = NSSelectorFromString(@"stopWakeGestureUpdates");
    if (![manager respondsToSelector:delegateSel] || ![manager respondsToSelector:setDelegateSel] ||
        ![manager respondsToSelector:startSel] || ![manager respondsToSelector:stopSel]) { NNPDiagnosticSetBool(@"PickupMonitorAvailable", NO); return; }
    id delegate = ((id (*)(id, SEL))objc_msgSend)(manager, delegateSel);
    if (active) {
        NNPActiveMonitor = self;
        if (!delegate) {
            _ownDelegate = [NNPPickupOwnDelegate new];
            ((void (*)(id, SEL, id))objc_msgSend)(manager, setDelegateSel, _ownDelegate);
            ((void (*)(id, SEL))objc_msgSend)(manager, startSel);
            NNPDiagnosticSetString(@"PickupMonitorMode", @"own delegate");
        } else if (delegate != _ownDelegate) {
            Class delegateClass = [delegate class];
            Method m4 = class_getInstanceMethod(delegateClass, NSSelectorFromString(@"wakeGestureManager:didUpdateWakeGesture:orientation:detectedAt:"));
            Method m3 = class_getInstanceMethod(delegateClass, NSSelectorFromString(@"wakeGestureManager:didUpdateWakeGesture:orientation:"));
            if (m4 && !NNPOriginalDelegate4) NNPOriginalDelegate4 = (void (*)(id, SEL, id, long long, long long, id))method_setImplementation(m4, (IMP)NNPObservedDelegate4);
            if (m3 && !NNPOriginalDelegate3) NNPOriginalDelegate3 = (void (*)(id, SEL, id, long long, long long))method_setImplementation(m3, (IMP)NNPObservedDelegate3);
            NNPDiagnosticSetString(@"PickupMonitorMode", @"observing system delegate");
        }
    } else if (_ownDelegate) {
        if (((id (*)(id, SEL))objc_msgSend)(manager, delegateSel) == _ownDelegate) {
            ((void (*)(id, SEL))objc_msgSend)(manager, stopSel);
            ((void (*)(id, SEL, id))objc_msgSend)(manager, setDelegateSel, nil);
        }
        _ownDelegate = nil;
    }
    _active = active;
    NNPDiagnosticSetBool(@"PickupMonitorAvailable", YES);
    NNPDiagnosticSetBool(@"PickupMonitorActive", active);
}
@end
