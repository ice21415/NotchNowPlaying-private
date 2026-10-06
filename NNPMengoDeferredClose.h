#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void NNPMengoDeferredClose(CFTypeRef client, id owner,
    void (*unschedule)(CFTypeRef, CFRunLoopRef, CFStringRef), void (*unregister)(CFTypeRef));
