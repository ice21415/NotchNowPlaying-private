#import "NNPLockStateController.h"
#import "NNPDiagnostics.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>

static NSString * const NNPLockStateEvent = @"com.user.notchnowplaying.native-lock.changed";
static void (*NNPOriginalLockNotification)(id, SEL);
static void NNPSendLockNotification(id object, SEL selector) {
    NNPOriginalLockNotification(object, selector);
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:NNPLockStateEvent object:nil];
    });
}
static BOOL NNPInstallLockNotificationHook(void) {
    static BOOL installed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = NSClassFromString(@"SBLockScreenManager");
        SEL selector = NSSelectorFromString(@"_sendUILockStateChangedNotification");
        Method method = class_getInstanceMethod(cls, selector);
        char type[32] = {0};
        if (!method || method_getNumberOfArguments(method) != 2) return;
        method_getReturnType(method, type, sizeof(type));
        if (type[0] != 'v') return;
        IMP original = method_getImplementation(method);
        NNPOriginalLockNotification = (void (*)(id, SEL))original;
        if (!class_addMethod(cls, selector, (IMP)NNPSendLockNotification, method_getTypeEncoding(method)))
            original = method_setImplementation(method, (IMP)NNPSendLockNotification);
        NNPOriginalLockNotification = (void (*)(id, SEL))original;
        installed = NNPOriginalLockNotification != NULL;
    });
    return installed;
}
static BOOL NNPReadLockState(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    SEL shared = @selector(sharedInstance), selector = @selector(isUILocked);
    if (!cls || ![cls respondsToSelector:shared]) return NO;
    id manager = ((id (*)(id, SEL))objc_msgSend)((id)cls, shared);
    if (!manager || ![manager respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(manager, selector);
}
@interface NNPLockStateController ()
@property(nonatomic) BOOL locked;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) id nativeObserver;
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL eventPending;
@property(nonatomic) BOOL continuousFallback;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger remainingChecks;
@property(nonatomic) NSUInteger readCount;
@property(nonatomic) NSUInteger eventCount;
@property(nonatomic) int lockToken;
@property(nonatomic) int completeToken;
@end
@implementation NNPLockStateController
- (instancetype)init {
    if ((self = [super init])) _lockToken = _completeToken = -1;
    return self;
}
- (void)start {
    if (self.started) return;
    self.started = YES;
    self.generation++;
    BOOL native = NNPInstallLockNotificationHook();
    __weak typeof(self) weakSelf = self;
    self.nativeObserver = [NSNotificationCenter.defaultCenter addObserverForName:NNPLockStateEvent object:nil queue:nil usingBlock:^(__unused NSNotification *note) { [weakSelf queueEvent]; }];
    int status = notify_register_dispatch("com.apple.springboard.lockstate", &_lockToken, dispatch_get_main_queue(), ^(__unused int token) { [weakSelf queueEvent]; });
    if (status != NOTIFY_STATUS_OK) self.lockToken = -1;
    status = notify_register_dispatch("com.apple.springboard.lockcomplete", &_completeToken, dispatch_get_main_queue(), ^(__unused int token) { [weakSelf queueEvent]; });
    if (status != NOTIFY_STATUS_OK) self.completeToken = -1;
    self.continuousFallback = !native && self.lockToken < 0 && self.completeToken < 0;
    NNPDiagnosticSetBool(@"LockObserverNativeHookInstalled", native);
    NNPDiagnosticSetBool(@"LockObserverDarwinRegistered", self.lockToken >= 0 || self.completeToken >= 0);
    NNPDiagnosticSetBool(@"LockObserverContinuousPolling", self.continuousFallback);
    self.locked = NNPReadLockState();
    NNPDiagnosticSetInteger(@"LockObserverReadCount", ++self.readCount);
    [self beginSettling];
}
- (void)queueEvent {
    if (!self.started) return;
    NNPDiagnosticSetInteger(@"LockObserverEventCount", ++self.eventCount);
    if (self.eventPending) return;
    self.eventPending = YES;
    NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.started || generation != strongSelf.generation) return;
        strongSelf.eventPending = NO;
        [strongSelf poll];
        [strongSelf beginSettling];
    });
}
- (void)beginSettling {
    [self.timer invalidate];
    self.remainingChecks = 3;
    [self scheduleCheck];
}
- (void)scheduleCheck {
    if (!self.started || (!self.continuousFallback && !self.remainingChecks)) {
        self.timer = nil;
        NNPDiagnosticSetBool(@"LockObserverTimerActive", NO);
        return;
    }
    NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:self.continuousFallback ? 1.0 : 0.15 repeats:NO block:^(__unused NSTimer *timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.started || generation != strongSelf.generation) return;
        strongSelf.timer = nil;
        [strongSelf poll];
        if (strongSelf.remainingChecks) strongSelf.remainingChecks--;
        [strongSelf scheduleCheck];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    NNPDiagnosticSetBool(@"LockObserverTimerActive", YES);
}
- (void)poll {
    if (!self.started) return;
    BOOL value = NNPReadLockState();
    NNPDiagnosticSetInteger(@"LockObserverReadCount", ++self.readCount);
    if (value == self.locked) return;
    self.locked = value;
    NNPDiagnosticBeginTransition(value ? @"logical-lock-observed" : @"logical-unlock-observed");
    if (self.stateHandler) self.stateHandler(value);
}
- (void)stop {
    self.started = NO;
    self.generation++;
    self.eventPending = NO;
    [self.timer invalidate]; self.timer = nil;
    if (self.nativeObserver) [NSNotificationCenter.defaultCenter removeObserver:self.nativeObserver];
    self.nativeObserver = nil;
    if (self.lockToken >= 0) notify_cancel(self.lockToken);
    if (self.completeToken >= 0) notify_cancel(self.completeToken);
    self.lockToken = self.completeToken = -1;
    NNPDiagnosticSetBool(@"LockObserverTimerActive", NO);
}
- (void)dealloc { [self stop]; }
@end
