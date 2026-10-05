#import "../../NNPQueueSnapshot.h"
#import "../../NNPCoverURL.h"
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
        NSString *imageID = @"0123456789abcdef0123456789abcdef01234567";
        NSString *imageURL = [@"https://i.scdn.co/image/" stringByAppendingString:imageID];
        assert([NNPCoverURLString([@"spotify:image:" stringByAppendingString:imageID]) isEqualToString:imageURL]);
        assert([NNPCoverURLString([NSURL URLWithString:imageURL]) isEqualToString:imageURL]);
        assert(!NNPCoverURLString(@"spotify:image:invalid").length);
        assert(!NNPCoverURLString(@"https://other.example/image/x").length);
        assert(!NNPCoverURLString(@"file:///tmp/image.jpg").length);
        assert(!NNPCoverURLString(@42).length);
        puts("Queue association and stale snapshot checks passed");
    }
}
