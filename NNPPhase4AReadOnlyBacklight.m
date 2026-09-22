#import "NNPPhase4AReadOnlyBacklight.h"

#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

#ifndef NNP_PHASE4A_BUILD_ID
#define NNP_PHASE4A_BUILD_ID "unknown"
#endif
#ifndef NNP_PHASE4A_TRACE_MICRO_TEST
#define NNP_PHASE4A_TRACE_MICRO_TEST 0
#endif

__attribute__((visibility("hidden"), noinline))
void NNPPhase4ANoop(void) {
}

static BOOL gNNPPhase4AAwakeLogged;
static BOOL gNNPPhase4ALockLogged;
static BOOL gNNPPhase4AObjectLogged;
static BOOL gNNPPhase4AUIStateValid;
static long long gNNPPhase4AUIState;
static NSString * const NNPPhase4ATracePath = @"/var/mobile/Library/NotchNowPlaying/phase4a-trace.log";
static CFStringRef const NNPPhase4ADiagnosticDomain = CFSTR("com.user.notchnowplaying.phase4a");

NSString *NNPPhase4ABuildIdentity(void) {
    return @NNP_PHASE4A_BUILD_ID;
}

BOOL NNPPhase4AReadBacklightState(long long *state) {
    if (!state) return NO;
    Class backlightClass = NSClassFromString(@"BLSBacklight");
    SEL sharedSelector = NSSelectorFromString(@"sharedBacklight");
    SEL stateSelector = NSSelectorFromString(@"backlightState");
    if (!backlightClass ||
        !class_respondsToSelector(object_getClass(backlightClass), sharedSelector)) {
        return NO;
    }
    id backlight = ((id (*)(id, SEL))objc_msgSend)((id)backlightClass, sharedSelector);
    if (!backlight || ![backlight isKindOfClass:backlightClass] ||
        ![backlight respondsToSelector:stateSelector]) {
        return NO;
    }
    *state = ((long long (*)(id, SEL))objc_msgSend)(backlight, stateSelector);
    return YES;
}

void NNPPhase4ASetUIState(BOOL succeeded, long long state) {
    gNNPPhase4AUIStateValid = succeeded;
    gNNPPhase4AUIState = state;
}

NSString *NNPPhase4AUIStateMarker(void) {
    if (!gNNPPhase4AUIStateValid) return @"A:ERR";
    return [NSString stringWithFormat:@"A:%lld", gNNPPhase4AUIState];
}

void NNPPhase4ASetDiagnosticValue(NSString *key, id value) {
    if (!key.length || !value) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             NNPPhase4ADiagnosticDomain);
    CFPreferencesAppSynchronize(NNPPhase4ADiagnosticDomain);
}

void NNPPhase4ASetDiagnosticBoolean(NSString *key, BOOL value) {
    NNPPhase4ASetDiagnosticValue(key, @(value));
}

void NNPPhase4ASetDiagnosticInteger(NSString *key, long long value) {
    NNPPhase4ASetDiagnosticValue(key, @(value));
}

__attribute__((used, visibility("default")))
void NNPPhase4ATrace(NSString *line) {
#if NNP_PHASE4A_TRACE_MICRO_TEST == 1
    (void)line;
    return;
#endif
    if (!line.length) return;
    int fd = open(NNPPhase4ATracePath.UTF8String, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) {
        NNPPhase4ASetDiagnosticInteger(@"TraceOpenErrno", errno);
        return;
    }
    NNPPhase4ASetDiagnosticInteger(@"TraceOpenErrno", 0);
    NSString *record = [line stringByAppendingString:@"\n"];
    NSData *data = [record dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length) write(fd, data.bytes, data.length);
    close(fd);
}

static void NNPPhase4AFileLog(NSString *line) {
    NNPPhase4ATrace(line);
}

static id NNPPhase4AExistingBacklight(void) {
    NNPPhase4ATrace(@"BLS_CLASS_LOOKUP_BEGIN");
    Class backlightClass = NSClassFromString(@"BLSBacklight");
    SEL sharedSelector = NSSelectorFromString(@"sharedBacklight");
    if (!backlightClass) {
        NNPPhase4ASetDiagnosticBoolean(@"BLSClassFound", NO);
        NNPPhase4ATrace(@"FAIL_BLS_CLASS_MISSING");
        NNPPhase4AFileLog(@"failure=BLSBacklight-class-missing");
        return nil;
    }
    NNPPhase4ASetDiagnosticBoolean(@"BLSClassFound", YES);
    NNPPhase4ATrace(@"BLS_CLASS_FOUND");
    if (!class_respondsToSelector(object_getClass(backlightClass), sharedSelector)) {
        NNPPhase4ASetDiagnosticBoolean(@"SharedSelectorFound", NO);
        NNPPhase4ATrace(@"FAIL_SHARED_SELECTOR_MISSING");
        NSLog(@"[NNP][Phase4A] failure=BLSBacklight-singleton-unavailable");
        NNPPhase4AFileLog(@"failure=BLSBacklight-singleton-unavailable");
        return nil;
    }
    NNPPhase4ASetDiagnosticBoolean(@"SharedSelectorFound", YES);
    NNPPhase4ATrace(@"BLS_SHARED_SELECTOR_FOUND");

    // This is the statically recovered framework singleton accessor. No
    // request, proxy, assertion, or manually-created connection is involved.
    NNPPhase4ATrace(@"BLS_SHARED_BACKLIGHT_CALL_BEGIN");
    id backlight = ((id (*)(id, SEL))objc_msgSend)((id)backlightClass, sharedSelector);
    if (!backlight) {
        NNPPhase4ASetDiagnosticBoolean(@"SharedBacklightFound", NO);
        NNPPhase4ATrace(@"BLS_SHARED_BACKLIGHT_FAILED");
        NNPPhase4AFileLog(@"failure=sharedBacklight-nil");
        return nil;
    }
    if (![backlight isKindOfClass:backlightClass]) {
        NNPPhase4ASetDiagnosticBoolean(@"SharedBacklightFound", NO);
        NNPPhase4ATrace(@"BLS_SHARED_BACKLIGHT_FAILED");
        NNPPhase4AFileLog(@"failure=sharedBacklight-class-mismatch");
        return nil;
    }
    NNPPhase4ASetDiagnosticBoolean(@"SharedBacklightFound", YES);
    NNPPhase4ATrace(@"BLS_SHARED_BACKLIGHT_OK");
    return backlight;
}

static void NNPLogBacklightState(NSString *reason) {
    id backlight = NNPPhase4AExistingBacklight();
    SEL stateSelector = NSSelectorFromString(@"backlightState");
    if (!backlight || ![backlight respondsToSelector:stateSelector]) {
        NNPPhase4ASetDiagnosticBoolean(@"StateSelectorFound", NO);
        NNPPhase4ATrace(@"FAIL_STATE_SELECTOR_MISSING");
        NSLog(@"[NNP][Phase4A] failure=backlightState-unavailable");
        NNPPhase4AFileLog(@"failure=backlightState-unavailable");
        return;
    }
    NNPPhase4ASetDiagnosticBoolean(@"StateSelectorFound", YES);
    NNPPhase4ATrace(@"BACKLIGHT_STATE_SELECTOR_FOUND");
    if (!gNNPPhase4AObjectLogged) {
        gNNPPhase4AObjectLogged = YES;
        NSLog(@"[NNP][Phase4A] BLSBacklight object=%p class=%@", backlight, NSStringFromClass([backlight class]));
        NNPPhase4AFileLog([NSString stringWithFormat:@"BLSBacklight class=%@", NSStringFromClass([backlight class])]);
    }
    NNPPhase4ATrace([NSString stringWithFormat:@"BACKLIGHT_STATE_READ_BEGIN reason=%@", reason]);
    long long state = ((long long (*)(id, SEL))objc_msgSend)(backlight, stateSelector);
    if ([reason isEqualToString:@"awake"]) {
        NNPPhase4ASetDiagnosticInteger(@"AwakeBacklightState", state);
    } else if ([reason isEqualToString:@"lock-transition"]) {
        NNPPhase4ASetDiagnosticInteger(@"LockBacklightState", state);
    }
    NNPPhase4ATrace([NSString stringWithFormat:@"BACKLIGHT_STATE=%lld reason=%@", state, reason]);
    NSLog(@"[NNP][Phase4A] reason=%@ state=%lld", reason, state);
    NNPPhase4AFileLog([NSString stringWithFormat:@"reason=%@ state=%lld", reason, state]);
}

static void NNPPhase4ABlankedScreenCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    NNPPhase4ASetDiagnosticBoolean(@"LockCallbackEntered", YES);
    NNPPhase4ATrace(@"LOCK_CALLBACK_ENTER");
    if (gNNPPhase4ALockLogged) return;
    gNNPPhase4ALockLogged = YES;
    NNPLogBacklightState(@"lock-transition");
    NNPPhase4ATrace(@"LOCK_SAMPLE_DONE");
}

__attribute__((used, visibility("default")))
void NNPPhase4AStartReadOnlyBacklightObservation(void) {
    NNPPhase4ASetDiagnosticBoolean(@"Phase4AStartEntered", YES);
    NNPPhase4ATrace(@"PHASE4A_START_ENTER");
    long applicationState = (long)UIApplication.sharedApplication.applicationState;
    NNPPhase4ASetDiagnosticInteger(@"UIApplicationState", applicationState);
    NNPPhase4ATrace([NSString stringWithFormat:@"UIApplicationState=%ld", applicationState]);
    if (!gNNPPhase4AAwakeLogged) {
        gNNPPhase4AAwakeLogged = YES;
        NNPPhase4ATrace(@"AWAKE_BRANCH_DIRECT");
        NNPLogBacklightState(@"awake");
        NNPPhase4ATrace(@"AWAKE_SAMPLE_DONE");
    }
    NNPPhase4ATrace(@"DARWIN_OBSERVER_REGISTER_BEGIN");
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    NNPPhase4ABlankedScreenCallback,
                                    CFSTR("com.apple.springboard.hasBlankedScreen"), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    NNPPhase4ATrace(@"DARWIN_OBSERVER_REGISTERED");
}
