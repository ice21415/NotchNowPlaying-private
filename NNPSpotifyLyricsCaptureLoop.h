#import <Foundation/Foundation.h>

// Main-thread owner of the optional foreground UI fallback.
@interface NNPSpotifyLyricsCaptureLoop : NSObject
@property(nonatomic, readonly, getter=isRunning) BOOL running;
@property(nonatomic, readonly) NSUInteger captureCount;
- (instancetype)initWithCapture:(void (^)(void))capture isActive:(BOOL (^)(void))isActive;
- (void)start;
- (void)stop;
@end
