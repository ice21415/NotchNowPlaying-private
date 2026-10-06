#import <Foundation/Foundation.h>
#import "../../NNPAODTouchAssertion.h"
#include <assert.h>
void NNPDiagnosticSetBool(NSString *key, BOOL value) {}
static NSUInteger requests, invalidations;
@interface TestTouchMode : NSObject
@property(nonatomic) long long displayState;
@property(nonatomic) BOOL digitizerEnabled;
@property(nonatomic) BOOL tapToWakeEnabled;
@end
@implementation TestTouchMode
@end
@interface BKSHIDUISensorMode : NSObject
+ (id)buildModeForReason:(NSString *)reason builder:(void (^)(id))builder;
@end
@implementation BKSHIDUISensorMode
+ (id)buildModeForReason:(NSString *)reason builder:(void (^)(id))builder {
    TestTouchMode *mode = [TestTouchMode new]; mode.tapToWakeEnabled = YES;
    builder(mode); return mode;
}
@end
@interface TestTouchToken : NSObject
- (void)invalidate;
@end
@implementation TestTouchToken
- (void)invalidate { invalidations++; }
@end
@interface BKSHIDUISensorService : NSObject
+ (id)sharedInstance;
- (id)requestUISensorMode:(TestTouchMode *)mode;
@end
@implementation BKSHIDUISensorService
+ (id)sharedInstance { return [self new]; }
- (id)requestUISensorMode:(TestTouchMode *)mode {
    assert(mode.displayState == 2 && mode.digitizerEnabled && !mode.tapToWakeEnabled);
    requests++; return [TestTouchToken new];
}
@end
int main(void) {
    @autoreleasepool {
        NNPAODTouchAssertion *owner = [NNPAODTouchAssertion new];
        [owner setActive:NO]; assert(requests == 0);
        [owner setActive:YES]; [owner setActive:YES]; assert(requests == 1);
        [owner setActive:NO]; [owner setActive:NO]; assert(invalidations == 1);
        [owner setActive:YES]; assert(requests == 2);
        __weak NNPAODTouchAssertion *weakOwner = owner;
        owner = nil; assert(!weakOwner && invalidations == 2);
        puts("AOD digitizer configuration and assertion lifecycle tests passed");
    }
}
