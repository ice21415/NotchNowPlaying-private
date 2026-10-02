#define NNP_DIAGNOSTICS_DOMAIN "com.user.notchnowplaying.tests"
#include "../../NNPDiagnostics.m"
#include <assert.h>

static void WaitForBatch(void) {
    [NSThread sleepForTimeInterval:0.8];
    dispatch_sync(NNPDiagnosticWriteQueue, ^{});
}
static void ClearTestDomain(void) {
    CFArrayRef keys = CFPreferencesCopyKeyList(NNPDiagDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    for (NSString *key in (__bridge NSArray *)keys) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, NNPDiagDomain);
    }
    if (keys) CFRelease(keys);
    CFPreferencesAppSynchronize(NNPDiagDomain);
}
int main(void) {
    @autoreleasepool {
        ClearTestDomain();
        NNPDiagnosticSetInteger(@"Burst", 1);
        NNPDiagnosticSetInteger(@"Burst", 2);
        NNPDiagnosticSetInteger(@"Burst", 2);
        NNPDiagnosticSetBool(@"Stable", YES);
        NNPDiagnosticSetBool(@"Stable", YES);
        NNPDiagnosticLog(@"Release build must not persist this detailed event.");
        NNPDiagnosticAppendEvent(@{@"event": @"not persisted"});
        WaitForBatch();
        assert([NNPDiagnosticCopyValue(@"Burst") integerValue] == 2);
        assert([NNPDiagnosticCopyValue(@"Stable") boolValue]);
        assert([NNPDiagnosticCopyValue(@"DiagnosticFlushBatchCount") integerValue] == 1);
        assert([NNPDiagnosticCopyValue(@"DiagnosticChangedValueCount") integerValue] == 2);
        assert(NNPDiagnosticCopyValue(@"DiagnosticLogEvents") == nil);
        assert(NNPDiagnosticCopyValue(@"BlankingObserverEvents") == nil);
        NNPDiagnosticSetInteger(@"Burst", 2);
        NNPDiagnosticSetBool(@"Stable", YES);
        WaitForBatch();
        assert([NNPDiagnosticCopyValue(@"DiagnosticFlushBatchCount") integerValue] == 1);
        NNPDiagnosticSetInteger(@"Burst", 3);
        NNPDiagnosticSetInteger(@"Burst", 4);
        WaitForBatch();
        assert([NNPDiagnosticCopyValue(@"Burst") integerValue] == 4);
        assert([NNPDiagnosticCopyValue(@"DiagnosticFlushBatchCount") integerValue] == 2);
        assert([NNPDiagnosticCopyValue(@"DiagnosticSkippedDuplicateCount") integerValue] >= 4);
        ClearTestDomain();
        puts("Diagnostic coalescing, unchanged-value suppression and release logging checks passed");
    }
    return 0;
}
