#import "../../NNPCoverConfirmation.h"
#include <assert.h>
static void Drain(double time) { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:time]]; }
int main(void) {
    @autoreleasepool {
        NNPCoverConfirmation *confirmation = [NNPCoverConfirmation new];
        __block BOOL covered = NO;
        __block NSUInteger changes = 0;
        confirmation.onChange = ^(BOOL value) { covered = value; changes++; };
        [confirmation update:YES]; Drain(0.3);
        [confirmation update:NO]; Drain(0.6);
        assert(!covered && changes == 0); // brief pass over the sensor does not blank
        [confirmation update:YES]; Drain(0.5);
        [confirmation update:YES]; Drain(0.4);
        assert(covered && changes == 1); // repeated sensor samples do not postpone confirmation
        [confirmation update:NO]; Drain(0.1);
        [confirmation update:YES]; Drain(0.3); assert(covered && changes == 1);
        [confirmation update:NO]; Drain(0.3); assert(!covered && changes == 2);
        [confirmation update:YES]; [confirmation reset]; Drain(0.9);
        assert(!covered && changes == 2); // no delayed blank after leaving AOD
        [confirmation update:YES]; Drain(0.9); assert(covered && changes == 3);
        [confirmation update:NO];
        __weak NNPCoverConfirmation *weak = confirmation;
        confirmation = nil; assert(weak == nil);
        Drain(0.3); assert(changes == 3);
        puts("cover confirmation, repeated samples, interruption and cancellation passed");
    }
    return 0;
}
