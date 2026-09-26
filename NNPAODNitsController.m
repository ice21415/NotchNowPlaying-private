#import "NNPAODNitsController.h"
#import "NNPDiagnostics.h"
#import <dlfcn.h>
#import <math.h>
#import <stdatomic.h>
#import <stdint.h>

@protocol NNPAODBacklightFeatures <NSObject>
@property(nonatomic) BOOL disableFeatures;
@property(nonatomic) float fixedBrightnessNitsWhileDisabled;
@end

@protocol NNPAODBrightnessClient <NSObject>
- (id)copyPropertyForKey:(NSString *)key;
@end

typedef void (*NNPAODSetBacklightFeaturesFunction)(id features);

static dispatch_queue_t gNNPAODNitsQueue;
static dispatch_once_t gNNPAODNitsQueueOnce;
static _Atomic(uint64_t) gNNPAODNitsGeneration = 0;
static NNPAODSetBacklightFeaturesFunction gNNPAODSetBacklightFeatures;
static Class gNNPAODBacklightFeaturesClass;
static id<NNPAODBrightnessClient> gNNPAODBrightnessClient;
static BOOL gNNPAODFeatureActive;

static dispatch_queue_t NNPAODNitsQueue(void) {
    dispatch_once(&gNNPAODNitsQueueOnce, ^{
        gNNPAODNitsQueue = dispatch_queue_create("com.user.notchnowplaying.aod-nits", DISPATCH_QUEUE_SERIAL);
    });
    return gNNPAODNitsQueue;
}

static BOOL NNPAODLoadBacklightFeatures(void) {
    if (gNNPAODSetBacklightFeatures && gNNPAODBacklightFeaturesClass) return YES;
    void *framework = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",
                             RTLD_LAZY | RTLD_LOCAL);
    if (!framework) return NO;
    gNNPAODSetBacklightFeatures = (NNPAODSetBacklightFeaturesFunction)dlsym(framework,
        "BKSHIDServicesSetBacklightFeatures");
    gNNPAODBacklightFeaturesClass = NSClassFromString(@"BKSBacklightFeatures");
    return gNNPAODSetBacklightFeatures && gNNPAODBacklightFeaturesClass;
}

static id<NNPAODBrightnessClient> NNPAODGetBrightnessClient(void) {
    if (gNNPAODBrightnessClient) return gNNPAODBrightnessClient;
    Class clientClass = NSClassFromString(@"BrightnessSystemClient");
    if (!clientClass) {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY | RTLD_LOCAL);
        clientClass = NSClassFromString(@"BrightnessSystemClient");
    }
    if (!clientClass) return nil;
    id client = [[clientClass alloc] init];
    if (![client respondsToSelector:@selector(copyPropertyForKey:)]) return nil;
    gNNPAODBrightnessClient = client;
    return gNNPAODBrightnessClient;
}

static void NNPAODRecordReadback(NSString *session, NSString *stage, NSString *diagnosticKey) {
    id<NNPAODBrightnessClient> client = NNPAODGetBrightnessClient();
    if (!client) {
        NNPDiagnosticLog([NSString stringWithFormat:@"AOD_FIXED_NITS session=%@ %@ CoreBrightness client unavailable",
                          session, stage]);
        return;
    }
    id brightness = nil;
    id features = nil;
    @try {
        brightness = [client copyPropertyForKey:@"DisplayBrightness"];
        features = [client copyPropertyForKey:@"CoreBrightnessFeaturesDisabled"];
    } @catch (NSException *exception) {
        NNPDiagnosticLog([NSString stringWithFormat:@"AOD_FIXED_NITS session=%@ %@ readback exception=%@",
                          session, stage, exception.name]);
    }
    NSNumber *nits = [brightness isKindOfClass:NSDictionary.class]
        ? ((NSDictionary *)brightness)[@"Nits"] : nil;
    if ([nits isKindOfClass:NSNumber.class]) NNPDiagnosticSetDouble(diagnosticKey, nits.doubleValue);
    NNPDiagnosticLog([NSString stringWithFormat:@"AOD_FIXED_NITS session=%@ %@ DisplayBrightness=%@ features=%@",
                      session, stage, brightness ?: @"nil", features ?: @"nil"]);
}

static void NNPAODClearBacklightFeatures(void) {
    if (!gNNPAODFeatureActive) return;
    if (!NNPAODLoadBacklightFeatures()) {
        NNPDiagnosticLog(@"AOD_FIXED_NITS cleanup API unavailable");
        return;
    }
    // Both fixed-brightness fields initialize to -1, which releases the override.
    id<NNPAODBacklightFeatures> defaults = [[gNNPAODBacklightFeaturesClass alloc] init];
    gNNPAODSetBacklightFeatures(defaults);
    gNNPAODFeatureActive = NO;
    NNPDiagnosticSetBool(@"Phase7FixedBrightnessActive", NO);
    NNPDiagnosticLog(@"AOD_FIXED_NITS cleared per-PID backlight features");
}

void NNPAODNitsBeginSession(NSString *sessionID, float multiplier) {
    uint64_t generation = atomic_fetch_add_explicit(&gNNPAODNitsGeneration, 1, memory_order_acq_rel) + 1;
    NSString *session = [sessionID copy] ?: @"none";
    float safeMultiplier = isfinite(multiplier) ? fminf(4.0f, fmaxf(1.0f, multiplier)) : 1.0f;
    NNPDiagnosticSetDouble(@"Phase7FixedBrightnessMultiplier", safeMultiplier);
    dispatch_async(NNPAODNitsQueue(), ^{
        if (generation != atomic_load_explicit(&gNNPAODNitsGeneration, memory_order_acquire)) return;
        NNPAODClearBacklightFeatures();
        if (safeMultiplier <= 1.001f) return;
        float targetNits = 20.0f * safeMultiplier;
        NNPDiagnosticSetDouble(@"Phase7FixedBrightnessTargetNits", targetNits);
        BOOL available = NNPAODLoadBacklightFeatures();
        NNPDiagnosticSetBool(@"Phase7FixedBrightnessAPIAvailable", available);
        if (!available) {
            NNPDiagnosticLog([NSString stringWithFormat:@"AOD_FIXED_NITS session=%@ BackBoardServices API unavailable", session]);
            return;
        }
        id<NNPAODBacklightFeatures> features = [[gNNPAODBacklightFeaturesClass alloc] init];
        if (!features || ![features respondsToSelector:@selector(setDisableFeatures:)] ||
            ![features respondsToSelector:@selector(setFixedBrightnessNitsWhileDisabled:)]) {
            NNPDiagnosticLog([NSString stringWithFormat:@"AOD_FIXED_NITS session=%@ BKSBacklightFeatures unavailable", session]);
            return;
        }
        features.disableFeatures = YES;
        features.fixedBrightnessNitsWhileDisabled = targetNits;
        @try {
            gNNPAODSetBacklightFeatures(features);
            gNNPAODFeatureActive = YES;
            NNPDiagnosticSetBool(@"Phase7FixedBrightnessActive", YES);
            NNPDiagnosticLog([NSString stringWithFormat:@"AOD_FIXED_NITS session=%@ requested=%.2f via BackBoardServices",
                              session, targetNits]);
        } @catch (NSException *exception) {
            NNPDiagnosticLog([NSString stringWithFormat:@"AOD_FIXED_NITS session=%@ request exception=%@",
                              session, exception.name]);
        }
        if (!gNNPAODFeatureActive) return;
        NNPAODRecordReadback(session, @"immediate", @"Phase7FixedBrightnessImmediateNits");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), NNPAODNitsQueue(), ^{
            if (generation != atomic_load_explicit(&gNNPAODNitsGeneration, memory_order_acquire)) return;
            NNPAODRecordReadback(session, @"after-0.5s", @"Phase7FixedBrightnessDelayedNits");
        });
    });
}

void NNPAODNitsEndSession(void) {
    atomic_fetch_add_explicit(&gNNPAODNitsGeneration, 1, memory_order_acq_rel);
    dispatch_async(NNPAODNitsQueue(), ^{
        NNPAODClearBacklightFeatures();
    });
}
