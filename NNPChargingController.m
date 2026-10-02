#import "NNPChargingController.h"
#import "NNPPreferences.h"
#import "NNPChargingPolicy.h"
#import "NNPDiagnostics.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <math.h>

@interface NNPChargingView : UIView
@property(nonatomic, strong) NSArray<CAShapeLayer *> *streams;
@property(nonatomic) BOOL running;
@property(nonatomic) BOOL reducedMotion;
@property(nonatomic) CGFloat batteryProgress;
- (void)setRunning:(BOOL)running reducedMotion:(BOOL)reducedMotion;
@end

@implementation NNPChargingView
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    NSMutableArray *streams = [NSMutableArray array];
    // Four overlapping strokes per side form a soft tail and a bright head.
    for (NSUInteger side = 0; side < 2; side++) {
        for (NSUInteger band = 0; band < 4; band++) {
            CAShapeLayer *stroke = [CAShapeLayer layer];
            stroke.fillColor = UIColor.clearColor.CGColor;
            stroke.strokeColor = [UIColor colorWithRed:0.25 + band * 0.19
                                                green:1.0 blue:0.70 + band * 0.09
                                                alpha:0.20 + band * 0.23].CGColor;
            stroke.lineWidth = band == 3 ? 2.5 : 3.5;
            stroke.lineCap = kCALineCapRound;
            stroke.lineJoin = kCALineJoinRound;
            stroke.strokeEnd = 0;
            [self.layer addSublayer:stroke];
            [streams addObject:stroke];
        }
    }
    self.streams = streams;
    return self;
}
- (UIBezierPath *)leftPath {
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    CGFloat inset = 4.0;
    CGFloat radius = MIN(38.0, MIN(width, height) * 0.10);
    CGFloat left = inset, right = width - inset, top = inset, bottom = height - inset;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(width / 2.0, bottom)];
    [path addLineToPoint:CGPointMake(left + radius, bottom)];
    [path addArcWithCenter:CGPointMake(left + radius, bottom - radius) radius:radius
               startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
    [path addLineToPoint:CGPointMake(left, top + radius)];
    [path addArcWithCenter:CGPointMake(left + radius, top + radius) radius:radius
               startAngle:M_PI endAngle:3.0 * M_PI_2 clockwise:YES];
    // End beside the notch instead of drawing across its sensor cutout.
    [path addLineToPoint:CGPointMake(MIN(right - radius, width * 0.25), top)];
    return path;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (CGRectIsEmpty(self.bounds)) return;
    UIBezierPath *left = [self leftPath];
    UIBezierPath *right = [left copy];
    [right applyTransform:CGAffineTransformMake(-1, 0, 0, 1, CGRectGetWidth(self.bounds), 0)];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger index = 0; index < self.streams.count; index++) {
        CAShapeLayer *stroke = self.streams[index];
        stroke.frame = self.bounds;
        stroke.path = index < 4 ? left.CGPath : right.CGPath;
    }
    [CATransaction commit];
}
- (void)setRunning:(BOOL)running reducedMotion:(BOOL)reducedMotion {
    if (_running == running && _reducedMotion == reducedMotion) return;
    _running = running;
    _reducedMotion = reducedMotion;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CFTimeInterval beginTime = CACurrentMediaTime();
    for (NSUInteger index = 0; index < self.streams.count; index++) {
        CAShapeLayer *stroke = self.streams[index];
        [stroke removeAllAnimations];
        stroke.strokeStart = 0;
        stroke.strokeEnd = running && reducedMotion ? self.batteryProgress : 0;
        stroke.opacity = reducedMotion ? 0.45 : 1.0;
        if (!running || reducedMotion) continue;
        NSUInteger band = index % 4;
        CGFloat tailLength = MIN(0.16, self.batteryProgress * 0.4) * (1.0 - band * 0.28125);
        NSMutableArray *starts = [NSMutableArray array], *ends = [NSMutableArray array];
        // The head travels beyond the endpoint so the tail drains naturally.
        for (NSUInteger sample = 0; sample <= 60; sample++) {
            CGFloat head = (CGFloat)sample / 60.0 * (self.batteryProgress + MIN(0.16, self.batteryProgress * 0.4));
            [starts addObject:@(MAX(0.0, MIN(self.batteryProgress, head - tailLength)))];
            [ends addObject:@(MIN(self.batteryProgress, head))];
        }
        CAKeyframeAnimation *start = [CAKeyframeAnimation animationWithKeyPath:@"strokeStart"];
        start.values = starts;
        start.duration = 3.2;
        start.calculationMode = kCAAnimationLinear;
        CAKeyframeAnimation *end = [CAKeyframeAnimation animationWithKeyPath:@"strokeEnd"];
        end.values = ends;
        end.duration = 3.2;
        end.calculationMode = kCAAnimationLinear;
        CAAnimationGroup *flow = [CAAnimationGroup animation];
        flow.animations = @[start, end];
        flow.duration = 3.2;
        flow.repeatCount = HUGE_VALF;
        flow.beginTime = [stroke convertTime:beginTime fromLayer:nil];
        [stroke addAnimation:flow forKey:@"chargingFlow"];
    }
    [CATransaction commit];
}
@end

@interface NNPChargingController ()
@property(nonatomic, strong) NNPChargingView *view;
@property(nonatomic, weak) UIView *aodHost;
@property(nonatomic) BOOL started;
@property(nonatomic) int displayToken;
@property(nonatomic) BOOL screenOn;
@property(nonatomic) BOOL didRecordPresentation;
@property(nonatomic) BOOL recordedVisible;
@property(nonatomic) BOOL recordedAOD;
- (void)refresh;
- (void)readDisplayState;
- (void)releasePresentation;
@end

@implementation NNPChargingController
- (instancetype)init {
    if ((self = [super init])) _displayToken = -1;
    return self;
}
- (void)start {
    if (self.started) return;
    self.started = YES;
    self.displayToken = -1;
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[UIDeviceBatteryStateDidChangeNotification,
                            UIDeviceBatteryLevelDidChangeNotification,
                            UIAccessibilityReduceMotionStatusDidChangeNotification,
                            NNPPreferencesDidChangeNotification,
                            UISceneDidActivateNotification,
                            UISceneDidDisconnectNotification]) {
        [center addObserver:self selector:@selector(statusChanged:) name:name object:nil];
    }
    __weak typeof(self) weakSelf = self;
    int token = -1;
    uint32_t result = notify_register_dispatch("com.apple.iokit.hid.displayStatus", &token,
        dispatch_get_main_queue(), ^(__unused int changedToken) {
            [weakSelf readDisplayState];
            [weakSelf refresh];
        });
    if (result == NOTIFY_STATUS_OK) self.displayToken = token;
    [self readDisplayState];
    [self refresh];
}
- (void)readDisplayState {
    uint64_t state = 0;
    // Unknown display state is hidden; this observer never wakes the panel.
    self.screenOn = self.displayToken >= 0 &&
        notify_get_state(self.displayToken, &state) == NOTIFY_STATUS_OK && state != 0;
}
- (void)setAodPresentationActive:(BOOL)active {
    if (_aodPresentationActive == active) return;
    _aodPresentationActive = active;
    [self refresh];
}
- (void)statusChanged:(__unused NSNotification *)notification {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
        return;
    }
    [self refresh];
}
- (void)setAODPresentationHost:(UIView *)host {
    self.aodHost = host;
    [self refresh];
}
- (void)refresh {
    if (!self.started) return;
    UIDevice *device = UIDevice.currentDevice;
    NNPPreferences *preferences = NNPPreferences.sharedPreferences;
    float level = device.batteryLevel;
    BOOL visible = NNPChargingPresentsFlow(preferences.enabled, preferences.chargingAnimationEnabled,
        self.screenOn, self.aodPresentationActive,
        device.batteryState == UIDeviceBatteryStateCharging, level) && self.aodHost.window != nil;
    if (!self.didRecordPresentation || self.recordedVisible != visible ||
        self.recordedAOD != self.aodPresentationActive) {
        self.didRecordPresentation = YES;
        self.recordedVisible = visible;
        self.recordedAOD = self.aodPresentationActive;
        NNPDiagnosticSetBool(@"ChargingFlowVisible", visible);
        NNPDiagnosticSetBool(@"ChargingFlowAODActive", self.aodPresentationActive);
        NNPDiagnosticLogTransition([NSString stringWithFormat:
            @"CHARGING flow visible=%@ aod=%@ screenOn=%@ batteryState=%ld level=%.3f",
            visible ? @"YES" : @"NO", self.aodPresentationActive ? @"YES" : @"NO",
            self.screenOn ? @"YES" : @"NO", (long)device.batteryState, level]);
    }
    if (!visible) {
        [self releasePresentation];
        return;
    }
    UIView *container = self.aodHost;
    if (!self.view) self.view = [[NNPChargingView alloc] initWithFrame:container.bounds];
    if (self.view.superview != container) {
        [self.view setRunning:NO reducedMotion:NO];
        [self.view removeFromSuperview];
        [container addSubview:self.view];
    }
    self.view.frame = container.bounds;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container bringSubviewToFront:self.view];
    NNPDiagnosticSetBool(@"ChargingFlowHostedInCoverSheet", YES);
    NNPDiagnosticSetString(@"ChargingFlowHostClass", NSStringFromClass(container.class));
    NNPDiagnosticSetString(@"ChargingFlowFrame", NSStringFromCGRect(self.view.frame));
    CGFloat progress = MAX(0.0, MIN(1.0, level));
    if (fabs(self.view.batteryProgress - progress) > 0.0001) {
        [self.view setRunning:NO reducedMotion:NO];
        self.view.batteryProgress = progress;
    }
    NNPDiagnosticSetValue(@"ChargingFlowBatteryProgress", @(progress));
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self.view setRunning:YES reducedMotion:UIAccessibilityIsReduceMotionEnabled()];
    NNPDiagnosticSetBool(@"ChargingFlowResourcesAllocated", YES);
}
- (void)releasePresentation {
    [self.view setRunning:NO reducedMotion:NO];
    [self.view removeFromSuperview];
    self.view = nil;
    NNPDiagnosticSetBool(@"ChargingFlowResourcesAllocated", NO);
    NNPDiagnosticSetBool(@"ChargingFlowHostedInCoverSheet", NO);
}
- (void)stop {
    self.started = NO;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (self.displayToken >= 0) notify_cancel(self.displayToken);
    self.displayToken = -1;
    [self releasePresentation];
    self.aodHost = nil;
    // Battery monitoring is shared with NNPView; leave it enabled for that owner.
}
- (void)dealloc { [self stop]; }
@end
