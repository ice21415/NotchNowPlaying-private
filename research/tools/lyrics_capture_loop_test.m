#import "../../NNPSpotifyLyricsCaptureLoop.h"
#include <assert.h>
static void Drain(double seconds) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}
int main(void) {
    @autoreleasepool {
        __block BOOL active = NO;
        __block NSUInteger captures = 0;
        NNPSpotifyLyricsCaptureLoop *loop = [[NNPSpotifyLyricsCaptureLoop alloc]
            initWithCapture:^{ captures++; } isActive:^{ return active; }];
        [loop start]; Drain(0.25);
        assert(!loop.running && captures == 0);
        active = YES; [loop start]; [loop start];
        assert(loop.running && captures == 1); // duplicate resume does not duplicate work
        Drain(0.45); assert(captures >= 3);
        [loop stop]; [loop stop];
        NSUInteger stopped = captures;
        Drain(0.45); assert(!loop.running && captures == stopped);
        [loop start]; assert(captures == stopped + 1);
        active = NO; Drain(0.25);
        assert(!loop.running && captures == stopped + 1); // missed lifecycle event remains safe
        active = YES; [loop start];
        __weak NNPSpotifyLyricsCaptureLoop *weakLoop = loop;
        loop = nil;
        assert(weakLoop == nil); // run loop does not retain the owner
        stopped = captures; Drain(0.25); assert(captures == stopped);
        puts("lyrics foreground capture lifecycle passed");
    }
    return 0;
}
