#import "../../NNPQueueSnapshot.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        NSDictionary *queue = @{@"currentURI": @"spotify:track:a", @"currentTitle": @"Song", @"currentArtist": @"Artist", @"timestamp": @1000};
        assert(NNPQueueSnapshotMatches(queue, @"spotify:track:a#session", @"Song", @"Artist", 1010));
        assert(!NNPQueueSnapshotMatches(queue, @"spotify:track:b", @"Song", @"Artist", 1010));
        assert(!NNPQueueSnapshotMatches(queue, @"spotify:track:a", @"Song", @"Artist", 23000));
        assert(!NNPQueueSnapshotMatches(queue, @"spotify:track:a", @"Song", @"Artist", 900));
        assert(NNPQueueSnapshotMatches(queue, @"", @"Song", @"Artist", 1010));
        assert(!NNPQueueSnapshotMatches(queue, @"", @"Song", @"Other artist", 1010));
        assert(!NNPQueueSnapshotMatches(@{}, @"", @"Song", @"Artist", 1010));
        assert([NNPQueueText(@42) isEqualToString:@""]);
        puts("Queue association and stale snapshot checks passed");
    }
}
