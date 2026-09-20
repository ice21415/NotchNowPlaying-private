#import <UIKit/UIKit.h>
@class NNPState;
@interface NNPView : UIView
- (void)updateState:(NNPState *)state;
- (void)updateElapsed:(NSTimeInterval)elapsed duration:(NSTimeInterval)duration playing:(BOOL)playing;
@end
