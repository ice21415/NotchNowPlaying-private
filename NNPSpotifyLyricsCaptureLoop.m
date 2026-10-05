#import "NNPSpotifyLyricsCaptureLoop.h"

@interface NNPSpotifyLyricsCaptureLoop ()
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) void (^capture)(void);
@property(nonatomic, copy) BOOL (^isActive)(void);
@property(nonatomic, readwrite) NSUInteger captureCount;
@end

@implementation NNPSpotifyLyricsCaptureLoop
- (instancetype)initWithCapture:(void (^)(void))capture isActive:(BOOL (^)(void))isActive {
    if ((self = [super init])) {
        _capture = [capture copy];
        _isActive = [isActive copy];
    }
    return self;
}
- (BOOL)isRunning { return self.timer != nil; }
- (void)captureIfActive {
    if (!self.isActive()) {
        [self stop];
        return;
    }
    self.captureCount++;
    self.capture();
}
- (void)start {
    if (self.timer || !self.isActive()) return;
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(__unused NSTimer *timer) {
        [weakSelf captureIfActive];
    }];
    [self captureIfActive];
}
- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
}
- (void)dealloc { [_timer invalidate]; }
@end
