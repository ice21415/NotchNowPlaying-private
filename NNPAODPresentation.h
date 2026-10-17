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

// Pixel shifting alone protects the display; the brief full-surface blank was removed to avoid the flash.
// Kept as a no-op so every call site stays unchanged.
static inline void NNPAODRestPixels(CALayer *layer) {
    (void)layer;
}
