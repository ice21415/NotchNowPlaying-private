#import "NNPDisplayAssertionController.h"
#import "NNPDiagnostics.h"
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <mach/mach_error.h>

#ifndef NNP_PHASE2E_ARM_AT_START
#define NNP_PHASE2E_ARM_AT_START 0
#endif

static NSString * const NNPAssertionLog = @"[NotchNowPlaying/DisplayAssertion]";

@interface NNPDisplayAssertionController ()
@property(nonatomic) IOPMAssertionID assertionID;
@property(nonatomic) BOOL assertionActive;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL armed;
@property(nonatomic) BOOL attempted;
@end

@implementation NNPDisplayAssertionController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.assertionID = kIOPMNullAssertionID;
        self.attempted = [NNPDiagnosticCopyValue(@"DisplayAssertionExperimentAttempted") boolValue];
        self.armed = [NNPDiagnosticCopyValue(@"DisplayAssertionExperimentArmed") boolValue] && !self.attempted;
#if NNP_PHASE2E_ARM_AT_START
        if (!self.attempted) self.armed = YES;
#endif
        NNPDiagnosticSetBool(@"ControllerInitialized", YES);
        NNPDiagnosticSetBool(@"DisplayAssertionExperimentAttempted", self.attempted);
        NNPDiagnosticSetBool(@"DisplayAssertionExperimentArmed", self.armed);
    }
    return self;
}

- (void)refreshManualArming {
    BOOL requested = [NNPDiagnosticCopyValue(@"DisplayAssertionExperimentArmed") boolValue];
    if (!self.attempted) self.armed = requested;
    NNPDiagnosticSetBool(@"DisplayAssertionExperimentArmed", self.armed);
}

- (BOOL)attemptTemporaryAssertion {
    if (self.assertionActive) return YES;
    if (!self.armed || self.attempted) return NO;

    self.attempted = YES;
    self.armed = NO;
    NNPDiagnosticSetBool(@"DisplayAssertionExperimentAttempted", YES);
    NNPDiagnosticSetBool(@"DisplayAssertionExperimentArmed", NO);
    NNPDiagnosticSetBool(@"AssertionAttempted", YES);
    NNPDiagnosticSetString(@"AssertionCreateTimestamp", [[NSDate date] description]);

    IOPMAssertionID identifier = kIOPMNullAssertionID;
    IOReturn result = IOPMAssertionCreateWithDescription(
        kIOPMAssertionTypePreventUserIdleDisplaySleep,
        CFSTR("NotchNowPlaying Phase 2E"),
        CFSTR("Temporary display assertion experiment"),
        NULL,
        NULL,
        10.0,
        kIOPMAssertionTimeoutActionRelease,
        &identifier);
    BOOL nullIdentifier = identifier == kIOPMNullAssertionID;
    NSString *symbolic = result == kIOReturnSuccess ? @"kIOReturnSuccess" : [NSString stringWithFormat:@"mach_error=%s", mach_error_string(result) ?: "unknown"];
    NNPDiagnosticSetInteger(@"AssertionCreateResultDecimal", result);
    NNPDiagnosticSetString(@"AssertionCreateResultHex", [NSString stringWithFormat:@"0x%08x", (unsigned int)result]);
    NNPDiagnosticSetInteger(@"AssertionID", identifier);
    NNPDiagnosticSetBool(@"AssertionIDValid", !nullIdentifier);
    NNPDiagnosticSetBool(@"AssertionActive", NO);
    NNPDiagnosticSetString(@"LastError", result == kIOReturnSuccess ? @"null_assertion_id" : symbolic);
    if (result != kIOReturnSuccess || identifier == kIOPMNullAssertionID) {
        NSLog(@"%@ acquire failed, return=%d", NNPAssertionLog, result);
        return NO;
    }

    self.assertionID = identifier;
    self.assertionActive = YES;
    NNPDiagnosticSetBool(@"AssertionActive", YES);
    NSUInteger generation = ++self.generation;
    NSLog(@"%@ acquired, timeout=10s", NNPAssertionLog);

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.generation == generation) {
                NSLog(@"%@ watchdog timeout", NNPAssertionLog);
                [weakSelf releaseAssertionWithReason:@"timeout"];
            }
        });
    });
    return YES;
}

- (void)releaseAssertion {
    [self releaseAssertionWithReason:@"manual_cleanup"];
}

- (void)releaseAssertionWithReason:(NSString *)reason {
    if (!self.assertionActive) return;
    IOPMAssertionID identifier = self.assertionID;
    self.assertionID = kIOPMNullAssertionID;
    self.assertionActive = NO;
    self.generation += 1;
    IOReturn result = IOPMAssertionRelease(identifier);
    NSString *symbolic = result == kIOReturnSuccess ? @"kIOReturnSuccess" : [NSString stringWithFormat:@"mach_error=%s", mach_error_string(result) ?: "unknown"];
    NNPDiagnosticSetBool(@"AssertionActive", NO);
    NNPDiagnosticSetString(@"AssertionReleaseReason", reason ?: @"unknown");
    NNPDiagnosticSetInteger(@"AssertionReleaseResult", result);
    NNPDiagnosticSetString(@"AssertionReleaseTimestamp", [[NSDate date] description]);
    if (result != kIOReturnSuccess) NNPDiagnosticSetString(@"LastError", symbolic);
    NSLog(@"%@ released, return=%d", NNPAssertionLog, result);
}

- (void)dealloc {
    [self releaseAssertionWithReason:@"teardown"];
}

@end
