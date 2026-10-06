#import <Foundation/Foundation.h>
#import "../../NNPMengoSensorMode.h"
#include <assert.h>
void NNPDiagnosticSetBool(NSString *key, BOOL value) {}
void NNPDiagnosticSetInteger(NSString *key, NSInteger value) {}
static BOOL mutateBacklight;
@interface SBBacklightController : NSObject
@property(nonatomic) long long backlightState;
@property(nonatomic) long long lastBacklightChangeSource;
@property(nonatomic) long long sensorState;
@property(nonatomic) long long sensorSource;
@property(nonatomic) NSUInteger updates;
@property(nonatomic) BOOL digitizerDisabled;
@property(nonatomic) BOOL tapToWakeEnabled;
+ (id)sharedInstance;
- (BOOL)isDigitizerDisabled;
- (BOOL)isTapToWakeEnabled;
- (void)_updateHIDUISensorModeForBacklightState:(long long)state source:(long long)source;
@end
@implementation SBBacklightController
+ (id)sharedInstance {
    static id controller; static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [self new]; }); return controller;
}
- (BOOL)isDigitizerDisabled { return self.digitizerDisabled; }
- (BOOL)isTapToWakeEnabled { return self.tapToWakeEnabled; }
- (void)_updateHIDUISensorModeForBacklightState:(long long)state source:(long long)source {
    self.sensorState = state; self.sensorSource = source; self.updates++;
    self.digitizerDisabled = state != 1; self.tapToWakeEnabled = state != 1;
    if (mutateBacklight && state == 1) self.backlightState = 1;
}
@end
int main(void) {
    @autoreleasepool {
        SBBacklightController *controller = [SBBacklightController sharedInstance];
        controller.backlightState = 3; controller.lastBacklightChangeSource = 7;
        NNPMengoSensorMode *owner = [NNPMengoSensorMode new];
        [owner setActive:YES];
        assert(controller.backlightState == 3 && controller.sensorState == 1 && controller.sensorSource == 7);
        assert(!controller.digitizerDisabled && !controller.tapToWakeEnabled);
        NSUInteger count = controller.updates;
        [owner setActive:YES]; assert(controller.updates == count);
        [controller _updateHIDUISensorModeForBacklightState:3 source:9];
        assert(controller.sensorState == 1 && controller.sensorSource == 9 && controller.backlightState == 3);
        controller.backlightState = 1; controller.lastBacklightChangeSource = 3;
        [owner setActive:NO]; assert(controller.sensorState == 1 && controller.sensorSource == 3);
        controller.backlightState = 3;
        [controller _updateHIDUISensorModeForBacklightState:3 source:7];
        assert(controller.sensorState == 3 && controller.tapToWakeEnabled);
        [owner setActive:YES];
        __weak NNPMengoSensorMode *weak = owner;
        owner = nil; assert(!weak && controller.sensorState == 3);
        owner = [NNPMengoSensorMode new]; mutateBacklight = YES;
        [owner setActive:YES]; assert(controller.backlightState == 1);
        count = controller.updates;
        controller.backlightState = 3; [owner setActive:YES];
        assert(controller.updates == count); // failed replay cannot cause a wake loop
        puts("native sensor replay, physical state preservation, restore and failure latch passed");
    }
}
