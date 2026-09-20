#import "NNPDisplayAssertionController.h"
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <mach/mach_error.h>

static NSString * const NNPAssertionLog = @"[Lilywhite/DisplayAssertion]";
static NSString * const NNPDiagnosticDirectory = @"/var/mobile/Library/NotchNowPlaying";
static NSString * const NNPDiagnosticPath = @"/var/mobile/Library/NotchNowPlaying/display-assertion-diagnostic.log";
static NSString * const NNPArmPath = @"/var/mobile/Library/NotchNowPlaying/display-assertion-arm";

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
        [self appendDiagnostic:@"state=DISARMED"]; 
    }
    return self;
}

- (void)appendDiagnostic:(NSString *)event {
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager createDirectoryAtPath:NNPDiagnosticDirectory
        withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions: @0755}
        error:NULL];
    NSString *timestamp = [NSString localizedStringWithFormat:@"%@", [NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, event];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:NNPDiagnosticPath];
    if (!handle) {
        [manager createFileAtPath:NNPDiagnosticPath contents:nil attributes:@{NSFilePosixPermissions: @0644}];
        handle = [NSFileHandle fileHandleForWritingAtPath:NNPDiagnosticPath];
    }
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

- (void)refreshManualArming {
    if (self.armed || self.attempted) return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:NNPArmPath]) return;
    [[NSFileManager defaultManager] removeItemAtPath:NNPArmPath error:NULL];
    self.armed = YES;
    [self appendDiagnostic:@"state=ARMED source=explicit-trigger-file"]; 
    NSLog(@"%@ armed by explicit trigger", NNPAssertionLog);
}

- (BOOL)attemptTemporaryAssertion {
    if (self.assertionActive) return YES;
    if (!self.armed || self.attempted) return NO;

    self.attempted = YES;
    self.armed = NO;
    [self appendDiagnostic:@"state=ATTEMPTED"]; 

    IOPMAssertionID identifier = kIOPMNullAssertionID;
    IOReturn result = IOPMAssertionCreateWithDescription(
        kIOPMAssertionTypePreventUserIdleDisplaySleep,
        CFSTR("NotchNowPlaying Phase 2D"),
        CFSTR("Temporary display assertion experiment"),
        NULL,
        NULL,
        10.0,
        kIOPMAssertionTimeoutActionRelease,
        &identifier);
    BOOL nullIdentifier = identifier == kIOPMNullAssertionID;
    NSString *symbolic = result == kIOReturnSuccess ? @"kIOReturnSuccess" : [NSString stringWithFormat:@"mach_error=%s", mach_error_string(result) ?: "unknown"];
    [self appendDiagnostic:[NSString stringWithFormat:@"acquire result=%d hex=0x%08x symbolic=%@ id=%u null_id=%@", result, result, symbolic, identifier, nullIdentifier ? @"YES" : @"NO"]];
    if (result != kIOReturnSuccess || identifier == kIOPMNullAssertionID) {
        NSLog(@"%@ acquire failed, return=%d", NNPAssertionLog, result);
        return NO;
    }

    self.assertionID = identifier;
    self.assertionActive = YES;
    NSUInteger generation = ++self.generation;
    [self appendDiagnostic:@"acquire accepted timeout=10s"]; 
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
    [self appendDiagnostic:[NSString stringWithFormat:@"release reason=%@ id=%u result=%d hex=0x%08x symbolic=%@", reason ?: @"unknown", identifier, result, result, symbolic]];
    NSLog(@"%@ released, return=%d", NNPAssertionLog, result);
}

- (void)dealloc {
    [self releaseAssertionWithReason:@"teardown"];
}

@end
