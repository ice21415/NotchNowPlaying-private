#import <Foundation/Foundation.h>
#import "../../NNPMengoDeferredClose.h"
#include <assert.h>
static BOOL inCallback;
static NSUInteger unscheduled, unregistered, ownersReleased;
@interface Owner : NSObject @end
@implementation Owner
- (void)dealloc { ownersReleased++; }
@end
static void Unschedule(CFTypeRef client, CFRunLoopRef runloop, CFStringRef mode) {
    assert(!inCallback && client && runloop == CFRunLoopGetMain() && CFEqual(mode, kCFRunLoopCommonModes));
    unscheduled++;
}
static void Unregister(CFTypeRef client) { assert(!inCallback && client); unregistered++; }
int main(void) {
    @autoreleasepool {
        Owner *owner = [Owner new]; __weak Owner *weak = owner;
        CFTypeRef client = CFBridgingRetain([NSObject new]);
        inCallback = YES;
        NNPMengoDeferredClose(client, owner, Unschedule, Unregister);
        owner = nil;
        assert(weak && unscheduled == 0 && unregistered == 0 && ownersReleased == 0);
        inCallback = NO;
        double deadline = NSProcessInfo.processInfo.systemUptime + 1;
        while (!unregistered && NSProcessInfo.processInfo.systemUptime < deadline)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        assert(unscheduled == 1 && unregistered == 1 && ownersReleased == 1 && !weak);
        NNPMengoDeferredClose(NULL, nil, Unschedule, Unregister);
        assert(unscheduled == 1 && unregistered == 1);
        puts("HID teardown waits for callback return and retains target through unregister");
    }
}
