#import <Foundation/Foundation.h>
@interface NNPScreenCoverObserver : NSObject
@property(nonatomic, readonly) BOOL covered;
@property(nonatomic, copy) void (^stateChanged)(BOOL covered);
- (void)setActive:(BOOL)active;
@end
