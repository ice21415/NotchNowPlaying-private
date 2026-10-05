#import <UIKit/UIKit.h>
@interface NNPMengoController : NSObject
@property(nonatomic, copy) void (^presentationChanged)(BOOL open);
- (void)setHostWindow:(UIWindow *)host active:(BOOL)active;
- (void)close;
- (void)restPixelsAtOffset:(CGPoint)pixels;
@end
