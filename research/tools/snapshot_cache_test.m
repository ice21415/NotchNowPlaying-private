#import "../../NNPSnapshotCache.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        __block NSUInteger reads = 0;
        __block NSDictionary *source = @{@"track": @"a", @"lyrics": @[@"first"]};
        NNPSnapshotCache *cache = [[NNPSnapshotCache alloc] initWithLoader:^{ reads++; return source; } recoveryInterval:30];
        NSDictionary *first = [cache snapshotAtTime:100];
        for (NSUInteger i = 0; i < 290; i++) assert([cache snapshotAtTime:100 + i / 10.0] == first);
        assert(reads == 1);
        source = @{@"track": @"b", @"lyrics": @[@"second"]};
        assert([[cache snapshotAtTime:129][@"track"] isEqual:@"a"]);
        [cache invalidate]; [cache invalidate];
        assert([[cache snapshotAtTime:129][@"track"] isEqual:@"b"]);
        assert(reads == 2); // repeated invalidations are one read
        source = @{@"track": @"c"};
        assert([[cache snapshotAtTime:158.9][@"track"] isEqual:@"b"]);
        assert([[cache snapshotAtTime:159][@"track"] isEqual:@"c"]);
        assert(reads == 3); // lost notification recovered at the deadline
        source = nil;
        [cache invalidate];
        assert([cache snapshotAtTime:160].count == 0);
        for (NSUInteger i = 0; i < 29; i++) assert([cache snapshotAtTime:160 + i].count == 0);
        assert(reads == 4); // missing file does not cause a tight retry loop
        source = @{@"track": @"restored"};
        assert([[cache snapshotAtTime:190][@"track"] isEqual:@"restored"]);
        assert(reads == 5);
        assert([[cache snapshotAtTime:10][@"track"] isEqual:@"restored"]);
        assert(reads == 6); // monotonic clock reset also recovers
        puts("Snapshot cache, notification invalidation and recovery checks passed");
    }
}
