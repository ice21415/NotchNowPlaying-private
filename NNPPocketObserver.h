#import <Foundation/Foundation.h>
@interface NNPPocketObserver : NSObject
@property(nonatomic, readonly) BOOL inPocket;
@property(nonatomic, copy) void (^stateChanged)(BOOL inPocket);
- (void)setActive:(BOOL)active;
@end
