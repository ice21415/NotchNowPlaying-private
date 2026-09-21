#import "NNPPhase4AReadOnlyBacklight.h"

#if NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG

#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdio.h>

static BOOL gNNPPhase4AAwakeLogged;
static BOOL gNNPPhase4ALockLogged;
static BOOL gNNPPhase4AObjectLogged;
static id gNNPPhase4AAwakeObserver;

static void NNPPhase4AFileLog(NSString *line) {
    if (!line.length) return;
    FILE *file = fopen("/var/tmp/notchnowplaying-phase4a.log", "a");
    if (!file) return;
    fprintf(file, "%s\n", line.UTF8String ?: "");
    fflush(file);
    fclose(file);
}

static id NNPPhase4AExistingBacklight(void) {
    Class backlightClass = NSClassFromString(@"BLSBacklight");
    SEL sharedSelector = NSSelectorFromString(@"sharedBacklight");
    if (!backlightClass || !class_respondsToSelector(object_getClass(backlightClass), sharedSelector)) {
        NSLog(@"[NNP][Phase4A] failure=BLSBacklight-singleton-unavailable");
        NNPPhase4AFileLog(@"failure=BLSBacklight-singleton-unavailable");
        return nil;
    }

    // This is the statically recovered framework singleton accessor. No
    // request, proxy, assertion, or manually-created connection is involved.
    id backlight = ((id (*)(id, SEL))objc_msgSend)((id)backlightClass, sharedSelector);
    if (!backlight || ![backlight isKindOfClass:backlightClass]) {
        NSLog(@"[NNP][Phase4A] failure=unexpected-BLSBacklight-class");
        NNPPhase4AFileLog(@"failure=unexpected-BLSBacklight-class");
        return nil;
    }
    return backlight;
}

static void NNPLogBacklightState(NSString *reason) {
    id backlight = NNPPhase4AExistingBacklight();
    SEL stateSelector = NSSelectorFromString(@"backlightState");
    if (!backlight || ![backlight respondsToSelector:stateSelector]) {
        NSLog(@"[NNP][Phase4A] failure=backlightState-unavailable");
        NNPPhase4AFileLog(@"failure=backlightState-unavailable");
        return;
    }
    if (!gNNPPhase4AObjectLogged) {
        gNNPPhase4AObjectLogged = YES;
        NSLog(@"[NNP][Phase4A] BLSBacklight object=%p class=%@", backlight, NSStringFromClass([backlight class]));
        NNPPhase4AFileLog([NSString stringWithFormat:@"BLSBacklight class=%@", NSStringFromClass([backlight class])]);
    }
    long long state = ((long long (*)(id, SEL))objc_msgSend)(backlight, stateSelector);
    NSLog(@"[NNP][Phase4A] reason=%@ state=%lld", reason, state);
    NNPPhase4AFileLog([NSString stringWithFormat:@"reason=%@ state=%lld", reason, state]);
}

static void NNPPhase4ABlankedScreenCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    if (gNNPPhase4ALockLogged) return;
    gNNPPhase4ALockLogged = YES;
    NNPLogBacklightState(@"lock-transition");
}

void NNPPhase4AStartReadOnlyBacklightObservation(void) {
    // Called from the existing post-startup path. This code adds no timer,
    // polling loop, delayed dispatch, display operation, or lock query.
    if (!gNNPPhase4AAwakeLogged && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
        gNNPPhase4AAwakeLogged = YES;
        NNPLogBacklightState(@"awake");
    } else if (!gNNPPhase4AAwakeLogged) {
        gNNPPhase4AAwakeObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
            usingBlock:^(__unused NSNotification *notification) {
                if (gNNPPhase4AAwakeLogged) return;
                gNNPPhase4AAwakeLogged = YES;
                NNPLogBacklightState(@"awake");
                [[NSNotificationCenter defaultCenter] removeObserver:gNNPPhase4AAwakeObserver];
                gNNPPhase4AAwakeObserver = nil;
            }];
    }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    NNPPhase4ABlankedScreenCallback,
                                    CFSTR("com.apple.springboard.hasBlankedScreen"), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

#else

void NNPPhase4AStartReadOnlyBacklightObservation(void) {}

#endif
