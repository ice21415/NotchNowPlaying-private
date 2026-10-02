#pragma once
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static inline void NNPAODApplyPixelShift(CALayer *layer, CGPoint pixels) {
    UIScreen *screen = UIScreen.mainScreen;
    CGFloat sx = CGRectGetWidth(screen.nativeBounds) / MAX(1.0, CGRectGetWidth(screen.bounds));
    CGFloat sy = CGRectGetHeight(screen.nativeBounds) / MAX(1.0, CGRectGetHeight(screen.bounds));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.sublayerTransform = CATransform3DMakeTranslation(pixels.x / sx, pixels.y / sy, 0);
    [CATransaction commit];
}

// Translation alone leaves the interiors of large solid shapes illuminated.
// Briefly blank the entire plugin surface so these overlapping pixels rest too.
static inline void NNPAODRestPixels(CALayer *layer) {
    if (!layer) return;
    CAKeyframeAnimation *rest = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    rest.values = @[@0, @0, @(layer.opacity)];
    rest.keyTimes = @[@0, @0.7, @1];
    rest.duration = 0.3;
    [layer addAnimation:rest forKey:@"aodPixelRest"];
}
