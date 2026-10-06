#import <UIKit/UIKit.h>
@interface NNPMengoTouchMonitor : NSObject
@property(nonatomic, copy) void (^contact)(CGPoint normalized, BOOL down);
- (void)setActive:(BOOL)active;
@end
