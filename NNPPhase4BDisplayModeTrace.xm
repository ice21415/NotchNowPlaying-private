#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <ptrauth.h>
#import <objc/runtime.h>
#import <string.h>

static CFStringRef const NNPPhase4BDisplayModeDomain =
    CFSTR("com.user.notchnowplaying.phase4b");
static long long gNNPPhase4BDisplayModeSequence;
static BOOL gNNPPhase4BStateMachineIvarsRecorded;
static BOOL gNNPPhase4BProviderIvarsRecorded;
static BOOL gNNPPhase4BSleepMonitorIvarsRecorded;

static void NNPPhase4BDisplayModeSet(NSString *key, id value) {
    if (!key.length || !value) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             NNPPhase4BDisplayModeDomain);
    CFPreferencesAppSynchronize(NNPPhase4BDisplayModeDomain);
}

%hook BLSHBacklightDisplayStateMachine

- (void)displayState:(id)displayState didUpdateToMode:(long long)mode {
    NNPPhase4BDisplayModeSet(@"DisplayStateModeCallbackCount", @1);
    NNPPhase4BDisplayModeSet(@"DisplayStateModeCallbackMode", @(mode));
    NNPPhase4BDisplayModeSet(@"DisplayStateModeCallbackClass",
                             displayState ? NSStringFromClass(object_getClass(displayState)) : @"<nil>");
    NNPPhase4BDisplayModeSet(@"DisplayStateModeCallbackReceiverClass",
                             NSStringFromClass(object_getClass(self)));
    %orig;
}

- (void)setDisplayMode:(long long)mode withRampDuration:(double)duration {
    if (gNNPPhase4BDisplayModeSequence < 2) {
        id __unsafe_unretained downstreamBefore = nil;
        memcpy(&downstreamBefore,
               (const void *)((uintptr_t)(__bridge void *)self + 0x18),
               sizeof(downstreamBefore));
        if (downstreamBefore) {
            id __unsafe_unretained lowerBefore = nil;
            memcpy(&lowerBefore,
                   (const void *)((uintptr_t)(__bridge void *)downstreamBefore + 0x38),
                   sizeof(lowerBefore));
            NNPPhase4BDisplayModeSet(@"LowerReceiverPointerBefore",
                                     [NSString stringWithFormat:@"0x%llx",
                                      (unsigned long long)(uintptr_t)lowerBefore]);
            if (lowerBefore) {
                SEL lowerSelector = NSSelectorFromString(@"transitionToDisplayMode:withDuration:error:");
                Method lowerMethod = class_getInstanceMethod(object_getClass(lowerBefore),
                                                              lowerSelector);
                IMP lowerIMP = lowerMethod ? method_getImplementation(lowerMethod) : NULL;
                NNPPhase4BDisplayModeSet(@"LowerReceiverClassBefore",
                                         NSStringFromClass(object_getClass(lowerBefore)));
                NNPPhase4BDisplayModeSet(@"LowerSelectorFoundBefore",
                                         @(lowerMethod != NULL));
                if (lowerIMP) {
                    void *strippedLowerIMP = ptrauth_strip((void *)lowerIMP,
                                                           ptrauth_key_function_pointer);
                    NNPPhase4BDisplayModeSet(@"LowerIMPBefore",
                                             [NSString stringWithFormat:@"0x%llx",
                                              (unsigned long long)(uintptr_t)strippedLowerIMP]);
                    Dl_info lowerInfo = {0};
                    if (dladdr((const void *)lowerIMP, &lowerInfo)) {
                        NNPPhase4BDisplayModeSet(@"LowerImageBefore",
                                                 lowerInfo.dli_fname
                                                     ? [NSString stringWithUTF8String:lowerInfo.dli_fname]
                                                     : @"unknown");
                        NNPPhase4BDisplayModeSet(@"LowerImageBaseBefore",
                                                 [NSString stringWithFormat:@"0x%llx",
                                                  (unsigned long long)(uintptr_t)lowerInfo.dli_fbase]);
                    }
                }
            }
        }
    }
    %orig;

    gNNPPhase4BDisplayModeSequence++;
    if (gNNPPhase4BDisplayModeSequence == 1) {
        NNPPhase4BDisplayModeSet(@"FirstDisplayMode", @(mode));
        NNPPhase4BDisplayModeSet(@"FirstRampDuration", @(duration));
    }
    NNPPhase4BDisplayModeSet(@"DisplayModeCallCount",
                             @(gNNPPhase4BDisplayModeSequence));
    NNPPhase4BDisplayModeSet(@"LastDisplayMode", @(mode));
    NNPPhase4BDisplayModeSet(@"LastRampDuration", @(duration));
    NNPPhase4BDisplayModeSet(@"LastDisplayModeReceiverClass",
                             NSStringFromClass(object_getClass(self)));
    NNPPhase4BDisplayModeSet(@"DisplayModeSequence",
                             @(gNNPPhase4BDisplayModeSequence));

    if (gNNPPhase4BDisplayModeSequence == 1) {
        id __unsafe_unretained downstream = nil;
        memcpy(&downstream,
               (const void *)((uintptr_t)(__bridge void *)self + 0x18),
               sizeof(downstream));
        if (downstream) {
            SEL transitionSelector = NSSelectorFromString(@"transitionToDisplayMode:withDuration:");
            Method transitionMethod = class_getInstanceMethod(object_getClass(downstream),
                                                               transitionSelector);
            IMP transitionIMP = transitionMethod ? method_getImplementation(transitionMethod) : NULL;
            NNPPhase4BDisplayModeSet(@"DownstreamReceiverClass",
                                     NSStringFromClass(object_getClass(downstream)));
            NNPPhase4BDisplayModeSet(@"DownstreamSelectorFound",
                                     @(transitionMethod != NULL));
            if (transitionIMP) {
                Dl_info transitionInfo = {0};
                void *strippedTransitionIMP = ptrauth_strip((void *)transitionIMP,
                                                            ptrauth_key_function_pointer);
                NNPPhase4BDisplayModeSet(@"DownstreamIMP",
                                         [NSString stringWithFormat:@"0x%llx",
                                          (unsigned long long)(uintptr_t)strippedTransitionIMP]);
                if (dladdr((const void *)transitionIMP, &transitionInfo)) {
                    NNPPhase4BDisplayModeSet(@"DownstreamImageBase",
                                             [NSString stringWithFormat:@"0x%llx",
                                              (unsigned long long)(uintptr_t)transitionInfo.dli_fbase]);
                    if (transitionInfo.dli_fname) {
                        NNPPhase4BDisplayModeSet(@"DownstreamImage",
                                                 [NSString stringWithUTF8String:transitionInfo.dli_fname]);
                    }
                    if (transitionInfo.dli_saddr) {
                        NNPPhase4BDisplayModeSet(@"DownstreamSymbolAddress",
                                                 [NSString stringWithFormat:@"0x%llx",
                                                  (unsigned long long)(uintptr_t)transitionInfo.dli_saddr]);
                    }
                }
            }

            id __unsafe_unretained lowerReceiver = nil;
            memcpy(&lowerReceiver,
                   (const void *)((uintptr_t)(__bridge void *)downstream + 0x38),
                   sizeof(lowerReceiver));
            NNPPhase4BDisplayModeSet(@"LowerReceiverPointerAfter",
                                     [NSString stringWithFormat:@"0x%llx",
                                      (unsigned long long)(uintptr_t)lowerReceiver]);
            unsigned int ivarCount = 0;
            Ivar *ivars = class_copyIvarList(object_getClass(downstream), &ivarCount);
            for (unsigned int index = 0; ivars && index < ivarCount; index++) {
                Ivar ivar = ivars[index];
                if (ivar_getOffset(ivar) == 0x38) {
                    NNPPhase4BDisplayModeSet(@"DownstreamIvar38Name",
                                             [NSString stringWithUTF8String:ivar_getName(ivar)]);
                    NNPPhase4BDisplayModeSet(@"DownstreamIvar38Type",
                                             [NSString stringWithUTF8String:ivar_getTypeEncoding(ivar)]);
                    break;
                }
            }
            if (ivars) free(ivars);
            if (lowerReceiver) {
                SEL lowerSelector = NSSelectorFromString(@"transitionToDisplayMode:withDuration:error:");
                Method lowerMethod = class_getInstanceMethod(object_getClass(lowerReceiver),
                                                              lowerSelector);
                IMP lowerIMP = lowerMethod ? method_getImplementation(lowerMethod) : NULL;
                NNPPhase4BDisplayModeSet(@"LowerReceiverClass",
                                         NSStringFromClass(object_getClass(lowerReceiver)));
                NNPPhase4BDisplayModeSet(@"LowerSelectorFound", @(lowerMethod != NULL));
                if (lowerIMP) {
                    Dl_info lowerInfo = {0};
                    void *strippedLowerIMP = ptrauth_strip((void *)lowerIMP,
                                                           ptrauth_key_function_pointer);
                    NNPPhase4BDisplayModeSet(@"LowerIMP",
                                             [NSString stringWithFormat:@"0x%llx",
                                              (unsigned long long)(uintptr_t)strippedLowerIMP]);
                    if (dladdr((const void *)lowerIMP, &lowerInfo)) {
                        NNPPhase4BDisplayModeSet(@"LowerImageBase",
                                                 [NSString stringWithFormat:@"0x%llx",
                                                  (unsigned long long)(uintptr_t)lowerInfo.dli_fbase]);
                        if (lowerInfo.dli_fname) {
                            NNPPhase4BDisplayModeSet(@"LowerImage",
                                                     [NSString stringWithUTF8String:lowerInfo.dli_fname]);
                        }
                        if (lowerInfo.dli_saddr) {
                            NNPPhase4BDisplayModeSet(@"LowerSymbolAddress",
                                                     [NSString stringWithFormat:@"0x%llx",
                                                      (unsigned long long)(uintptr_t)lowerInfo.dli_saddr]);
                        }
                    }
                }
            }
        }
    }
}

%end

%hook BLSHBacklightOSInterfaceProvider

- (void)transitionToDisplayMode:(long long)mode withDuration:(double)duration {
    if (!gNNPPhase4BProviderIvarsRecorded) {
        gNNPPhase4BProviderIvarsRecorded = YES;
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(object_getClass(self), &count);
        NSMutableArray *objects = [NSMutableArray array];
        for (unsigned int index = 0; ivars && index < count; index++) {
            Ivar ivar = ivars[index];
            const char *encoding = ivar_getTypeEncoding(ivar);
            if (!encoding || encoding[0] != '@') continue;
            id __unsafe_unretained value = nil;
            memcpy(&value,
                   (const void *)((uintptr_t)(__bridge void *)self + ivar_getOffset(ivar)),
                   sizeof(value));
            NSString *name = [NSString stringWithUTF8String:ivar_getName(ivar)];
            NSString *className = value ? NSStringFromClass(object_getClass(value)) : @"<nil>";
            [objects addObject:[NSString stringWithFormat:@"%@=%@", name, className]];
        }
        if (ivars) free(ivars);
        NNPPhase4BDisplayModeSet(@"ProviderObjectIvars",
                                 [objects componentsJoinedByString:@"|"]);
    }
    NNPPhase4BDisplayModeSet(@"ProviderTransitionCallCount", @1);
    NNPPhase4BDisplayModeSet(@"ProviderTransitionMode", @(mode));
    NNPPhase4BDisplayModeSet(@"ProviderTransitionDuration", @(duration));
    id __unsafe_unretained field08 = nil;
    memcpy(&field08,
           (const void *)((uintptr_t)(__bridge void *)self + 0x08),
           sizeof(field08));
    if (field08) {
        NNPPhase4BDisplayModeSet(@"ProviderField08Class",
                                 NSStringFromClass(object_getClass(field08)));
        NNPPhase4BDisplayModeSet(@"ProviderField08Pointer",
                                 [NSString stringWithFormat:@"0x%llx",
                                  (unsigned long long)(uintptr_t)field08]);
        SEL curveSelector = NSSelectorFromString(@"useAlwaysOnBrightnessCurve:withRampDuration:");
        Method curveMethod = class_getInstanceMethod(object_getClass(field08), curveSelector);
        NNPPhase4BDisplayModeSet(@"ProviderField08CurveSelectorFound",
                                 @(curveMethod != NULL));
        if (curveMethod) {
            IMP curveIMP = method_getImplementation(curveMethod);
            Dl_info curveInfo = {0};
            if (curveIMP && dladdr((const void *)curveIMP, &curveInfo)) {
                void *strippedCurveIMP = ptrauth_strip((void *)curveIMP,
                                                       ptrauth_key_function_pointer);
                NNPPhase4BDisplayModeSet(@"ProviderField08CurveIMP",
                                         [NSString stringWithFormat:@"0x%llx",
                                          (unsigned long long)(uintptr_t)strippedCurveIMP]);
                if (curveInfo.dli_fname) {
                    NNPPhase4BDisplayModeSet(@"ProviderField08CurveImage",
                                             [NSString stringWithUTF8String:curveInfo.dli_fname]);
                }
                NNPPhase4BDisplayModeSet(@"ProviderField08CurveImageBase",
                                         [NSString stringWithFormat:@"0x%llx",
                                          (unsigned long long)(uintptr_t)curveInfo.dli_fbase]);
            }
        }
    } else {
        NNPPhase4BDisplayModeSet(@"ProviderField08Class", @"<nil>");
    }
    %orig;
}

%end

%hook SBBacklightPlatformProvider

- (void)showBlankingWindow:(BOOL)visible withFadeDuration:(double)duration {
    NNPPhase4BDisplayModeSet(@"BlankingWindowShowCallCount", @1);
    NNPPhase4BDisplayModeSet(@"BlankingWindowShowVisible", @(visible));
    NNPPhase4BDisplayModeSet(@"BlankingWindowShowDuration", @(duration));
    %orig;
}

- (void)_setBlankingWindowVisible:(BOOL)visible fadeDuration:(double)duration {
    NNPPhase4BDisplayModeSet(@"BlankingWindowSetCallCount", @1);
    NNPPhase4BDisplayModeSet(@"BlankingWindowSetVisible", @(visible));
    NNPPhase4BDisplayModeSet(@"BlankingWindowSetDuration", @(duration));
    %orig;
}

- (void)useAlwaysOnBrightnessCurve:(BOOL)enabled withRampDuration:(double)duration {
    NNPPhase4BDisplayModeSet(@"AlwaysOnCurveCallCount", @1);
    NNPPhase4BDisplayModeSet(@"AlwaysOnCurveEnabled", @(enabled));
    NNPPhase4BDisplayModeSet(@"AlwaysOnCurveDuration", @(duration));
    NNPPhase4BDisplayModeSet(@"AlwaysOnCurveReceiverClass",
                             NSStringFromClass(object_getClass(self)));
    %orig;
}

%end

%hook SBBacklightController

- (void)_performBacklightChangeRequest:(id)request completion:(id)completion {
    NNPPhase4BDisplayModeSet(@"ControllerRequestCallCount", @1);
    NNPPhase4BDisplayModeSet(@"ControllerRequestClass",
                             request ? NSStringFromClass(object_getClass(request)) : @"<nil>");
    %orig;
}

%end

%hook BLSBacklight

- (id)performChangeRequest:(id)request {
    NNPPhase4BDisplayModeSet(@"BLSPerformRequestCallCount", @1);
    NNPPhase4BDisplayModeSet(@"BLSPerformRequestClass",
                             request ? NSStringFromClass(object_getClass(request)) : @"<nil>");
    id __unsafe_unretained proxy = nil;
    memcpy(&proxy,
           (const void *)((uintptr_t)(__bridge void *)self + 0x08),
           sizeof(proxy));
    NNPPhase4BDisplayModeSet(@"BLSProxyClass",
                             proxy ? NSStringFromClass(object_getClass(proxy)) : @"<nil>");
    return %orig;
}

%end

%hook BLSXPCBacklightProxy

- (id)performChangeRequest:(id)request {
    NNPPhase4BDisplayModeSet(@"BLSXPCProxyCallCount", @1);
    NNPPhase4BDisplayModeSet(@"BLSXPCProxyRequestClass",
                             request ? NSStringFromClass(object_getClass(request)) : @"<nil>");
    return %orig;
}

%end

%hook BLSHBacklightStateMachine

- (id)performChangeRequest:(id)request {
    NNPPhase4BDisplayModeSet(@"ProviderStateMachineRequestCallCount", @1);
    NNPPhase4BDisplayModeSet(@"ProviderStateMachineRequestClass",
                             request ? NSStringFromClass(object_getClass(request)) : @"<nil>");
    if (!gNNPPhase4BStateMachineIvarsRecorded) {
        gNNPPhase4BStateMachineIvarsRecorded = YES;
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(object_getClass(self), &count);
        NSMutableArray *objects = [NSMutableArray array];
        for (unsigned int index = 0; ivars && index < count; index++) {
            Ivar ivar = ivars[index];
            const char *encoding = ivar_getTypeEncoding(ivar);
            if (!encoding || encoding[0] != '@') continue;
            id __unsafe_unretained value = nil;
            memcpy(&value,
                   (const void *)((uintptr_t)(__bridge void *)self + ivar_getOffset(ivar)),
                   sizeof(value));
            if (value) {
                NSString *name = [NSString stringWithUTF8String:ivar_getName(ivar)];
                NSString *className = NSStringFromClass(object_getClass(value));
                [objects addObject:[NSString stringWithFormat:@"%@=%@", name, className]];
            }
        }
        if (ivars) free(ivars);
        NNPPhase4BDisplayModeSet(@"StateMachineObjectIvars",
                                 [objects componentsJoinedByString:@"|"]);
    }
    return %orig;
}

%end

%hook BLSHOnSystemSleepAction

- (void)systemSleepMonitor:(id)monitor sleepRequestedWithResult:(id)completion {
    if (!gNNPPhase4BSleepMonitorIvarsRecorded && monitor) {
        gNNPPhase4BSleepMonitorIvarsRecorded = YES;
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(object_getClass(monitor), &count);
        NSMutableArray *objects = [NSMutableArray array];
        for (unsigned int index = 0; ivars && index < count; index++) {
            Ivar ivar = ivars[index];
            const char *encoding = ivar_getTypeEncoding(ivar);
            if (!encoding || encoding[0] != '@') continue;
            id __unsafe_unretained value = nil;
            memcpy(&value,
                   (const void *)((uintptr_t)(__bridge void *)monitor + ivar_getOffset(ivar)),
                   sizeof(value));
            NSString *name = [NSString stringWithUTF8String:ivar_getName(ivar)];
            NSString *className = value ? NSStringFromClass(object_getClass(value)) : @"<nil>";
            [objects addObject:[NSString stringWithFormat:@"%@=%@", name, className]];
        }
        if (ivars) free(ivars);
        NNPPhase4BDisplayModeSet(@"SystemSleepMonitorObjectIvars",
                                 [objects componentsJoinedByString:@"|"]);
        NNPPhase4BDisplayModeSet(@"SystemSleepMonitorRuntimeClass",
                                 NSStringFromClass(object_getClass(monitor)));
    }
    %orig;
}

- (void)systemSleepMonitor:(id)monitor prepareForSleepWithCompletion:(id)completion {
    if (!gNNPPhase4BSleepMonitorIvarsRecorded && monitor) {
        gNNPPhase4BSleepMonitorIvarsRecorded = YES;
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(object_getClass(monitor), &count);
        NSMutableArray *objects = [NSMutableArray array];
        for (unsigned int index = 0; ivars && index < count; index++) {
            Ivar ivar = ivars[index];
            const char *encoding = ivar_getTypeEncoding(ivar);
            if (!encoding || encoding[0] != '@') continue;
            id __unsafe_unretained value = nil;
            memcpy(&value,
                   (const void *)((uintptr_t)(__bridge void *)monitor + ivar_getOffset(ivar)),
                   sizeof(value));
            NSString *name = [NSString stringWithUTF8String:ivar_getName(ivar)];
            NSString *className = value ? NSStringFromClass(object_getClass(value)) : @"<nil>";
            [objects addObject:[NSString stringWithFormat:@"%@=%@", name, className]];
        }
        if (ivars) free(ivars);
        NNPPhase4BDisplayModeSet(@"SystemSleepMonitorObjectIvars",
                                 [objects componentsJoinedByString:@"|"]);
        NNPPhase4BDisplayModeSet(@"SystemSleepMonitorRuntimeClass",
                                 NSStringFromClass(object_getClass(monitor)));
    }
    %orig;
}

%end

%hook SWSystemSleepMonitor

- (id)initWithIdentifier:(id)identifier
                    queue:(id)queue
     allowsInvalidation:(BOOL)allowsInvalidation
         monitorProvider:(id)monitorProvider
   sleepAssertionProvider:(id)sleepAssertionProvider {
    NNPPhase4BDisplayModeSet(@"SleepMonitorInitMonitorProviderClass",
                             monitorProvider
                                 ? NSStringFromClass(object_getClass(monitorProvider))
                                 : @"<nil>");
    NNPPhase4BDisplayModeSet(@"SleepMonitorInitSleepAssertionProviderClass",
                             sleepAssertionProvider
                                 ? NSStringFromClass(object_getClass(sleepAssertionProvider))
                                 : @"<nil>");
    NNPPhase4BDisplayModeSet(@"SleepMonitorInitQueueClass",
                             queue ? NSStringFromClass(object_getClass(queue)) : @"<nil>");
    id result = %orig;
    NNPPhase4BDisplayModeSet(@"SleepMonitorInitResultClass",
                             result ? NSStringFromClass(object_getClass(result)) : @"<nil>");
    return result;
}

%end

static void NNPPhase4BRecordSystemWakeClassMetadata(Class cls, NSString *prefix) {
    if (!cls || !prefix) return;

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    NSMutableArray *methodNames = [NSMutableArray array];
    for (unsigned int index = 0; methods && index < methodCount; index++) {
        SEL selector = method_getName(methods[index]);
        const char *name = sel_getName(selector);
        if (!name) continue;
        NSString *selectorName = [NSString stringWithUTF8String:name];
        NSString *lower = selectorName.lowercaseString;
        if (![lower containsString:@"sleep"] && ![lower containsString:@"power"] &&
            ![lower containsString:@"display"] && ![lower containsString:@"blank"] &&
            ![lower containsString:@"request"] && ![lower containsString:@"notify"] &&
            ![lower containsString:@"monitor"]) continue;
        const char *types = method_getTypeEncoding(methods[index]);
        [methodNames addObject:[NSString stringWithFormat:@"%@[%@]", selectorName,
                                types ? [NSString stringWithUTF8String:types] : @"?"]];
    }
    if (methods) free(methods);

    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList(cls, &ivarCount);
    NSMutableArray *ivarNames = [NSMutableArray array];
    for (unsigned int index = 0; ivars && index < ivarCount; index++) {
        const char *name = ivar_getName(ivars[index]);
        const char *types = ivar_getTypeEncoding(ivars[index]);
        if (name) {
            [ivarNames addObject:[NSString stringWithFormat:@"%s[%s]", name,
                                  types ? types : "?"]];
        }
    }
    if (ivars) free(ivars);

    NNPPhase4BDisplayModeSet([prefix stringByAppendingString:@"Class"], NSStringFromClass(cls));
    NNPPhase4BDisplayModeSet([prefix stringByAppendingString:@"Methods"],
                             [methodNames componentsJoinedByString:@"|"]);
    NNPPhase4BDisplayModeSet([prefix stringByAppendingString:@"Ivars"],
                             [ivarNames componentsJoinedByString:@"|"]);
}

%hook BSServiceConnection

- (id)performChangeRequest:(id)request {
    NNPPhase4BDisplayModeSet(@"BSServiceConnectionCallCount", @1);
    NNPPhase4BDisplayModeSet(@"BSServiceConnectionRequestClass",
                             request ? NSStringFromClass(object_getClass(request)) : @"<nil>");
    return %orig;
}

%end

%hook CBDisplayStateClient

- (BOOL)transitionToDisplayMode:(long long)mode
               withDuration:(double)duration
                       error:(NSError **)error {
    NNPPhase4BDisplayModeSet(@"DisplayClientCallCount", @1);
    NNPPhase4BDisplayModeSet(@"DisplayClientLastMode", @(mode));
    NNPPhase4BDisplayModeSet(@"DisplayClientLastDuration", @(duration));
    NNPPhase4BDisplayModeSet(@"DisplayClientReceiverClass",
                             NSStringFromClass(object_getClass(self)));
    return %orig;
}

%end

%ctor {
    NNPPhase4BDisplayModeSet(@"DisplayModeHookBuildIdentity",
                             @"phase4b-display-mode");
    Class displayClientClass = NSClassFromString(@"CBDisplayStateClient");
    SEL displayClientSelector = NSSelectorFromString(@"transitionToDisplayMode:withDuration:error:");
    Method displayClientMethod = displayClientClass
        ? class_getInstanceMethod(displayClientClass, displayClientSelector) : NULL;
    NNPPhase4BDisplayModeSet(@"DisplayClientClassFound", @(displayClientClass != Nil));
    NNPPhase4BDisplayModeSet(@"DisplayClientSelectorFound", @(displayClientMethod != NULL));
    if (displayClientClass) {
        NNPPhase4BDisplayModeSet(@"DisplayClientClass", NSStringFromClass(displayClientClass));
    }
    if (displayClientMethod) {
        IMP displayClientIMP = method_getImplementation(displayClientMethod);
        Dl_info displayClientInfo = {0};
        if (displayClientIMP && dladdr((const void *)displayClientIMP, &displayClientInfo)) {
            void *strippedDisplayClientIMP = ptrauth_strip((void *)displayClientIMP,
                                                            ptrauth_key_function_pointer);
            NNPPhase4BDisplayModeSet(@"DisplayClientIMP",
                                     [NSString stringWithFormat:@"0x%llx",
                                      (unsigned long long)(uintptr_t)strippedDisplayClientIMP]);
            NNPPhase4BDisplayModeSet(@"DisplayClientImageBase",
                                     [NSString stringWithFormat:@"0x%llx",
                                      (unsigned long long)(uintptr_t)displayClientInfo.dli_fbase]);
            if (displayClientInfo.dli_fname) {
                NNPPhase4BDisplayModeSet(@"DisplayClientImage",
                                         [NSString stringWithUTF8String:displayClientInfo.dli_fname]);
            }
            if (displayClientInfo.dli_saddr) {
                NNPPhase4BDisplayModeSet(@"DisplayClientSymbolAddress",
                                         [NSString stringWithFormat:@"0x%llx",
                                          (unsigned long long)(uintptr_t)displayClientInfo.dli_saddr]);
            }
        }
    }
    if (displayClientClass) {
        unsigned int platformCount = 0;
        Method *platformMethods = class_copyMethodList(NSClassFromString(@"SBBacklightPlatformProvider"),
                                                        &platformCount);
        NSMutableArray *platformNames = [NSMutableArray array];
        for (unsigned int index = 0; platformMethods && index < platformCount; index++) {
            const char *name = sel_getName(method_getName(platformMethods[index]));
            if (!name) continue;
            NSString *selectorName = [NSString stringWithUTF8String:name];
            NSString *lower = selectorName.lowercaseString;
            if ([lower containsString:@"backlight"] || [lower containsString:@"display"] ||
                [lower containsString:@"brightness"] || [lower containsString:@"curve"] ||
                [lower containsString:@"blank"] || [lower containsString:@"screen"] ||
                [lower containsString:@"power"] || [lower containsString:@"sleep"]) {
                [platformNames addObject:selectorName];
            }
        }
        if (platformMethods) free(platformMethods);
        NNPPhase4BDisplayModeSet(@"PlatformProviderMethods",
                                 [platformNames componentsJoinedByString:@"|"]);
    }
    Class sleepActionClass = NSClassFromString(@"BLSHOnSystemSleepAction");
    if (sleepActionClass) {
        unsigned int sleepCount = 0;
        Method *sleepMethods = class_copyMethodList(sleepActionClass, &sleepCount);
        NSMutableArray *sleepNames = [NSMutableArray array];
        for (unsigned int index = 0; sleepMethods && index < sleepCount; index++) {
            const char *name = sel_getName(method_getName(sleepMethods[index]));
            if (!name) continue;
            NSString *selectorName = [NSString stringWithUTF8String:name];
            NSString *lower = selectorName.lowercaseString;
            if ([lower containsString:@"sleep"] || [lower containsString:@"display"] ||
                [lower containsString:@"blank"] || [lower containsString:@"perform"] ||
                [lower containsString:@"execute"] || [lower containsString:@"action"]) {
                const char *types = method_getTypeEncoding(sleepMethods[index]);
                [sleepNames addObject:[NSString stringWithFormat:@"%@[%@]",
                                       selectorName,
                                       types ? [NSString stringWithUTF8String:types] : @"?"]];
            }
        }
        if (sleepMethods) free(sleepMethods);
        NNPPhase4BDisplayModeSet(@"SleepActionClassFound", @YES);
        NNPPhase4BDisplayModeSet(@"SleepActionMethods",
                                 [sleepNames componentsJoinedByString:@"|"]);
        SEL requestedSelector = NSSelectorFromString(@"systemSleepMonitor:sleepRequestedWithResult:");
        SEL prepareSelector = NSSelectorFromString(@"systemSleepMonitor:prepareForSleepWithCompletion:");
        Method requestedMethod = class_getInstanceMethod(sleepActionClass, requestedSelector);
        Method prepareMethod = class_getInstanceMethod(sleepActionClass, prepareSelector);
        Method methodsToInspect[2] = { requestedMethod, prepareMethod };
        for (NSUInteger index = 0; index < 2; index++) {
            Method method = methodsToInspect[index];
            if (!method) continue;
            IMP imp = method_getImplementation(method);
            Dl_info info = {0};
            if (!imp || !dladdr((const void *)imp, &info)) continue;
            void *strippedIMP = ptrauth_strip((void *)imp, ptrauth_key_function_pointer);
            NSString *address = [NSString stringWithFormat:@"0x%llx",
                                 (unsigned long long)(uintptr_t)strippedIMP];
            NSString *image = info.dli_fname
                ? [NSString stringWithUTF8String:info.dli_fname] : @"unknown";
            if (index == 0) {
                NNPPhase4BDisplayModeSet(@"SleepRequestedOriginalIMP", address);
                NNPPhase4BDisplayModeSet(@"SleepRequestedOriginalImage", image);
            } else {
                NNPPhase4BDisplayModeSet(@"PrepareForSleepOriginalIMP", address);
                NNPPhase4BDisplayModeSet(@"PrepareForSleepOriginalImage", image);
            }
        }
    } else {
        NNPPhase4BDisplayModeSet(@"SleepActionClassFound", @NO);
    }
    Class systemSleepMonitorClass = NSClassFromString(@"SWSystemSleepMonitor");
    if (systemSleepMonitorClass) {
        unsigned int monitorCount = 0;
        Method *monitorMethods = class_copyMethodList(systemSleepMonitorClass, &monitorCount);
        NSMutableArray *monitorNames = [NSMutableArray array];
        NSMutableArray *monitorIMPs = [NSMutableArray array];
        NSString *monitorImage = nil;
        NSString *monitorImageBase = nil;
        for (unsigned int index = 0; monitorMethods && index < monitorCount; index++) {
            SEL selector = method_getName(monitorMethods[index]);
            const char *name = sel_getName(selector);
            if (!name) continue;
            NSString *selectorName = [NSString stringWithUTF8String:name];
            NSString *lower = selectorName.lowercaseString;
            if (![lower containsString:@"sleep"] && ![lower containsString:@"prepare"] &&
                ![lower containsString:@"request"] && ![lower containsString:@"display"] &&
                ![lower containsString:@"power"] && ![lower containsString:@"blank"]) continue;
            const char *types = method_getTypeEncoding(monitorMethods[index]);
            [monitorNames addObject:[NSString stringWithFormat:@"%@[%@]", selectorName,
                                     types ? [NSString stringWithUTF8String:types] : @"?"]];
            IMP methodIMP = method_getImplementation(monitorMethods[index]);
            Dl_info methodInfo = {0};
            if (methodIMP && dladdr((const void *)methodIMP, &methodInfo)) {
                void *strippedIMP = ptrauth_strip((void *)methodIMP, ptrauth_key_function_pointer);
                NSString *impText = [NSString stringWithFormat:@"%@=0x%llx",
                                     selectorName,
                                     (unsigned long long)(uintptr_t)strippedIMP];
                [monitorIMPs addObject:impText];
            }
            if (!monitorImage) {
                IMP imp = method_getImplementation(monitorMethods[index]);
                Dl_info info = {0};
                if (imp && dladdr((const void *)imp, &info) && info.dli_fname) {
                    monitorImage = [NSString stringWithUTF8String:info.dli_fname];
                    monitorImageBase = [NSString stringWithFormat:@"0x%llx",
                                        (unsigned long long)(uintptr_t)info.dli_fbase];
                }
            }
        }
        if (monitorMethods) free(monitorMethods);
        NNPPhase4BDisplayModeSet(@"SystemSleepMonitorClassFound", @YES);
        NNPPhase4BDisplayModeSet(@"SystemSleepMonitorMethods",
                                 [monitorNames componentsJoinedByString:@"|"]);
        NNPPhase4BDisplayModeSet(@"SystemSleepMonitorMethodIMPs",
                                 [monitorIMPs componentsJoinedByString:@"|"]);
        if (monitorImage) NNPPhase4BDisplayModeSet(@"SystemSleepMonitorImage", monitorImage);
        if (monitorImageBase) NNPPhase4BDisplayModeSet(@"SystemSleepMonitorImageBase", monitorImageBase);
    } else {
        NNPPhase4BDisplayModeSet(@"SystemSleepMonitorClassFound", @NO);
    }
    NNPPhase4BRecordSystemWakeClassMetadata(NSClassFromString(@"SWSystemSleepMonitorProvider"),
                                             @"SleepMonitorProvider");
    NNPPhase4BRecordSystemWakeClassMetadata(NSClassFromString(@"SWSystemSleepAssertionProvider"),
                                             @"SleepAssertionProvider");
    Class displayStateClass = NSClassFromString(@"BLSHBacklightDisplayStateMachine");
    SEL displayModeSelector = NSSelectorFromString(@"setDisplayMode:withRampDuration:");
    NNPPhase4BDisplayModeSet(@"DisplayModeClassFound", @(displayStateClass != Nil));
    NNPPhase4BDisplayModeSet(@"DisplayModeSelectorFound",
                             @(displayStateClass &&
                               class_getInstanceMethod(displayStateClass,
                                                       displayModeSelector) != NULL));
    Method displayModeMethod = displayStateClass
        ? class_getInstanceMethod(displayStateClass, displayModeSelector) : NULL;
    IMP displayModeIMP = displayModeMethod ? method_getImplementation(displayModeMethod) : NULL;
    Dl_info displayModeInfo = {0};
    if (displayModeIMP && dladdr((const void *)displayModeIMP, &displayModeInfo)) {
        NNPPhase4BDisplayModeSet(@"DisplayModeIMP",
                                 [NSString stringWithFormat:@"0x%llx",
                                  (unsigned long long)(uintptr_t)displayModeIMP]);
        void *strippedIMP = ptrauth_strip((void *)displayModeIMP,
                                          ptrauth_key_function_pointer);
        NNPPhase4BDisplayModeSet(@"DisplayModeStrippedIMP",
                                 [NSString stringWithFormat:@"0x%llx",
                                  (unsigned long long)(uintptr_t)strippedIMP]);
        NNPPhase4BDisplayModeSet(@"DisplayModeImageBase",
                                 [NSString stringWithFormat:@"0x%llx",
                                  (unsigned long long)(uintptr_t)displayModeInfo.dli_fbase]);
        if (displayModeInfo.dli_saddr) {
            NNPPhase4BDisplayModeSet(@"DisplayModeSymbolAddress",
                                     [NSString stringWithFormat:@"0x%llx",
                                      (unsigned long long)(uintptr_t)displayModeInfo.dli_saddr]);
        }
        if (displayModeInfo.dli_fname) {
            NNPPhase4BDisplayModeSet(@"DisplayModeImage",
                                     [NSString stringWithUTF8String:displayModeInfo.dli_fname]);
        }
    }
    NNPPhase4BDisplayModeSet(@"DisplayModeCallCount", @0);
    NNPPhase4BDisplayModeSet(@"DisplayModeSequence", @0);
}
