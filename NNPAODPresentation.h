#pragma once
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>

static inline void NNPAODApplyPixelShift(CALayer *layer, CGPoint pixels) {
    UIScreen *screen = UIScreen.mainScreen;
    CGFloat sx = CGRectGetWidth(screen.nativeBounds) / MAX(1.0, CGRectGetWidth(screen.bounds));
    CGFloat sy = CGRectGetHeight(screen.nativeBounds) / MAX(1.0, CGRectGetHeight(screen.bounds));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.sublayerTransform = CATransform3DMakeTranslation(pixels.x / sx, pixels.y / sy, 0);
    [CATransaction commit];
}

// Translation alone leaves the interiors of large solid shapes lit. Instead of blanking the surface,
// slowly breathe its brightness between 100% and 70% over a four-minute triangle wave. The level is
// derived from the wall clock, so it needs no state, and it is applied only on the existing pixel
// shift tick, so it adds no timer wakeups and no continuous animation.
static inline float NNPAODBreathDimAlpha(double now) {
    double phase = fmod(now / 240.0, 1.0);
    double triangle = phase < 0.5 ? phase * 2.0 : (1.0 - phase) * 2.0;
    return (float)(0.30 * triangle);
}

static inline void NNPAODRestPixels(CALayer *layer) {
    if (!layer) return;
    static NSString *const key = @"nnpAODBreathDim";
    CALayer *dim = nil;
    for (CALayer *sub in layer.sublayers) if ([sub.name isEqualToString:key]) { dim = sub; break; }
    if (!dim) {
        dim = [CALayer layer];
        dim.name = key;
        dim.backgroundColor = UIColor.blackColor.CGColor;
        dim.opacity = 0;
        dim.frame = CGRectMake(-200, -200, 1400, 3000);
        dim.zPosition = 10000;
        [layer addSublayer:dim];
    }
    float target = NNPAODBreathDimAlpha(NSDate.date.timeIntervalSince1970);
    if (UIAccessibilityIsReduceMotionEnabled()) { [CATransaction begin]; [CATransaction setDisableActions:YES]; dim.opacity = target; [CATransaction commit]; return; }
    [CATransaction begin];
    [CATransaction setAnimationDuration:2.0];
    dim.opacity = target;
    [CATransaction commit];
}
