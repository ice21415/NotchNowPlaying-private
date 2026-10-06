#import "../../NNPLockStateController.m"
#include <assert.h>
void NNPDiagnosticSetBool(__unused NSString *key, __unused BOOL value) {}
void NNPDiagnosticSetInteger(__unused NSString *key, __unused NSInteger value) {}
NSString *NNPDiagnosticBeginTransition(__unused NSString *reason) { return @"test"; }
static NSUInteger originalCalls;
@interface SBLockScreenManager : NSObject
@property(nonatomic) BOOL fakeLocked;
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
- (void)_sendUILockStateChangedNotification;
@end
@implementation SBLockScreenManager
+ (instancetype)sharedInstance {
    static SBLockScreenManager *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [self new]; });
    return instance;
}
- (BOOL)isUILocked { return self.fakeLocked; }
- (void)_sendUILockStateChangedNotification { originalCalls++; }
@end
static void Drain(double interval) {
    double deadline = NSProcessInfo.processInfo.systemUptime + interval;
    while (NSProcessInfo.processInfo.systemUptime < deadline) {
        double remaining = deadline - NSProcessInfo.processInfo.systemUptime;
        BOOL ran = [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
            beforeDate:[NSDate dateWithTimeIntervalSinceNow:MIN(0.02, remaining)]];
        if (!ran) [NSThread sleepForTimeInterval:MIN(0.005, remaining)];
    }
}
int main(void) {
    @autoreleasepool {
        SBLockScreenManager *manager = [SBLockScreenManager sharedInstance];
        NNPLockStateController *observer = [NNPLockStateController new];
        __block NSUInteger changes = 0;
        observer.stateHandler = ^(__unused BOOL locked) { changes++; };
        [observer start]; [observer start];
        Drain(1.05);
        assert(!observer.isLocked && !observer.continuousFallback && !observer.timer);
        NSUInteger reads = observer.readCount;
        Drain(0.3);
        assert(observer.readCount == reads); // no steady 10 Hz polling
        [manager _sendUILockStateChangedNotification];
        Drain(0.05);
        manager.fakeLocked = YES; // state becomes available after its notification
        Drain(0.6);
        assert(observer.isLocked && changes == 1 && !observer.timer);
        for (NSUInteger i = 0; i < 10; i++) [manager _sendUILockStateChangedNotification];
        Drain(1.05);
        assert(changes == 1 && originalCalls == 11);
        reads = observer.readCount;
        Drain(0.3);
        assert(observer.readCount == reads);
        manager.fakeLocked = NO;
        [manager _sendUILockStateChangedNotification];
        Drain(1.05);
        assert(!observer.isLocked && changes == 2);
        [manager _sendUILockStateChangedNotification];
        [observer stop];
        reads = observer.readCount;
        Drain(1.05);
        assert(observer.readCount == reads && !observer.timer && observer.lockToken == -1 && observer.completeToken == -1);
        [observer start];
        Drain(1.05);
        assert(!observer.timer);
        manager.fakeLocked = YES;
        [manager _sendUILockStateChangedNotification];
        Drain(1.05);
        assert(observer.isLocked && changes == 3);
        [observer stop];
        puts("Native lock event, delayed state, deduplication, cleanup and restart checks passed");
    }
}
