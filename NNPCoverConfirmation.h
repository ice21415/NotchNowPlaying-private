#import <Foundation/Foundation.h>
@interface NNPCoverConfirmation : NSObject
@property(nonatomic, copy) void (^onChange)(BOOL covered);
- (void)update:(BOOL)covered;
- (void)reset;
@end
