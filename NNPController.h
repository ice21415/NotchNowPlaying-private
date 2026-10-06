#import <Foundation/Foundation.h>
@interface NNPController : NSObject
+ (instancetype)sharedController;
- (void)install;
- (void)refreshDiagnosticUI;
- (void)setLocked:(BOOL)locked;
- (void)revealCoverSheetControlsForWake;
- (BOOL)showNotificationSnakeAnimation;
- (BOOL)shouldHandleMengoWakeTap;
- (BOOL)handleMengoWakeGesture:(id)gesture;
- (void)captureMengoWakeTouches:(id)touches gesture:(id)gesture;
@end
