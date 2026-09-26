#import <Foundation/Foundation.h>
@class NNPState;
typedef void (^NNPStateHandler)(NNPState *state);
@interface NNPMediaController : NSObject
@property(nonatomic, copy) NNPStateHandler stateHandler;
- (void)start;
- (void)refresh;
- (BOOL)skipToPreviousTrack;
- (BOOL)skipToNextTrack;
@end
