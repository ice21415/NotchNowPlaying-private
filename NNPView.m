#import "NNPView.h"
#import "NNPState.h"
#import "NNPDiagnostics.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

#ifndef NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG
#define NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG 0
#endif
#ifndef NNP_PHASE4A_BUILD_ID
#define NNP_PHASE4A_BUILD_ID "unknown"
#endif
#ifndef NNP_DIAGNOSTIC_UI_MARKER
#define NNP_DIAGNOSTIC_UI_MARKER 0
#endif
#ifndef NNP_DIAGNOSTIC_BUILD_ID
#define NNP_DIAGNOSTIC_BUILD_ID "unknown"
#endif
#ifndef NNP_PHASE4A_UI_STATE_PROBE
#define NNP_PHASE4A_UI_STATE_PROBE 0
#endif
#if NNP_PHASE4A_UI_STATE_PROBE
#import "NNPPhase4AReadOnlyBacklight.h"
#endif

static NSString *const NNPTitleMarqueeAnimationKey = @"nnp.titleMarquee";

static NSString *NNPPlaybackTimeString(NSTimeInterval seconds) {
    NSInteger wholeSeconds = (NSInteger)MAX(0.0, floor(seconds));
    NSInteger hours = wholeSeconds / 3600;
    NSInteger minutes = (wholeSeconds / 60) % 60;
    NSInteger remainder = wholeSeconds % 60;
    if (hours > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)remainder];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(wholeSeconds / 60), (long)remainder];
}

static UIColor *NNPAccentColorForArtwork(UIImage *artwork) {
    CGImageRef image = artwork.CGImage;
    if (!image) return [UIColor colorWithWhite:0.88 alpha:1.0];

    enum { sampleSide = 12 };
    uint8_t pixels[sampleSide * sampleSide * 4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, sampleSide, sampleSide, 8,
        sampleSide * 4, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) return [UIColor colorWithWhite:0.88 alpha:1.0];
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, sampleSide, sampleSide), image);
    CGContextRelease(context);

    double hueX = 0.0, hueY = 0.0, saturationSum = 0.0, totalWeight = 0.0;
    double strongestWeight = 0.0, strongestHue = 0.0;
    for (NSUInteger index = 0; index < sampleSide * sampleSide; index++) {
        const uint8_t *pixel = pixels + index * 4;
        CGFloat alpha = pixel[3] / 255.0;
        if (alpha < 0.35) continue;
        UIColor *color = [UIColor colorWithRed:pixel[0] / 255.0
                                       green:pixel[1] / 255.0
                                        blue:pixel[2] / 255.0 alpha:1.0];
        CGFloat hue = 0.0, saturation = 0.0, brightness = 0.0;
        if (![color getHue:&hue saturation:&saturation brightness:&brightness alpha:NULL] ||
            saturation < 0.2 || brightness < 0.12) continue;
        double weight = saturation * saturation * (0.4 + brightness) * alpha;
        hueX += cos(hue * 2.0 * M_PI) * weight;
        hueY += sin(hue * 2.0 * M_PI) * weight;
        saturationSum += saturation * weight;
        totalWeight += weight;
        if (weight > strongestWeight) { strongestWeight = weight; strongestHue = hue; }
    }
    if (totalWeight < 0.01) return [UIColor colorWithWhite:0.88 alpha:1.0];
    CGFloat hue = hypot(hueX, hueY) < totalWeight * 0.12 ? strongestHue : atan2(hueY, hueX) / (2.0 * M_PI);
    if (hue < 0.0) hue += 1.0;
    CGFloat saturation = MIN(0.72, MAX(0.38, saturationSum / totalWeight * 0.82));
    return [UIColor colorWithHue:hue saturation:saturation brightness:0.90 alpha:1.0];
}

@interface NNPView ()
@property(nonatomic, strong) UIView *contentContainer;
@property(nonatomic, strong) UIImageView *art;
@property(nonatomic, strong) UIView *titleViewport;
@property(nonatomic, strong) UILabel *title;
@property(nonatomic, strong) UILabel *titleDuplicate;
@property(nonatomic, strong) UILabel *artist;
@property(nonatomic, strong) CAShapeLayer *track;
@property(nonatomic, strong) CAShapeLayer *fill;
@property(nonatomic, strong) UILabel *playbackTime;
@property(nonatomic, strong) UILabel *lyricsLabel;
@property(nonatomic) CGFloat fraction;
@property(nonatomic) CGRect lastNotchRect;
@property(nonatomic) BOOL lastNotchRectPrivate;
@property(nonatomic, copy) NSString *marqueeText;
@property(nonatomic) CGFloat marqueeWidth;
@property(nonatomic) CGFloat marqueeFontSize;
@property(nonatomic) BOOL marqueeReducedMotion;
@property(nonatomic) BOOL marqueeAnimating;
@property(nonatomic, strong) UIImage *accentArtwork;
@property(nonatomic, strong) UIColor *accentColor;
@property(nonatomic, strong) CAShapeLayer *notificationSnakeLayer;
@property(nonatomic, strong) CAShapeLayer *notificationSnakeFinishLayer;
@property(nonatomic) NSUInteger notificationSnakeGeneration;
- (void)updateTitleMarquee;
- (CGRect)notchRectUsingPrivateAPI:(BOOL *)usedPrivateAPI;
- (UIBezierPath *)notificationSnakePath;
- (void)updateNotificationSnakeCounterTransform;
@end

@implementation NNPView

- (void)setPixelShiftPixels:(CGPoint)pixelShiftPixels {
    _pixelShiftPixels = pixelShiftPixels;
    CGFloat scale = MAX(UIScreen.mainScreen.scale, 1.0);
    // Move only player content; the full-screen black mask remains fixed.
    self.layer.sublayerTransform = CATransform3DMakeTranslation(
        pixelShiftPixels.x / scale, pixelShiftPixels.y / scale, 0.0);
    [self updateNotificationSnakeCounterTransform];
}

- (void)updateNotificationSnakeCounterTransform {
    if (!self.notificationSnakeLayer) return;
    CGFloat scale = MAX(UIScreen.mainScreen.scale, 1.0);
    self.notificationSnakeLayer.transform = CATransform3DMakeTranslation(
        -self.pixelShiftPixels.x / scale, -self.pixelShiftPixels.y / scale, 0.0);
}

- (void)setContentOpacity:(CGFloat)contentOpacity {
    _contentOpacity = MIN(1.0, MAX(0.0, contentOpacity));
    self.contentContainer.alpha = _contentOpacity;
}

- (void)stopContentAnimation {
    [self.contentContainer.layer removeAllAnimations];
}

- (void)setPlaybackVisible:(BOOL)playbackVisible {
    if (_playbackVisible == playbackVisible) return;
    _playbackVisible = playbackVisible;
    if (!playbackVisible) {
        [self.titleViewport.layer removeAnimationForKey:NNPTitleMarqueeAnimationKey];
        self.titleViewport.layer.sublayerTransform = CATransform3DIdentity;
        self.marqueeAnimating = NO;
    }
    [self setNeedsLayout];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = NO;
    _contentOpacity = 1.0;
    _contentContainer = [[UIView alloc] initWithFrame:self.bounds];
    _contentContainer.backgroundColor = UIColor.clearColor;
    _contentContainer.userInteractionEnabled = NO;
    _contentContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_contentContainer];

    _art = [UIImageView new];
    _art.contentMode = UIViewContentModeScaleAspectFill;
    _art.clipsToBounds = YES;
    _art.layer.cornerCurve = kCACornerCurveContinuous;
    _art.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    _art.layer.borderWidth = 1.0 / MAX(UIScreen.mainScreen.scale, 1.0);

    _titleViewport = [UIView new];
    _titleViewport.clipsToBounds = YES;
    _titleViewport.isAccessibilityElement = YES;
    _title = [UILabel new];
    _title.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    _title.textColor = [UIColor colorWithWhite:1.0 alpha:0.94];
    _title.lineBreakMode = NSLineBreakByTruncatingTail;
    _title.isAccessibilityElement = NO;
    _titleDuplicate = [UILabel new];
    _titleDuplicate.font = _title.font;
    _titleDuplicate.textColor = _title.textColor;
    _titleDuplicate.hidden = YES;
    _titleDuplicate.isAccessibilityElement = NO;
    [_titleViewport addSubview:_title];
    [_titleViewport addSubview:_titleDuplicate];

    _artist = [UILabel new];
    _artist.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    _artist.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    _artist.lineBreakMode = NSLineBreakByTruncatingTail;

    _track = [CAShapeLayer layer];
    _track.fillColor = UIColor.clearColor.CGColor;
    _track.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    _track.lineCap = kCALineCapRound;
    _track.lineJoin = kCALineJoinRound;
    _fill = [CAShapeLayer layer];
    _fill.fillColor = UIColor.clearColor.CGColor;
    _fill.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.92].CGColor;
    _fill.lineCap = kCALineCapRound;
    _fill.lineJoin = kCALineJoinRound;

    _playbackTime = [UILabel new];
    _playbackTime.font = [UIFont monospacedDigitSystemFontOfSize:10.5 weight:UIFontWeightMedium];
    _playbackTime.textAlignment = NSTextAlignmentCenter;
    _playbackTime.hidden = YES;

    _lyricsLabel = [UILabel new];
    _lyricsLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    _lyricsLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.94];
    _lyricsLabel.textAlignment = NSTextAlignmentCenter;
    _lyricsLabel.numberOfLines = 2;
    _lyricsLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _lyricsLabel.hidden = YES;
    _lyricsLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    _lyricsLabel.shadowOffset = CGSizeMake(0.0, 1.0);

    [_contentContainer addSubview:_art];
    [_contentContainer addSubview:_titleViewport];
    [_contentContainer addSubview:_artist];
    [_contentContainer addSubview:_playbackTime];
    [_contentContainer addSubview:_lyricsLabel];
    [_contentContainer.layer addSublayer:_track];
    [_contentContainer.layer addSublayer:_fill];

    _showArtwork = YES;
    _showArtist = YES;
    _showProgress = YES;
    _showLyrics = YES;
    _artworkSize = 40.0;
    _cornerRadius = 9.0;
    _textSize = 14.0;
    _progressHeight = 3.0;
    _accentColor = [UIColor colorWithWhite:0.88 alpha:1.0];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reduceMotionChanged:)
                                                 name:UIAccessibilityReduceMotionStatusDidChangeNotification
                                               object:nil];
    return self;
}

- (void)reduceMotionChanged:(__unused NSNotification *)notification {
    [self setNeedsLayout];
}

- (CGRect)notchRectUsingPrivateAPI:(BOOL *)usedPrivateAPI {
    CGFloat width = CGRectGetWidth(self.bounds);
    UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
    SEL exclusionSelector = NSSelectorFromString(@"_exclusionArea");
    if ([screen respondsToSelector:exclusionSelector]) {
        id (*getArea)(id, SEL) = (id (*)(id, SEL))[screen methodForSelector:exclusionSelector];
        id area = getArea(screen, exclusionSelector);
        SEL rectSelector = NSSelectorFromString(@"rect");
        if ([area respondsToSelector:rectSelector]) {
            CGRect (*getRect)(id, SEL) = (CGRect (*)(id, SEL))[area methodForSelector:rectSelector];
            CGRect rect = [self convertRect:getRect(area, rectSelector)
                       fromCoordinateSpace:screen.coordinateSpace];
            if (isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
                isfinite(rect.size.width) && isfinite(rect.size.height) &&
                rect.size.width >= 100.0 && rect.size.width <= 260.0 &&
                rect.size.height >= 18.0 && rect.size.height <= 65.0 &&
                fabs(CGRectGetMidX(rect) - width / 2.0) < 20.0 &&
                rect.origin.y >= -5.0 && rect.origin.y < 20.0) {
                if (usedPrivateAPI) *usedPrivateAPI = YES;
                return rect;
            }
        }
    }
    if (usedPrivateAPI) *usedPrivateAPI = NO;
    CGFloat fallbackWidth = MIN(209.0, MAX(140.0, width - 104.0));
    return CGRectMake((width - fallbackWidth) / 2.0, 0.0, fallbackWidth, 30.0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.contentContainer.frame = self.bounds;
    CGFloat width = CGRectGetWidth(self.bounds);
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat side = MAX(12.0, safe.left + 12.0);
    BOOL privateBoundary = NO;
    CGRect notch = [self notchRectUsingPrivateAPI:&privateBoundary];
    if (!CGRectEqualToRect(notch, self.lastNotchRect) || privateBoundary != self.lastNotchRectPrivate) {
        self.lastNotchRect = notch;
        self.lastNotchRectPrivate = privateBoundary;
        NNPDiagnosticSetString(@"NotchBoundarySource", privateBoundary ? @"UIScreen._exclusionArea" : @"iPhone12MiniFallback");
        NNPDiagnosticSetString(@"NotchBoundaryRect", NSStringFromCGRect(notch));
    }
    CGFloat notchLeft = CGRectGetMinX(notch);
    CGFloat notchRight = CGRectGetMaxX(notch);
    CGFloat top = MAX(5.0, CGRectGetMinY(notch) + 5.0);
    CGFloat leftLaneWidth = MAX(28.0, notchLeft - side - 8.0);
    CGFloat artSize = MIN(MAX(28.0, self.artworkSize), leftLaneWidth);
    BOOL artworkVisible = self.showArtwork;
    self.art.hidden = !artworkVisible;
    self.art.frame = CGRectMake(side + (leftLaneWidth - artSize) / 2.0, top, artSize, artSize);
    self.art.layer.cornerRadius = MIN(self.cornerRadius, artSize / 2.0);

    CGFloat textX = notchRight + 10.0;
    CGFloat textWidth = MAX(1.0, width - side - textX);
    BOOL reducedMotion = UIAccessibilityIsReduceMotionEnabled();
    CGFloat titleHeight = reducedMotion ? MAX(34.0, self.textSize * 2.3) : MAX(20.0, self.textSize + 5.0);
    self.title.font = [UIFont systemFontOfSize:self.textSize weight:UIFontWeightSemibold];
    self.titleDuplicate.font = self.title.font;
    self.title.numberOfLines = reducedMotion ? 2 : 1;
    self.titleViewport.frame = CGRectMake(textX, top, textWidth, titleHeight);

    self.artist.hidden = !self.showArtist;
    CGFloat artistTop = CGRectGetMaxY(self.titleViewport.frame) + 1.0;
    self.artist.frame = CGRectMake(textX, artistTop, textWidth, 17.0);

    CGFloat progressHeight = MAX(2.0, self.progressHeight);
    CGFloat pathLeft = notchLeft - 4.5;
    CGFloat pathRight = notchRight + 4.5;
    CGFloat pathTop = MAX(9.0, CGRectGetMinY(notch) + 9.0);
    CGFloat pathBottom = CGRectGetMaxY(notch) + 4.0;
    CGFloat radius = MIN(16.0, (pathBottom - pathTop) * 0.65);
    CGFloat arcControl = radius * 0.55228475;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(pathLeft, pathTop)];
    [path addLineToPoint:CGPointMake(pathLeft, pathBottom - radius)];
    [path addCurveToPoint:CGPointMake(pathLeft + radius, pathBottom)
           controlPoint1:CGPointMake(pathLeft, pathBottom - radius + arcControl)
           controlPoint2:CGPointMake(pathLeft + radius - arcControl, pathBottom)];
    [path addLineToPoint:CGPointMake(pathRight - radius, pathBottom)];
    [path addCurveToPoint:CGPointMake(pathRight, pathBottom - radius)
           controlPoint1:CGPointMake(pathRight - radius + arcControl, pathBottom)
           controlPoint2:CGPointMake(pathRight, pathBottom - radius + arcControl)];
    [path addLineToPoint:CGPointMake(pathRight, pathTop)];
    self.playbackTime.frame = CGRectMake(pathLeft + radius, pathBottom + 3.0,
                                         MAX(1.0, pathRight - pathLeft - radius * 2.0), 15.0);
    CGFloat lyricsTop = CGRectGetMaxY(self.playbackTime.frame) + 5.0;
    self.lyricsLabel.frame = CGRectMake(side, lyricsTop, MAX(1.0, width - side * 2.0), 34.0);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.track.path = path.CGPath;
    self.fill.path = path.CGPath;
    self.track.lineWidth = MAX(1.0, progressHeight * 0.52);
    self.fill.lineWidth = MAX(1.5, progressHeight * 0.78);
    self.fill.strokeEnd = self.fraction;
    if (self.notificationSnakeLayer) {
        self.notificationSnakeLayer.frame = self.bounds;
        self.notificationSnakeLayer.path = [self notificationSnakePath].CGPath;
        [self updateNotificationSnakeCounterTransform];
    }
    if (self.notificationSnakeFinishLayer) {
        self.notificationSnakeFinishLayer.frame = self.bounds;
        CGPathRef reverseTrackPath = self.track.path ? CGPathCreateCopyByReversingPath(self.track.path) : NULL;
        self.notificationSnakeFinishLayer.path = reverseTrackPath;
        if (reverseTrackPath) CGPathRelease(reverseTrackPath);
        self.notificationSnakeFinishLayer.lineWidth = self.track.lineWidth + 2.5;
    }
    [CATransaction commit];
    [self updateTitleMarquee];
}

- (UIBezierPath *)notificationSnakePath {
    CGRect bounds = self.bounds;
    CGRect notch = [self notchRectUsingPrivateAPI:NULL];
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    CGFloat left = 7.0;
    CGFloat right = MAX(left + 40.0, width - 7.0);
    CGFloat top = 7.0;
    CGFloat bottom = MAX(top + 80.0, height - 7.0);
    CGFloat radius = MIN(24.0, MIN((right - left) * 0.12, (bottom - top) * 0.055));
    CGFloat notchLeft = CGRectGetMinX(notch) - 4.5;
    CGFloat notchRight = CGRectGetMaxX(notch) + 4.5;
    CGFloat notchTop = MAX(9.0, CGRectGetMinY(notch) + 9.0);

    UIBezierPath *path = [UIBezierPath bezierPath];
    // Start and end on the actual playback-track endpoints. Leave the top
    // opening across the physical notch instead of drawing a second cap there.
    [path moveToPoint:CGPointMake(notchLeft, notchTop)];
    [path addLineToPoint:CGPointMake(notchLeft, top)];
    [path addLineToPoint:CGPointMake(left + radius, top)];
    [path addQuadCurveToPoint:CGPointMake(left, top + radius) controlPoint:CGPointMake(left, top)];
    [path addLineToPoint:CGPointMake(left, bottom - radius)];
    [path addQuadCurveToPoint:CGPointMake(left + radius, bottom) controlPoint:CGPointMake(left, bottom)];
    [path addLineToPoint:CGPointMake(right - radius, bottom)];
    [path addQuadCurveToPoint:CGPointMake(right, bottom - radius) controlPoint:CGPointMake(right, bottom)];
    [path addLineToPoint:CGPointMake(right, top + radius)];
    [path addQuadCurveToPoint:CGPointMake(right - radius, top) controlPoint:CGPointMake(right, top)];
    [path addLineToPoint:CGPointMake(notchRight, top)];
    [path addLineToPoint:CGPointMake(notchRight, notchTop)];
    return path;
}

- (BOOL)playNotificationSnakeAnimation {
    if (![NSThread isMainThread] || !self.window || CGRectIsEmpty(self.bounds)) return NO;
    if (!self.track.path) [self layoutIfNeeded];
    if (!self.track.path) return NO;
    if (!self.notificationSnakeLayer) {
        self.notificationSnakeLayer = [CAShapeLayer layer];
        self.notificationSnakeLayer.fillColor = UIColor.clearColor.CGColor;
        self.notificationSnakeLayer.lineCap = kCALineCapRound;
        self.notificationSnakeLayer.lineJoin = kCALineJoinRound;
        self.notificationSnakeLayer.contentsScale = MAX(UIScreen.mainScreen.scale, 1.0);
        [self.layer addSublayer:self.notificationSnakeLayer];
    }
    if (!self.notificationSnakeFinishLayer) {
        self.notificationSnakeFinishLayer = [CAShapeLayer layer];
        self.notificationSnakeFinishLayer.fillColor = UIColor.clearColor.CGColor;
        self.notificationSnakeFinishLayer.lineCap = kCALineCapRound;
        self.notificationSnakeFinishLayer.lineJoin = kCALineJoinRound;
        self.notificationSnakeFinishLayer.contentsScale = MAX(UIScreen.mainScreen.scale, 1.0);
        [self.layer addSublayer:self.notificationSnakeFinishLayer];
    }

    CAShapeLayer *snake = self.notificationSnakeLayer;
    CAShapeLayer *finish = self.notificationSnakeFinishLayer;
    NSUInteger generation = ++self.notificationSnakeGeneration;
    [snake removeAllAnimations];
    [finish removeAllAnimations];
    snake.frame = self.bounds;
    snake.path = [self notificationSnakePath].CGPath;
    snake.lineWidth = 6.5;
    snake.strokeColor = self.accentColor.CGColor;
    snake.shadowColor = self.accentColor.CGColor;
    snake.shadowOpacity = 1.0;
    snake.shadowRadius = 16.0;
    snake.shadowOffset = CGSizeZero;
    snake.opacity = 1.0;
    finish.frame = self.bounds;
    CGPathRef reverseTrackPath = CGPathCreateCopyByReversingPath(self.track.path);
    finish.path = reverseTrackPath;
    if (reverseTrackPath) CGPathRelease(reverseTrackPath);
    finish.lineWidth = self.track.lineWidth + 2.5;
    finish.strokeColor = self.accentColor.CGColor;
    finish.shadowColor = self.accentColor.CGColor;
    finish.shadowOpacity = 1.0;
    finish.shadowRadius = 14.0;
    finish.shadowOffset = CGSizeZero;
    finish.strokeStart = 0.0;
    finish.strokeEnd = 0.0;
    finish.opacity = 0.0;
    finish.hidden = NO;
    [self updateNotificationSnakeCounterTransform];

    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    NSTimeInterval duration = 2.2;
    if (reduceMotion) {
        snake.hidden = YES;
        finish.strokeEnd = 1.0;
        finish.opacity = 0.94;
        snake.strokeStart = 0.0;
        snake.strokeEnd = 1.0;
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
        pulse.fromValue = @0.45;
        pulse.toValue = @0.94;
        pulse.duration = 0.45;
        pulse.autoreverses = YES;
        pulse.repeatCount = 2.0;
        pulse.removedOnCompletion = NO;
        pulse.fillMode = kCAFillModeForwards;
        [finish addAnimation:pulse forKey:@"nnp.notificationSnakeFinishPulse"];
    } else {
        snake.hidden = NO;
        finish.hidden = NO;
        snake.strokeStart = 0.0;
        snake.strokeEnd = 0.10;
        CABasicAnimation *tail = [CABasicAnimation animationWithKeyPath:@"strokeStart"];
        tail.fromValue = @0.0;
        tail.toValue = @0.90;
        tail.duration = duration;
        tail.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        CABasicAnimation *head = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
        head.fromValue = @0.10;
        head.toValue = @1.0;
        head.duration = duration;
        head.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        CAAnimationGroup *laps = [CAAnimationGroup animation];
        laps.animations = @[tail, head];
        laps.duration = duration;
        laps.repeatCount = 2.0;
        laps.removedOnCompletion = NO;
        laps.fillMode = kCAFillModeForwards;
        [snake addAnimation:laps forKey:@"nnp.notificationSnakeLaps"];

        CABasicAnimation *glowPulse = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
        glowPulse.fromValue = @0.58;
        glowPulse.toValue = @1.0;
        glowPulse.duration = 0.55;
        glowPulse.autoreverses = YES;
        glowPulse.repeatCount = 4.0;
        glowPulse.removedOnCompletion = NO;
        glowPulse.fillMode = kCAFillModeForwards;
        [snake addAnimation:glowPulse forKey:@"nnp.notificationSnakeGlowPulse"];

        NSTimeInterval finishDuration = 1.0;
        CABasicAnimation *notchTrace = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
        notchTrace.fromValue = @0.0;
        notchTrace.toValue = @1.0;
        notchTrace.duration = finishDuration;
        notchTrace.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

        CAKeyframeAnimation *finishGlow = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        finishGlow.values = @[@0.0, @1.0, @1.0, @0.0];
        finishGlow.keyTimes = @[@0.0, @0.08, @0.82, @1.0];
        finishGlow.duration = finishDuration;

        CAAnimationGroup *notchFinish = [CAAnimationGroup animation];
        notchFinish.animations = @[notchTrace, finishGlow];
        notchFinish.duration = finishDuration;
        notchFinish.beginTime = CACurrentMediaTime() + duration * 2.0;
        notchFinish.removedOnCompletion = NO;
        notchFinish.fillMode = kCAFillModeBoth;
        [finish addAnimation:notchFinish forKey:@"nnp.notificationSnakeNotchFinish"];

        CABasicAnimation *edgeFade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        edgeFade.fromValue = @1.0;
        edgeFade.toValue = @0.08;
        edgeFade.duration = 0.22;
        edgeFade.beginTime = CACurrentMediaTime() + duration * 2.0;
        edgeFade.removedOnCompletion = NO;
        edgeFade.fillMode = kCAFillModeBoth;
        [snake addAnimation:edgeFade forKey:@"nnp.notificationSnakeEdgeFade"];
    }

    NSTimeInterval cleanupDelay = duration * (reduceMotion ? 1.0 : 2.0) + (reduceMotion ? 0.15 : 1.15);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(cleanupDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != self.notificationSnakeGeneration) return;
        [snake removeAllAnimations];
        [finish removeAllAnimations];
        snake.hidden = YES;
        snake.opacity = 0.0;
        snake.strokeStart = 0.0;
        snake.strokeEnd = 0.0;
        finish.hidden = YES;
        finish.opacity = 0.0;
        finish.strokeStart = 0.0;
        finish.strokeEnd = 0.0;
    });
    return YES;
}

- (void)updateTitleMarquee {
    NSString *text = self.title.text ?: @"";
    CGFloat viewportWidth = CGRectGetWidth(self.titleViewport.bounds);
    BOOL reducedMotion = UIAccessibilityIsReduceMotionEnabled();
    CGFloat naturalWidth = ceil([text sizeWithAttributes:@{ NSFontAttributeName: self.title.font }].width) + 2.0;
    BOOL animate = self.playbackVisible && self.window && !reducedMotion &&
        viewportWidth > 1.0 && naturalWidth > viewportWidth + 2.0;
    BOOL changed = ![self.marqueeText isEqualToString:text] ||
        fabs(self.marqueeWidth - viewportWidth) > 0.5 ||
        fabs(self.marqueeFontSize - self.textSize) > 0.01 ||
        self.marqueeReducedMotion != reducedMotion ||
        self.marqueeAnimating != animate;
    if (!changed) return;

    self.marqueeText = text;
    self.marqueeWidth = viewportWidth;
    self.marqueeFontSize = self.textSize;
    self.marqueeReducedMotion = reducedMotion;
    self.marqueeAnimating = animate;
    [self.titleViewport.layer removeAnimationForKey:NNPTitleMarqueeAnimationKey];
    self.titleViewport.layer.sublayerTransform = CATransform3DIdentity;
    self.titleViewport.accessibilityLabel = text;

    if (reducedMotion) {
        self.title.frame = self.titleViewport.bounds;
        self.titleDuplicate.hidden = YES;
        return;
    }

    CGFloat labelWidth = animate ? naturalWidth : viewportWidth;
    self.title.frame = CGRectMake(0.0, 0.0, labelWidth, CGRectGetHeight(self.titleViewport.bounds));
    self.titleDuplicate.hidden = !animate;
    if (!animate) return;

    // A duplicate title makes the jump back to the first frame invisible.
    CGFloat repeatDistance = naturalWidth + 30.0;
    self.titleDuplicate.text = text;
    self.titleDuplicate.frame = CGRectMake(repeatDistance, 0.0, naturalWidth,
                                           CGRectGetHeight(self.titleViewport.bounds));
    NSTimeInterval pause = 1.4;
    NSTimeInterval travel = repeatDistance / 30.0;
    NSTimeInterval duration = pause + travel;
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"sublayerTransform"];
    animation.values = @[
        [NSValue valueWithCATransform3D:CATransform3DIdentity],
        [NSValue valueWithCATransform3D:CATransform3DIdentity],
        [NSValue valueWithCATransform3D:CATransform3DMakeTranslation(-repeatDistance, 0.0, 0.0)]
    ];
    animation.keyTimes = @[ @0.0, @(pause / duration), @1.0 ];
    animation.calculationMode = kCAAnimationLinear;
    animation.duration = duration;
    animation.repeatCount = HUGE_VALF;
    [self.titleViewport.layer addAnimation:animation forKey:NNPTitleMarqueeAnimationKey];
}

- (void)updateState:(NNPState *)state {
    NSString *title = state.title.length ? state.title : @"Not Playing";
#if NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG
    title = [NSString stringWithFormat:@"[P4A-%@] %@", @NNP_PHASE4A_BUILD_ID, title];
#elif NNP_DIAGNOSTIC_UI_MARKER
    title = [NSString stringWithFormat:@"[DIAG-%@] %@", @NNP_DIAGNOSTIC_BUILD_ID, title];
#elif NNP_PHASE4A_UI_STATE_PROBE
    title = [NSString stringWithFormat:@"[%@] %@", NNPPhase4AUIStateMarker(), title];
#endif
    if (![self.title.text isEqualToString:title]) self.title.text = title;
    self.artist.text = state.artist.length ? state.artist : (state.album ?: @"");
    UIImage *artwork = state.artwork;
    if (self.accentArtwork != artwork) {
        self.accentArtwork = artwork;
        self.accentColor = NNPAccentColorForArtwork(artwork);
        self.art.layer.borderColor = [self.accentColor colorWithAlphaComponent:0.38].CGColor;
        self.artist.textColor = [self.accentColor colorWithAlphaComponent:0.82];
        self.track.strokeColor = [self.accentColor colorWithAlphaComponent:0.17].CGColor;
        self.fill.strokeColor = [self.accentColor colorWithAlphaComponent:0.94].CGColor;
    }
    self.art.image = artwork ?: [UIImage systemImageNamed:@"music.note"];
    self.art.contentMode = artwork ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
    self.art.backgroundColor = artwork ? UIColor.clearColor : [UIColor colorWithWhite:1.0 alpha:0.11];
    self.art.tintColor = [UIColor colorWithWhite:1.0 alpha:0.7];
    [self setNeedsLayout];
}

- (void)updateElapsed:(NSTimeInterval)elapsed duration:(NSTimeInterval)duration playing:(BOOL)playing {
    BOOL valid = duration > 0.0 && isfinite(duration);
    self.track.hidden = self.fill.hidden = !valid || !self.showProgress;
    self.playbackTime.hidden = !valid || !self.showProgress;
    if (!valid) return;
    elapsed = MIN(duration, MAX(0.0, elapsed));
    NSString *played = NNPPlaybackTimeString(elapsed);
    NSString *remaining = [@"−" stringByAppendingString:NNPPlaybackTimeString(ceil(duration - elapsed))];
    NSString *display = [NSString stringWithFormat:@"%@  ·  %@", played, remaining];
    NSMutableAttributedString *styled = [[NSMutableAttributedString alloc] initWithString:display
        attributes:@{ NSFontAttributeName: self.playbackTime.font,
                      NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.9] }];
    [styled addAttribute:NSForegroundColorAttributeName
                   value:[self.accentColor colorWithAlphaComponent:0.95]
                   range:NSMakeRange(0, played.length)];
    [styled addAttribute:NSForegroundColorAttributeName
                   value:[UIColor colorWithWhite:1.0 alpha:0.48]
                   range:NSMakeRange(played.length, display.length - played.length)];
    self.playbackTime.attributedText = styled;
    self.playbackTime.accessibilityLabel = [NSString stringWithFormat:@"已播放 %@，剩餘 %@", played, remaining];
    self.fraction = elapsed / duration;
    self.fill.opacity = playing ? 1.0 : 0.55;
    [self setNeedsLayout];
}

- (void)updateLyricsText:(NSString *)currentLine nextLine:(NSString *)nextLine {
    NSString *current = [currentLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSString *next = [nextLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSString *text = current.length && next.length && ![current isEqualToString:next]
        ? [NSString stringWithFormat:@"%@\n%@", current, next] : current;
    NSMutableAttributedString *styledText = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.92]
    }];
    if (current.length) {
        [styledText addAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:12.5 weight:UIFontWeightBold],
            NSForegroundColorAttributeName: [self.accentColor colorWithAlphaComponent:1.0]
        } range:NSMakeRange(0, current.length)];
    }
    if (next.length && text.length > current.length) {
        [styledText addAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.48]
        } range:NSMakeRange(current.length + 1, next.length)];
    }
    BOOL visible = self.showLyrics && text.length > 0;
    BOOL textChanged = ![self.lyricsLabel.text isEqualToString:text];
    BOOL styleChanged = ![self.lyricsLabel.attributedText isEqualToAttributedString:styledText];
    if (textChanged) {
        [UIView transitionWithView:self.lyricsLabel duration:0.18 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionBeginFromCurrentState animations:^{
            self.lyricsLabel.attributedText = styledText;
        } completion:nil];
    } else if (styleChanged) {
        self.lyricsLabel.attributedText = styledText;
    }
    self.lyricsLabel.hidden = !visible;
    self.lyricsLabel.accessibilityLabel = text;
    [self setNeedsLayout];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
