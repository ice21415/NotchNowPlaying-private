#import "NNPState.h"

@implementation NNPState
- (BOOL)hasTrack { return self.title.length || self.artist.length || self.artwork != nil; }
- (NNPState *)copyState {
    NNPState *copy = [NNPState new];
    copy.title = self.title; copy.artist = self.artist; copy.album = self.album;
    copy.artwork = self.artwork; copy.duration = self.duration; copy.elapsed = self.elapsed;
    copy.timestamp = self.timestamp; copy.playbackRate = self.playbackRate;
    copy.playing = self.playing; copy.bundleIdentifier = self.bundleIdentifier;
    copy.uniqueIdentifier = self.uniqueIdentifier; copy.validDuration = self.validDuration;
    return copy;
}
@end
