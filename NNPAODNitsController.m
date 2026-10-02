#import "NNPAODPixelPolicy.h"
#import "NNPAODNitsController.h"
#import "NNPDiagnostics.h"
#import <dlfcn.h>
#import <math.h>
#import <stdatomic.h>
#import <stdint.h>
#import <unistd.h>

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
static float gNNPAODCurrentNits;

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
    id nits = [brightness isKindOfClass:NSDictionary.class]
        ? ((NSDictionary *)brightness)[@"Nits"] : nil;
    if ([nits isKindOfClass:NSNumber.class]) NNPDiagnosticSetDouble(diagnosticKey, [(NSNumber *)nits doubleValue]);
    else if ([nits isKindOfClass:NSString.class]) {
        double value = 0;
        NSScanner *scanner = [NSScanner scannerWithString:nits];
        if ([scanner scanDouble:&value] && scanner.isAtEnd && isfinite(value) && value >= 0)
            NNPDiagnosticSetDouble(diagnosticKey, value);
    }
    id override = [features isKindOfClass:NSDictionary.class]
        ? ((NSDictionary *)features)[@"OverrideBrightnessWithFixedNits"] : nil;
    if ([override respondsToSelector:@selector(doubleValue)])
        NNPDiagnosticSetDouble(@"Phase7FixedBrightnessAppliedNits", [override doubleValue]);
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
    gNNPAODCurrentNits = 0;
    NNPDiagnosticSetBool(@"Phase7FixedBrightnessActive", NO);
    NNPDiagnosticLog(@"AOD_FIXED_NITS cleared per-PID backlight features");
}

static void NNPAODApplyTargetNits(NSString *sessionID, float targetNits, BOOL smooth) {
    uint64_t generation = atomic_fetch_add_explicit(&gNNPAODNitsGeneration, 1, memory_order_acq_rel) + 1;
    NSString *session = [sessionID copy] ?: @"none";
    NNPDiagnosticSetInteger(@"Phase7FixedBrightnessPID", getpid());
    NNPDiagnosticSetDouble(@"Phase7FixedBrightnessImmediateNits", -1);
    NNPDiagnosticSetDouble(@"Phase7FixedBrightnessDelayedNits", -1);
    NNPDiagnosticSetDouble(@"Phase7FixedBrightnessTargetNits", targetNits);
    dispatch_async(NNPAODNitsQueue(), ^{
        if (generation != atomic_load_explicit(&gNNPAODNitsGeneration, memory_order_acquire)) return;
        if (targetNits <= 0) {
            NNPAODClearBacklightFeatures();
            NNPDiagnosticSetBool(@"Phase7FixedBrightnessActive", NO);
            return;
        }
        BOOL available = NNPAODLoadBacklightFeatures();
        NNPDiagnosticSetBool(@"Phase7FixedBrightnessAPIAvailable", available);
        if (!available) return;
        id<NNPAODBacklightFeatures> features = [[gNNPAODBacklightFeaturesClass alloc] init];
        if (!features || ![features respondsToSelector:@selector(setDisableFeatures:)] ||
            ![features respondsToSelector:@selector(setFixedBrightnessNitsWhileDisabled:)]) return;
        float start = gNNPAODFeatureActive && gNNPAODCurrentNits > 0 ? gNNPAODCurrentNits : targetNits;
        unsigned steps = smooth && fabsf(start - targetNits) > 0.5f ? NNPAODBrightnessRampSteps : 1;
        for (unsigned step = 1; step <= steps; step++) {
            float nits = steps == 1 ? targetNits : NNPAODInterpolateNits(start, targetNits, step);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((steps == 1 ? 0 : step * NNPAODBrightnessRampInterval) * NSEC_PER_SEC)), NNPAODNitsQueue(), ^{
                if (generation != atomic_load_explicit(&gNNPAODNitsGeneration, memory_order_acquire)) return;
                features.disableFeatures = YES;
                features.fixedBrightnessNitsWhileDisabled = nits;
                @try {
                    gNNPAODSetBacklightFeatures(features);
                    gNNPAODFeatureActive = YES;
                    gNNPAODCurrentNits = nits;
                } @catch (NSException *exception) {
                    NNPDiagnosticLog([NSString stringWithFormat:@"AOD_FIXED_NITS request exception=%@", exception.name]);
                    return;
                }
                if (step != steps) return;
                NNPDiagnosticSetBool(@"Phase7FixedBrightnessActive", YES);
                NNPDiagnosticLog([NSString stringWithFormat:@"AOD_FIXED_NITS session=%@ requested=%.2f rampSteps=%u", session, targetNits, steps]);
                NNPAODRecordReadback(session, @"immediate", @"Phase7FixedBrightnessImmediateNits");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), NNPAODNitsQueue(), ^{
                    if (generation != atomic_load_explicit(&gNNPAODNitsGeneration, memory_order_acquire)) return;
                    NNPAODRecordReadback(session, @"after-0.5s", @"Phase7FixedBrightnessDelayedNits");
                });
            });
        }
    });
}

void NNPAODNitsBeginSession(NSString *sessionID, float multiplier) {
    float safe = isfinite(multiplier) ? fminf(4, fmaxf(1, multiplier)) : 1;
    NNPDiagnosticSetDouble(@"Phase7FixedBrightnessMultiplier", safe);
    NNPAODApplyTargetNits(sessionID, safe <= 1.001f ? 0 : 30 * safe, NO);
}

void NNPAODNitsSetTargetNits(NSString *sessionID, float nits) {
    float safe = isfinite(nits) && nits > 0 ? fminf(90, fmaxf(6, nits)) : 0;
    NNPAODApplyTargetNits(sessionID, safe, YES);
}

void NNPAODNitsEndSession(void) {
    atomic_fetch_add_explicit(&gNNPAODNitsGeneration, 1, memory_order_acq_rel);
    dispatch_async(NNPAODNitsQueue(), ^{
        NNPAODClearBacklightFeatures();
    });
}
