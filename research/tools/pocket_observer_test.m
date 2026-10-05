#import "../../NNPPocketObserver.m"
#include <assert.h>
void NNPDiagnosticSetBool(__unused NSString *key, __unused BOOL value) {}
void NNPDiagnosticSetInteger(__unused NSString *key, __unused NSInteger value) {}
static NSUInteger originalCalls;
@interface CMPocketStateManager : NSObject
- (void)onPocketStateUpdated:(int)state;
- (long long)translateInternalState:(int)state;
@end
@implementation CMPocketStateManager
- (void)onPocketStateUpdated:(__unused int)state { originalCalls++; }
- (long long)translateInternalState:(int)state { return state; }
@end
static void Drain(void) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}
int main(void) {
    @autoreleasepool {
        NNPPocketObserver *observer = [NNPPocketObserver new];
        __block NSUInteger changes = 0;
        observer.stateChanged = ^(__unused BOOL pocket) { changes++; };
        [observer setActive:YES]; [observer setActive:YES];
        assert(!observer.inPocket); // unavailable state never blanks the display
        CMPocketStateManager *native = [CMPocketStateManager new];
        [native onPocketStateUpdated:1]; Drain();
        assert(observer.inPocket && changes == 1 && originalCalls == 1);
        [native onPocketStateUpdated:1]; Drain(); assert(changes == 1);
        [native onPocketStateUpdated:99]; Drain(); assert(observer.inPocket);
        [native onPocketStateUpdated:0]; Drain(); assert(!observer.inPocket && changes == 2);
        [native onPocketStateUpdated:2]; Drain(); assert(!observer.inPocket); // face-down is not pocket
        [observer setActive:NO];
        [native onPocketStateUpdated:1]; Drain(); assert(!observer.inPocket && changes == 2);
        [observer setActive:YES]; assert(observer.inPocket && changes == 3);
        [observer setActive:NO];
        puts("pocket hook identity, deduplication, unavailable state and lifecycle passed");
    }
    return 0;
}
