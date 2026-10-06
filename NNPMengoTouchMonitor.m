#import "NNPMengoTouchMonitor.h"
#import "NNPMengoWakePolicy.h"
#import "NNPDiagnostics.h"
#import "NNPMengoDeferredClose.h"
#include <stdint.h>
#import <dlfcn.h>

static uint32_t (*NNPType)(CFTypeRef);
static double (*NNPFloat)(CFTypeRef, uint32_t);
static CFIndex (*NNPInteger)(CFTypeRef, uint32_t);
static CFArrayRef (*NNPChildren)(CFTypeRef);
static void (*NNPRegister)(CFTypeRef, void (*)(void *, void *, void *, CFTypeRef), void *, void *);
static void (*NNPUnregister)(CFTypeRef);
static void (*NNPSchedule)(CFTypeRef, CFRunLoopRef, CFStringRef);
static void (*NNPUnschedule)(CFTypeRef, CFRunLoopRef, CFStringRef);

@interface NNPMengoTouchMonitor ()
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL lastDown;
@property(nonatomic) NSUInteger generation;
- (void)receive:(CFTypeRef)event generation:(NSUInteger)generation;
@end
static void NNPMonitorEvent(void *target, void *refcon, void *sender, CFTypeRef event) {
    NNPMengoTouchMonitor *owner = (__bridge NNPMengoTouchMonitor *)target;
    [owner receive:event generation:(NSUInteger)(uintptr_t)refcon];
}
@implementation NNPMengoTouchMonitor {
    CFTypeRef _client;
}
- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active; _lastDown = NO; self.generation++;
    if (!active) {
        if (_client) {
            CFTypeRef retired = _client; _client = NULL;
            NNPMengoDeferredClose(retired, self, NNPUnschedule, NNPUnregister);
        }
        NNPDiagnosticSetBool(@"MengoTouchMonitorActive", NO);
        return;
    }
    static CFTypeRef (*create)(CFAllocatorRef, int, CFDictionaryRef);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        create = dlsym(library, "IOHIDEventSystemClientCreateWithType");
        NNPRegister = dlsym(library, "IOHIDEventSystemClientRegisterEventCallback");
        NNPUnregister = dlsym(library, "IOHIDEventSystemClientUnregisterEventCallback");
        NNPSchedule = dlsym(library, "IOHIDEventSystemClientScheduleWithRunLoop");
        NNPUnschedule = dlsym(library, "IOHIDEventSystemClientUnscheduleWithRunLoop");
        NNPType = dlsym(library, "IOHIDEventGetType"); NNPFloat = dlsym(library, "IOHIDEventGetFloatValue");
        NNPInteger = dlsym(library, "IOHIDEventGetIntegerValue"); NNPChildren = dlsym(library, "IOHIDEventGetChildren");
    });
    if (create && NNPRegister && NNPUnregister && NNPSchedule && NNPUnschedule && NNPType && NNPFloat && NNPInteger && NNPChildren)
        _client = create(kCFAllocatorDefault, 1, NULL);
    if (_client) {
        NNPRegister(_client, NNPMonitorEvent, (__bridge void *)self, (void *)(uintptr_t)self.generation);
        NNPSchedule(_client, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    }
    NNPDiagnosticSetBool(@"MengoTouchMonitorActive", _client != NULL);
}
- (void)receive:(CFTypeRef)event generation:(NSUInteger)generation {
    if (!_active || generation != self.generation || !event || NNPType(event) != 11 || !NSThread.isMainThread) return;
    CFTypeRef nodes[16] = {event}; int count = 1;
    for (int index = 0; index < count; index++) {
        CFTypeRef node = nodes[index];
        CFArrayRef children = NNPChildren(node);
        BOOL leaf = !children || CFArrayGetCount(children) == 0;
        if (NNPType(node) == 11 && leaf) {
            double x = NNPFloat(node, 11u << 16), y = NNPFloat(node, (11u << 16) | 1);
            BOOL down = NNPInteger(node, (11u << 16) | 9) != 0;
            if (!NNPMengoWakePositionValid(x, y)) continue;
            if (down != _lastDown) {
                _lastDown = down;
                NNPDiagnosticSetString(@"MengoMonitorPoint", NSStringFromCGPoint(CGPointMake(x, y)));
                NNPDiagnosticSetBool(@"MengoMonitorContactDown", down);
                if (self.contact) self.contact(CGPointMake(x, y), down);
            }
            return;
        }
        if (children) for (CFIndex child = 0; child < CFArrayGetCount(children) && count < 16; child++)
            nodes[count++] = CFArrayGetValueAtIndex(children, child);
    }
}
- (void)dealloc {
    if (_client) {
        NNPUnschedule(_client, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        NNPUnregister(_client); CFRelease(_client);
    }
}
@end
