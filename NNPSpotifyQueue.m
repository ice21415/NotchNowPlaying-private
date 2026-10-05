#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Read only object-returning getters. Spotify's private model varies by version.
static id NNPQueueGet(id object, NSString *name) {
    Method method = class_getInstanceMethod([object class], NSSelectorFromString(name));
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name));
}
static NSString *NNPQueueString(id value) {
    if ([value isKindOfClass:NSURL.class]) value = [value absoluteString];
    return [value isKindOfClass:NSString.class] ? [value substringToIndex:MIN((NSUInteger)512, [value length])] : @"";
}
void NNPSpotifyQueueReport(id state) {
    if (!state) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        id track = NNPQueueGet(state, @"track");
        id future = NNPQueueGet(state, @"future");
        if (![future isKindOfClass:NSArray.class]) return;
        id next = [future count] ? [future firstObject] : nil;
        NSDictionary *snapshot = @{
            @"currentURI": NNPQueueString(NNPQueueGet(track, @"URI")),
            @"currentTitle": NNPQueueString(NNPQueueGet(track, @"trackTitle")),
            @"currentArtist": NNPQueueString(NNPQueueGet(track, @"artistName")),
            @"nextURI": NNPQueueString(NNPQueueGet(next, @"URI")),
            @"nextTitle": NNPQueueString(NNPQueueGet(next, @"trackTitle")),
            @"nextArtist": NNPQueueString(NNPQueueGet(next, @"artistName"))
        };
        static NSDictionary *lastSnapshot;
        if ([lastSnapshot isEqual:snapshot]) return;
        lastSnapshot = snapshot;
        NSMutableDictionary *dated = [snapshot mutableCopy];
        dated[@"timestamp"] = @(NSDate.date.timeIntervalSince1970);
        CFPreferencesSetAppValue(CFSTR("SpotifyQueueSnapshot"), (__bridge CFDictionaryRef)dated, CFSTR("com.user.notchnowplaying"));
        CFPreferencesAppSynchronize(CFSTR("com.user.notchnowplaying"));
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.user.notchnowplaying.preferences.changed"), NULL, NULL, YES);
    });
}
@interface NNPSpotifyQueueObserver : NSObject
@end
@implementation NNPSpotifyQueueObserver
- (void)player:(id)player stateDidChange:(id)state {
    (void)player;
    NNPSpotifyQueueReport(state);
}
@end
void NNPSpotifyQueueObserve(id player) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            static NNPSpotifyQueueObserver *observer;
            observer = [NNPSpotifyQueueObserver new];
            SEL selector = NSSelectorFromString(@"addPlayerObserver:");
            Method method = class_getInstanceMethod([player class], selector);
            char argument[32] = {0};
            if (!method || method_getNumberOfArguments(method) != 3) return;
            method_getArgumentType(method, 2, argument, sizeof(argument));
            if (argument[0] != '@') return;
            ((void (*)(id, SEL, id))objc_msgSend)(player, selector, observer);
            NNPSpotifyQueueReport(NNPQueueGet(player, @"state"));
        });
    });
}
