#import "NNPMengoDeferredClose.h"
void NNPMengoDeferredClose(CFTypeRef client, id owner,
    void (*unschedule)(CFTypeRef, CFRunLoopRef, CFStringRef), void (*unregister)(CFTypeRef)) {
    if (!client) return;
    // Transfer the caller's +1 CF ownership to this block. Keep callback target
    // alive until registration is removed, after IOKit's current callback returns.
    dispatch_async(dispatch_get_main_queue(), ^{
        unschedule(client, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        unregister(client);
        CFRelease(client);
        (void)owner;
    });
}
