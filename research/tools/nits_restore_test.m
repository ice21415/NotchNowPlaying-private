#include "../../NNPAODNitsController.m"
#include <assert.h>

void NNPDiagnosticSetBool(NSString *key, BOOL value) { (void)key; (void)value; }
void NNPDiagnosticSetDouble(NSString *key, double value) { (void)key; (void)value; }
void NNPDiagnosticSetInteger(NSString *key, NSInteger value) { (void)key; (void)value; }
void (NNPDiagnosticLog)(NSString *event) { (void)event; }

@interface MockFeatures : NSObject <NNPAODBacklightFeatures>
@property(nonatomic) BOOL disableFeatures;
@property(nonatomic) float fixedBrightnessNitsWhileDisabled;
@end
@implementation MockFeatures
- (instancetype)init {
    if ((self = [super init])) _fixedBrightnessNitsWhileDisabled = -1;
    return self;
}
@end
static atomic_uint cleared;
static void SetFeatures(id features) {
    assert(![(MockFeatures *)features disableFeatures]);
    assert([(MockFeatures *)features fixedBrightnessNitsWhileDisabled] == -1);
    atomic_fetch_add(&cleared, 1);
}
static void Drain(double seconds) {
    double deadline = NSProcessInfo.processInfo.systemUptime + seconds;
    while (NSProcessInfo.processInfo.systemUptime < deadline) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}
int main(void) {
    @autoreleasepool {
        gNNPAODSetBacklightFeatures = SetFeatures;
        gNNPAODBacklightFeaturesClass = MockFeatures.class;
        gNNPAODFeatureActive = YES; gNNPAODCurrentNits = 90;
        __block BOOL completed = NO;
        NNPAODNitsEndSessionWithCompletion(^{
            assert(NSThread.isMainThread && !gNNPAODFeatureActive);
            assert(atomic_load(&cleared) == 1 && gNNPAODCurrentNits == 0);
            completed = YES;
        });
        dispatch_sync(NNPAODNitsQueue(), ^{}); Drain(0.05);
        assert(completed);

        // A new session before cleanup must cancel cleanup and completion.
        dispatch_semaphore_t gate = dispatch_semaphore_create(0);
        dispatch_async(NNPAODNitsQueue(), ^{ dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER); });
        gNNPAODFeatureActive = YES; completed = NO;
        NNPAODNitsEndSessionWithCompletion(^{ completed = YES; });
        atomic_fetch_add(&gNNPAODNitsGeneration, 1);
        dispatch_semaphore_signal(gate);
        dispatch_sync(NNPAODNitsQueue(), ^{}); Drain(0.05);
        assert(!completed && gNNPAODFeatureActive && atomic_load(&cleared) == 1);

        // A new session after cleanup but before the main callback cancels it.
        NNPAODNitsEndSessionWithCompletion(^{ completed = YES; });
        dispatch_sync(NNPAODNitsQueue(), ^{});
        atomic_fetch_add(&gNNPAODNitsGeneration, 1);
        Drain(0.05);
        assert(!completed && !gNNPAODFeatureActive && atomic_load(&cleared) == 2);

        gNNPAODFeatureActive = YES;
        NNPAODNitsEndSession(); dispatch_sync(NNPAODNitsQueue(), ^{});
        assert(!gNNPAODFeatureActive && atomic_load(&cleared) == 3);
        puts("Brightness cleanup ordering, main completion and stale-session cancellation passed");
    }
    return 0;
}
