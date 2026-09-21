#import <Foundation/Foundation.h>
@interface NNPController : NSObject
+ (instancetype)sharedController;
- (void)install;
- (void)refreshDiagnosticUI;
- (void)setLocked:(BOOL)locked;
@end
