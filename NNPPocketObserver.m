#import "NNPPocketObserver.h"
#import "NNPDiagnostics.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSString * const NNPPocketChanged = @"com.user.notchnowplaying.native-pocket.changed";
static void (*NNPOriginalPocketUpdate)(id, SEL, int);
static BOOL NNPHasPocketState;
static NSInteger NNPLastPocketState;

static void NNPPocketUpdate(id object, SEL selector, int state) {
    NNPOriginalPocketUpdate(object, selector, state);
    long long external = ((long long (*)(id, SEL, int))objc_msgSend)(object,
        NSSelectorFromString(@"translateInternalState:"), state);
    if (external < 0 || external > 3) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (NNPHasPocketState && NNPLastPocketState == external) return;
        NNPHasPocketState = YES;
        NNPLastPocketState = (NSInteger)external;
        [NSNotificationCenter.defaultCenter postNotificationName:NNPPocketChanged object:nil];
    });
}
static BOOL NNPInstallPocketHook(void) {
    static BOOL installed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/Frameworks/CoreMotion.framework/CoreMotion", RTLD_LAZY | RTLD_LOCAL);
        Class cls = NSClassFromString(@"CMPocketStateManager");
        SEL selector = NSSelectorFromString(@"onPocketStateUpdated:");
        Method update = class_getInstanceMethod(cls, selector);
        Method translate = class_getInstanceMethod(cls, NSSelectorFromString(@"translateInternalState:"));
        char result[16] = {0}, argument[16] = {0}, translated[16] = {0}, input[16] = {0};
        if (!update || !translate || method_getNumberOfArguments(update) != 3 ||
            method_getNumberOfArguments(translate) != 3) return;
        method_getReturnType(update, result, sizeof(result));
        method_getArgumentType(update, 2, argument, sizeof(argument));
        method_getReturnType(translate, translated, sizeof(translated));
        method_getArgumentType(translate, 2, input, sizeof(input));
        if (result[0] != 'v' || argument[0] != 'i' || translated[0] != 'q' || input[0] != 'i') return;
        NNPOriginalPocketUpdate = (void (*)(id, SEL, int))method_getImplementation(update);
        if (!class_addMethod(cls, selector, (IMP)NNPPocketUpdate, method_getTypeEncoding(update)))
            method_setImplementation(update, (IMP)NNPPocketUpdate);
        installed = YES;
    });
    return installed;
}
@implementation NNPPocketObserver {
    id _observer;
    BOOL _active;
    BOOL _inPocket;
}
- (BOOL)inPocket { return _inPocket; }
- (void)refresh {
    if (!_active) return;
    BOOL pocket = NNPHasPocketState && NNPLastPocketState == 1;
    NNPDiagnosticSetBool(@"PocketStateObserved", NNPHasPocketState);
    NNPDiagnosticSetInteger(@"PocketNativeState", NNPHasPocketState ? NNPLastPocketState : -1);
    if (_inPocket == pocket) return;
    _inPocket = pocket;
    if (self.stateChanged) self.stateChanged(pocket);
}
- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active;
    NNPDiagnosticSetBool(@"PocketObserverActive", active);
    if (!active) {
        if (_observer) [NSNotificationCenter.defaultCenter removeObserver:_observer];
        _observer = nil;
        _inPocket = NO;
        return;
    }
    NNPDiagnosticSetBool(@"PocketNativeHookInstalled", NNPInstallPocketHook());
    __weak typeof(self) weakSelf = self;
    _observer = [NSNotificationCenter.defaultCenter addObserverForName:NNPPocketChanged object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { [weakSelf refresh]; }];
    [self refresh];
}
- (void)dealloc {
    if (_observer) [NSNotificationCenter.defaultCenter removeObserver:_observer];
}
@end
