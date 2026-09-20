#import <Foundation/Foundation.h>

@interface NNPDisplayAssertionController : NSObject
@property(nonatomic, readonly) BOOL assertionActive;
- (void)refreshManualArming;
- (BOOL)attemptTemporaryAssertion;
- (void)releaseAssertion;
- (void)releaseAssertionWithReason:(NSString *)reason;
@end
