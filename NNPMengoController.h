#import <UIKit/UIKit.h>
@interface NNPMengoController : NSObject
@property(nonatomic, copy) void (^presentationChanged)(BOOL open);
@property(nonatomic, copy) void (^outsideTap)(void);
- (void)setHostView:(UIView *)host active:(BOOL)active;
- (void)close;
- (void)restPixelsAtOffset:(CGPoint)pixels;
- (CGRect)interactiveRectInView:(UIView *)view;
- (BOOL)handleTapAtPoint:(CGPoint)point inView:(UIView *)view;
@end
