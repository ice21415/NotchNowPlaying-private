#import "../../NNPCoverConfirmation.h"
#include <assert.h>
static void Drain(double time) {
    double deadline = NSProcessInfo.processInfo.systemUptime + time;
    while (NSProcessInfo.processInfo.systemUptime < deadline) {
        double remaining = deadline - NSProcessInfo.processInfo.systemUptime;
        BOOL ran = [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
            beforeDate:[NSDate dateWithTimeIntervalSinceNow:MIN(0.02, remaining)]];
        if (!ran) [NSThread sleepForTimeInterval:MIN(0.005, remaining)];
    }
}
int main(void) {
    @autoreleasepool {
        NNPCoverConfirmation *confirmation = [NNPCoverConfirmation new];
        __block BOOL covered = NO;
        __block NSUInteger changes = 0;
        confirmation.onChange = ^(BOOL value) { covered = value; changes++; };
        [confirmation update:YES]; Drain(0.3);
        [confirmation update:NO]; Drain(0.6);
        assert(!covered && changes == 0); // brief pass over the sensor does not blank
        [confirmation update:YES];
        NSDate *scheduled = [[confirmation valueForKey:@"timer"] fireDate];
        [confirmation update:YES];
        assert([scheduled isEqualToDate:[[confirmation valueForKey:@"timer"] fireDate]]);
        Drain(1.2);
        assert(covered && changes == 1); // repeated sensor samples do not postpone confirmation
        [confirmation update:NO]; Drain(0.1);
        [confirmation update:YES]; Drain(0.3); assert(covered && changes == 1);
        [confirmation update:NO]; Drain(0.6); assert(!covered && changes == 2);
        [confirmation update:YES]; [confirmation reset]; Drain(0.9);
        assert(!covered && changes == 2); // no delayed blank after leaving AOD
        [confirmation update:YES]; Drain(1.2); assert(covered && changes == 3);
        [confirmation update:NO];
        __weak NNPCoverConfirmation *weak = confirmation;
        confirmation = nil; assert(weak == nil);
        Drain(0.3); assert(changes == 3);
        puts("cover confirmation, repeated samples, interruption and cancellation passed");
    }
    return 0;
}
