#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <ptrauth.h>
#import <objc/runtime.h>
#import <string.h>

static CFStringRef const NNPPhase4BDisplayModeDomain =
    CFSTR("com.user.notchnowplaying.phase4b");
static long long gNNPPhase4BDisplayModeSequence;

static void NNPPhase4BDisplayModeSet(NSString *key, id value) {
    if (!key.length || !value) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             NNPPhase4BDisplayModeDomain);
    CFPreferencesAppSynchronize(NNPPhase4BDisplayModeDomain);
}

%hook BLSHBacklightDisplayStateMachine

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
