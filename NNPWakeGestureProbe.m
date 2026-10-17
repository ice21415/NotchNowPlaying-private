#import "NNPWakeGestureProbe.h"
#import "NNPDiagnostics.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSInteger NNPProbeEventCount;
static void (*NNPProbeOriginal4)(id, SEL, id, long long, long long, id);
static void (*NNPProbeOriginal3)(id, SEL, id, long long, long long);

static void NNPProbeRecord(NSString *selectorName, long long gesture, long long orientation) {
    NNPProbeEventCount++;
    NNPDiagnosticSetInteger(@"WakeProbeEventCount", NNPProbeEventCount);
    NNPDiagnosticSetString(@"WakeProbeLastEvent", [NSString stringWithFormat:@"%@ gesture=%lld orientation=%lld t=%.1f",
        selectorName, gesture, orientation, NSDate.date.timeIntervalSince1970]);
}
static void NNPProbeDelegate4(id self, SEL _cmd, id manager, long long gesture, long long orientation, id detectedAt) {
    NNPProbeRecord(NSStringFromSelector(_cmd), gesture, orientation);
    if (NNPProbeOriginal4) NNPProbeOriginal4(self, _cmd, manager, gesture, orientation, detectedAt);
}
static void NNPProbeDelegate3(id self, SEL _cmd, id manager, long long gesture, long long orientation) {
    NNPProbeRecord(NSStringFromSelector(_cmd), gesture, orientation);
    if (NNPProbeOriginal3) NNPProbeOriginal3(self, _cmd, manager, gesture, orientation);
}

// Receives lift events when the system has no delegate of its own (Raise to Wake off).
@interface NNPWakeProbeDelegate : NSObject
@end
@implementation NNPWakeProbeDelegate
- (void)wakeGestureManager:(id)manager didUpdateWakeGesture:(long long)gesture orientation:(long long)orientation detectedAt:(id)detectedAt {
    NNPProbeRecord(@"own4", gesture, orientation);
}
- (void)wakeGestureManager:(id)manager didUpdateWakeGesture:(long long)gesture orientation:(long long)orientation {
    NNPProbeRecord(@"own3", gesture, orientation);
}
@end
static NNPWakeProbeDelegate *NNPProbeOwnDelegate;

void NNPWakeGestureProbeStartIfEnabled(void) {
    id flag = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("ResearchWakeGestureProbe"), CFSTR("com.user.notchnowplaying")));
    if (![flag respondsToSelector:@selector(boolValue)] || ![flag boolValue]) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class cls = NSClassFromString(@"CMWakeGestureManager");
        NNPDiagnosticSetBool(@"WakeProbeClassPresent", cls != Nil);
        if (!cls) return;
        SEL availableSel = NSSelectorFromString(@"isWakeGestureAvailable");
        BOOL available = [cls respondsToSelector:availableSel] && ((BOOL (*)(id, SEL))objc_msgSend)(cls, availableSel);
        NNPDiagnosticSetBool(@"WakeProbeAvailable", available);
        SEL sharedSel = NSSelectorFromString(@"sharedManager");
        if (![cls respondsToSelector:sharedSel]) return;
        id manager = ((id (*)(id, SEL))objc_msgSend)(cls, sharedSel);
        NNPDiagnosticSetBool(@"WakeProbeManagerPresent", manager != nil);
        if (!manager) return;
        id delegate = [manager respondsToSelector:@selector(delegate)] ? ((id (*)(id, SEL))objc_msgSend)(manager, @selector(delegate)) : nil;
        NNPDiagnosticSetString(@"WakeProbeDelegateClass", delegate ? NSStringFromClass([delegate class]) : @"none");
        if (delegate) {
            SEL four = NSSelectorFromString(@"wakeGestureManager:didUpdateWakeGesture:orientation:detectedAt:");
            SEL three = NSSelectorFromString(@"wakeGestureManager:didUpdateWakeGesture:orientation:");
            Method m4 = class_getInstanceMethod([delegate class], four);
            Method m3 = class_getInstanceMethod([delegate class], three);
            if (m4 && !NNPProbeOriginal4) NNPProbeOriginal4 = (void (*)(id, SEL, id, long long, long long, id))method_setImplementation(m4, (IMP)NNPProbeDelegate4);
            if (m3 && !NNPProbeOriginal3) NNPProbeOriginal3 = (void (*)(id, SEL, id, long long, long long))method_setImplementation(m3, (IMP)NNPProbeDelegate3);
            NNPDiagnosticSetString(@"WakeProbeHookedSelectors", [NSString stringWithFormat:@"4arg=%d 3arg=%d", m4 != NULL, m3 != NULL]);
        }
        if (!delegate && [manager respondsToSelector:NSSelectorFromString(@"setDelegate:")]) {
            NNPProbeOwnDelegate = [NNPWakeProbeDelegate new];
            ((void (*)(id, SEL, id))objc_msgSend)(manager, NSSelectorFromString(@"setDelegate:"), NNPProbeOwnDelegate);
            NNPDiagnosticSetBool(@"WakeProbeOwnDelegateSet", YES);
        }
        SEL startSel = NSSelectorFromString(@"startWakeGestureUpdates");
        if ([manager respondsToSelector:startSel]) {
            ((void (*)(id, SEL))objc_msgSend)(manager, startSel);
            NNPDiagnosticSetBool(@"WakeProbeStarted", YES);
        }
    });
}
