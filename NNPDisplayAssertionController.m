#import "NNPDisplayAssertionController.h"
#import <IOKit/pwr_mgt/IOPMLib.h>

static NSString * const NNPAssertionLog = @"[Lilywhite/DisplayAssertion]";

@interface NNPDisplayAssertionController ()
@property(nonatomic) IOPMAssertionID assertionID;
@property(nonatomic) BOOL assertionActive;
@property(nonatomic) NSUInteger generation;
@end

@implementation NNPDisplayAssertionController

- (BOOL)acquireTemporaryAssertion {
    if (self.assertionActive) return YES;

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
    if (result != kIOReturnSuccess || identifier == kIOPMNullAssertionID) {
        NSLog(@"%@ acquire failed, return=%d", NNPAssertionLog, result);
        return NO;
    }

    self.assertionID = identifier;
    self.assertionActive = YES;
    NSUInteger generation = ++self.generation;
    NSLog(@"%@ acquired, timeout=10s", NNPAssertionLog);

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.generation == generation) {
                NSLog(@"%@ watchdog timeout", NNPAssertionLog);
                [weakSelf releaseAssertion];
            }
        });
    });
    return YES;
}

- (void)releaseAssertion {
    if (!self.assertionActive) return;
    IOPMAssertionID identifier = self.assertionID;
    self.assertionID = kIOPMNullAssertionID;
    self.assertionActive = NO;
    self.generation += 1;
    IOReturn result = IOPMAssertionRelease(identifier);
    NSLog(@"%@ released, return=%d", NNPAssertionLog, result);
}

- (void)dealloc {
    [self releaseAssertion];
}

@end
