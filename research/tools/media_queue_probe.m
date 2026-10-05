#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <stdio.h>
static id Get(id object, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    return [object respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(object, sel) : nil;
}
static void Methods(Class cls) {
    unsigned count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned i = 0; i < count; i++) printf("METHOD %s %s\n", sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i]));
    free(methods);
}
int main(void) {
    @autoreleasepool {
        dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        for (NSString *name in @[@"MRPlaybackQueueRequest", @"MRNowPlayingController"]) {
            Class cls = NSClassFromString(name);
            printf("CLASS %s %s\n", name.UTF8String, cls ? "available" : "missing");
            if (cls) Methods(cls);
        }
        Protocol *protocol = objc_getProtocol("MRNowPlayingControllerDelegate");
        for (unsigned required = 0; required < 2; required++) {
            unsigned count = 0;
            struct objc_method_description *methods = protocol_copyMethodDescriptionList(protocol, required, YES, &count);
            for (unsigned i = 0; i < count; i++) printf("DELEGATE %s %s\n", sel_getName(methods[i].name), methods[i].types);
            free(methods);
        }
        Class controllerClass = NSClassFromString(@"MRNowPlayingController");
        id controller = Get(controllerClass, @"localRouteController");
        if (!controller) return 3;
        id configuration = Get(controller, @"configuration");
        id request = Get(NSClassFromString(@"MRPlaybackQueueRequest"), @"defaultPlaybackQueueRequest");
        printf("DEFAULT_REQUEST %s\n", [[request description] UTF8String]);
        if ([request respondsToSelector:@selector(setLength:)]) ((void (*)(id, SEL, long long))objc_msgSend)(request, @selector(setLength:), 3);
        if ([request respondsToSelector:@selector(setIncludeMetadata:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(request, @selector(setIncludeMetadata:), YES);
        if ([configuration respondsToSelector:@selector(setPlaybackQueueRequest:)]) ((void (*)(id, SEL, id))objc_msgSend)(configuration, @selector(setPlaybackQueueRequest:), request);
        if ([configuration respondsToSelector:@selector(setRequestPlaybackQueue:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(configuration, @selector(setRequestPlaybackQueue:), YES);
        if ([controller respondsToSelector:@selector(setConfiguration:)]) ((void (*)(id, SEL, id))objc_msgSend)(controller, @selector(setConfiguration:), configuration);
        if ([controller respondsToSelector:@selector(beginLoadingUpdates)]) ((void (*)(id, SEL))objc_msgSend)(controller, @selector(beginLoadingUpdates));
        for (unsigned i = 0; i < 4; i++) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3]];
            id response = Get(controller, @"response");
            id queue = Get(response, @"playbackQueue");
            printf("RESPONSE %s\n", [[response description] UTF8String] ?: "none");
            printf("QUEUE %s\n", [[queue description] UTF8String] ?: "none");
            for (id item in Get(queue, @"contentItems")) {
                printf("ITEM %s\n", [[Get(item, @"nowPlayingInfo") description] UTF8String] ?: "none");
            }
            fflush(stdout);
        }
        if ([controller respondsToSelector:@selector(endLoadingUpdates)]) ((void (*)(id, SEL))objc_msgSend)(controller, @selector(endLoadingUpdates));
    }
    return 0;
}
