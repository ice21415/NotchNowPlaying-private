#import <Foundation/Foundation.h>

@interface NNPBlankingObserver : NSObject
- (void)start;
- (void)recordLogicalLock:(BOOL)locked;
@end
