#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include <stdio.h>
static uint32_t (*typeOf)(CFTypeRef);
static double (*floatOf)(CFTypeRef, uint32_t);
static CFIndex (*integerOf)(CFTypeRef, uint32_t);
static CFArrayRef (*childrenOf)(CFTypeRef);
static unsigned printed;
static void TouchEvent(void *target, void *refcon, void *sender, CFTypeRef event) {
    if (!event || typeOf(event) != 11 || printed >= 40) return;
    @autoreleasepool {
        NSMutableArray *rows = [NSMutableArray array];
        CFTypeRef nodes[16] = {event}; int count = 1;
        for (int index = 0; index < count; index++) {
            CFTypeRef node = nodes[index];
            if (typeOf(node) == 11) [rows addObject:@{
                @"x": @(floatOf(node, 11u << 16)), @"y": @(floatOf(node, (11u << 16) | 1)),
                @"touch": @(integerOf(node, (11u << 16) | 9)),
                @"collection": @(integerOf(node, 1)), @"pixels": @(integerOf(node, 2))}];
            CFArrayRef children = childrenOf(node);
            if (children) for (CFIndex i = 0; i < CFArrayGetCount(children) && count < 16; i++)
                nodes[count++] = CFArrayGetValueAtIndex(children, i);
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:rows options:0 error:nil];
        if (data) { puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String); printed++; }
    }
}
int main(void) {
    @autoreleasepool {
        setbuf(stdout, NULL);
        void *library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        CFTypeRef (*create)(CFAllocatorRef, int, CFDictionaryRef) = dlsym(library, "IOHIDEventSystemClientCreateWithType");
        void (*callback)(CFTypeRef, void (*)(void *, void *, void *, CFTypeRef), void *, void *) = dlsym(library, "IOHIDEventSystemClientRegisterEventCallback");
        void (*schedule)(CFTypeRef, CFRunLoopRef, CFStringRef) = dlsym(library, "IOHIDEventSystemClientScheduleWithRunLoop");
        void (*unschedule)(CFTypeRef, CFRunLoopRef, CFStringRef) = dlsym(library, "IOHIDEventSystemClientUnscheduleWithRunLoop");
        void (*unregister)(CFTypeRef) = dlsym(library, "IOHIDEventSystemClientUnregisterEventCallback");
        typeOf = dlsym(library, "IOHIDEventGetType"); floatOf = dlsym(library, "IOHIDEventGetFloatValue");
        integerOf = dlsym(library, "IOHIDEventGetIntegerValue"); childrenOf = dlsym(library, "IOHIDEventGetChildren");
        if (!create || !callback || !schedule || !unschedule || !unregister || !typeOf || !floatOf || !integerOf || !childrenOf) return 2;
        CFTypeRef client = create(kCFAllocatorDefault, 1, NULL);
        if (!client) { puts("MONITOR_UNAVAILABLE"); return 3; }
        callback(client, TouchEvent, NULL, NULL);
        schedule(client, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        puts("MONITOR_READY_20_SECONDS");
        double deadline = NSProcessInfo.processInfo.systemUptime + 20;
        while (NSProcessInfo.processInfo.systemUptime < deadline)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        unschedule(client, CFRunLoopGetMain(), kCFRunLoopCommonModes); unregister(client); CFRelease(client);
        printf("MONITOR_DONE samples=%u\n", printed);
    }
    return 0;
}
