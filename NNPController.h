#import <Foundation/Foundation.h>
@interface NNPController : NSObject
+ (instancetype)sharedController;
- (void)install;
- (void)setLocked:(BOOL)locked;
@end
