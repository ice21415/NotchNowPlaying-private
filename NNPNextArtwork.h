#import <UIKit/UIKit.h>
@interface NNPNextArtwork : NSObject
@property(nonatomic, strong, readonly) UIImage *image;
- (void)setURL:(NSString *)URL active:(BOOL)active onChange:(dispatch_block_t)onChange;
@end
