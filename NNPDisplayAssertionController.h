#import <Foundation/Foundation.h>

@interface NNPDisplayAssertionController : NSObject
@property(nonatomic, readonly) BOOL assertionActive;
- (BOOL)acquireTemporaryAssertion;
- (void)releaseAssertion;
@end
