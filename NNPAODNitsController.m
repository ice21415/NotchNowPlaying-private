#import "NNPAODNitsController.h"
#import "NNPDiagnostics.h"
#import <dlfcn.h>
#import <math.h>
#import <stdatomic.h>
#import <stdint.h>

@protocol NNPAODBrightnessClient <NSObject>
- (id)copyPropertyForKey:(NSString *)key;
- (BOOL)setProperty:(id)property forKey:(NSString *)key;
@end

static NSString *const NNPAODDisplayBrightnessKey = @"DisplayBrightness";
static dispatch_queue_t gNNPAODNitsQueue;
static dispatch_once_t gNNPAODNitsQueueOnce;
static _Atomic(uint64_t) gNNPAODNitsGeneration = 0;
static id<NNPAODBrightnessClient> gNNPAODBrightnessClient;
static id gNNPAODOriginalBrightnessProperty;

static dispatch_queue_t NNPAODNitsQueue(void) {
    dispatch_once(&gNNPAODNitsQueueOnce, ^{
        gNNPAODNitsQueue = dispatch_queue_create("com.user.notchnowplaying.aod-nits", DISPATCH_QUEUE_SERIAL);
    });
    return gNNPAODNitsQueue;
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
    if (![client respondsToSelector:@selector(copyPropertyForKey:)] ||
        ![client respondsToSelector:@selector(setProperty:forKey:)]) return nil;
    gNNPAODBrightnessClient = client;
    return gNNPAODBrightnessClient;
}

static BOOL NNPAODRestoreOriginalBrightness(void) {
    if (!gNNPAODOriginalBrightnessProperty) return YES;
    id original = gNNPAODOriginalBrightnessProperty;
    BOOL accepted = NO;
    @try {
        accepted = [gNNPAODBrightnessClient setProperty:original forKey:NNPAODDisplayBrightnessKey];
    } @catch (NSException *exception) {
        NNPDiagnosticLog([NSString stringWithFormat:@"AOD_NITS restore exception=%@", exception.name]);
    }
    NNPDiagnosticSetBool(@"Phase7NitsRestoreAccepted", accepted);
    NNPDiagnosticLog([NSString stringWithFormat:@"AOD_NITS restored original DisplayBrightness accepted=%@ class=%@",
                      accepted ? @"YES" : @"NO", NSStringFromClass([original class])]);
    if (accepted) gNNPAODOriginalBrightnessProperty = nil;
    return accepted;
}

void NNPAODNitsBeginSession(NSString *sessionID, float multiplier) {
    uint64_t generation = atomic_fetch_add_explicit(&gNNPAODNitsGeneration, 1, memory_order_acq_rel) + 1;
    NSString *session = [sessionID copy] ?: @"none";
    float safeMultiplier = isfinite(multiplier) ? fminf(4.0f, fmaxf(1.0f, multiplier)) : 1.0f;
    NNPDiagnosticSetDouble(@"Phase7NitsRequestedMultiplier", safeMultiplier);
    if (safeMultiplier <= 1.001f) {
        NNPDiagnosticLog([NSString stringWithFormat:@"AOD_NITS session=%@ 100%% setting; native dim level retained", session]);
        return;
    }

    // 20–80 nits stays well below normal full-screen HDR brightness while
    // giving the 400% setting a physically distinct request. The server
    // clamps the request to the panel's own min/max nits before HID output.
    float targetNits = 20.0f * safeMultiplier;
    NNPDiagnosticSetDouble(@"Phase7NitsTarget", targetNits);
    dispatch_async(NNPAODNitsQueue(), ^{
        if (generation != atomic_load_explicit(&gNNPAODNitsGeneration, memory_order_acquire)) return;
        if (!NNPAODRestoreOriginalBrightness()) return;
        id<NNPAODBrightnessClient> client = NNPAODGetBrightnessClient();
        NNPDiagnosticSetBool(@"Phase7NitsClientAvailable", client != nil);
        if (!client) {
            NNPDiagnosticLog([NSString stringWithFormat:@"AOD_NITS session=%@ CoreBrightness client unavailable", session]);
            return;
        }

        id original = nil;
        @try {
            original = [client copyPropertyForKey:NNPAODDisplayBrightnessKey];
        } @catch (NSException *exception) {
            NNPDiagnosticLog([NSString stringWithFormat:@"AOD_NITS session=%@ snapshot exception=%@", session, exception.name]);
        }
        BOOL restorable = [original isKindOfClass:NSNumber.class] || [original isKindOfClass:NSDictionary.class];
        NNPDiagnosticSetBool(@"Phase7NitsSnapshotAvailable", restorable);
        NNPDiagnosticSetString(@"Phase7NitsSnapshotClass", original ? NSStringFromClass([original class]) : @"none");
        if (!restorable || generation != atomic_load_explicit(&gNNPAODNitsGeneration, memory_order_acquire)) {
            NNPDiagnosticLog([NSString stringWithFormat:@"AOD_NITS session=%@ skipped: %@",
                              session, restorable ? @"session ended" : @"no restorable DisplayBrightness snapshot"]);
            return;
        }

        NSDictionary *requestedProperty = @{ @"Nits": @(targetNits) };
        BOOL accepted = NO;
        // Keep the snapshot even if the XPC client reports failure: the
        // server may have queued the write before the client saw an error.
        gNNPAODOriginalBrightnessProperty = original;
        @try {
            accepted = [client setProperty:requestedProperty forKey:NNPAODDisplayBrightnessKey];
        } @catch (NSException *exception) {
            NNPDiagnosticLog([NSString stringWithFormat:@"AOD_NITS session=%@ apply exception=%@", session, exception.name]);
        }
        NNPDiagnosticSetBool(@"Phase7NitsApplyAccepted", accepted);
        NNPDiagnosticLog([NSString stringWithFormat:@"AOD_NITS session=%@ requested=%.2f nits accepted=%@ originalClass=%@",
                          session, targetNits, accepted ? @"YES" : @"NO", NSStringFromClass([original class])]);
        if (!accepted) {
            NNPAODRestoreOriginalBrightness();
            return;
        }

        if (generation != atomic_load_explicit(&gNNPAODNitsGeneration, memory_order_acquire)) {
            NNPAODRestoreOriginalBrightness();
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), NNPAODNitsQueue(), ^{
            if (generation != atomic_load_explicit(&gNNPAODNitsGeneration, memory_order_acquire)) return;
            id readback = nil;
            @try {
                readback = [client copyPropertyForKey:NNPAODDisplayBrightnessKey];
            } @catch (NSException *exception) {
                NNPDiagnosticLog([NSString stringWithFormat:@"AOD_NITS session=%@ readback exception=%@", session, exception.name]);
            }
            NNPDiagnosticLog([NSString stringWithFormat:@"AOD_NITS session=%@ DisplayBrightness readback=%@", session, readback ?: @"nil"]);
        });
    });
}

void NNPAODNitsEndSession(void) {
    atomic_fetch_add_explicit(&gNNPAODNitsGeneration, 1, memory_order_acq_rel);
    dispatch_async(NNPAODNitsQueue(), ^{
        if (!NNPAODRestoreOriginalBrightness()) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NNPAODNitsQueue(), ^{
                NNPAODRestoreOriginalBrightness();
            });
        }
    });
}
