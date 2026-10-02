#import "NNPAODPresentation.h"
#import "NNPView.h"
#import "NNPState.h"
#import "NNPDiagnostics.h"
#import "NNPAODPowerPolicy.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

#ifndef NNP_NOTIFICATION_SNAKE_GEOMETRY_DIAGNOSTICS
#define NNP_NOTIFICATION_SNAKE_GEOMETRY_DIAGNOSTICS 0
#endif

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
static const CGFloat NNPNotificationSnakeLineWidth = 6.5;

static void NNPAddPlaybackTrackSegments(UIBezierPath *path, CGRect notch, BOOL reversed, BOOL connectToCurrentPoint) {
    CGFloat pathLeft = CGRectGetMinX(notch) - 4.5;
    CGFloat pathRight = CGRectGetMaxX(notch) + 4.5;
    CGFloat pathTop = MAX(9.0, CGRectGetMinY(notch) + 9.0);
    CGFloat pathBottom = CGRectGetMaxY(notch) + 4.0;
    CGFloat radius = MIN(16.0, (pathBottom - pathTop) * 0.65);
    CGFloat arcControl = radius * 0.55228475;

    if (reversed) {
        CGPoint start = CGPointMake(pathRight, pathTop);
        if (connectToCurrentPoint) [path addLineToPoint:start];
        else [path moveToPoint:start];
        [path addLineToPoint:CGPointMake(pathRight, pathBottom - radius)];
        [path addCurveToPoint:CGPointMake(pathRight - radius, pathBottom)
               controlPoint1:CGPointMake(pathRight, pathBottom - radius + arcControl)
               controlPoint2:CGPointMake(pathRight - radius + arcControl, pathBottom)];
        [path addLineToPoint:CGPointMake(pathLeft + radius, pathBottom)];
        [path addCurveToPoint:CGPointMake(pathLeft, pathBottom - radius)
               controlPoint1:CGPointMake(pathLeft + radius - arcControl, pathBottom)
               controlPoint2:CGPointMake(pathLeft, pathBottom - radius + arcControl)];
        [path addLineToPoint:CGPointMake(pathLeft, pathTop)];
    } else {
        CGPoint start = CGPointMake(pathLeft, pathTop);
        if (connectToCurrentPoint) [path addLineToPoint:start];
        else [path moveToPoint:start];
        [path addLineToPoint:CGPointMake(pathLeft, pathBottom - radius)];
        [path addCurveToPoint:CGPointMake(pathLeft + radius, pathBottom)
               controlPoint1:CGPointMake(pathLeft, pathBottom - radius + arcControl)
               controlPoint2:CGPointMake(pathLeft + radius - arcControl, pathBottom)];
        [path addLineToPoint:CGPointMake(pathRight - radius, pathBottom)];
        [path addCurveToPoint:CGPointMake(pathRight, pathBottom - radius)
               controlPoint1:CGPointMake(pathRight - radius + arcControl, pathBottom)
               controlPoint2:CGPointMake(pathRight, pathBottom - radius + arcControl)];
        [path addLineToPoint:CGPointMake(pathRight, pathTop)];
    }
}

static UIBezierPath *NNPPlaybackTrackPath(CGRect notch, BOOL reversed) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    NNPAddPlaybackTrackSegments(path, notch, reversed, NO);
    return path;
}

static UIBezierPath *NNPNotificationSnakeFinishPath(CGRect notch) {
    // The perimeter returns to the left playback-track endpoint.
    return NNPPlaybackTrackPath(notch, NO);
}

#if NNP_NOTIFICATION_SNAKE_GEOMETRY_DIAGNOSTICS
static UIBezierPath *NNPNotificationSnakeCornerMarkersPath(CGRect notch) {
    CGFloat pathLeft = CGRectGetMinX(notch) - 4.5;
    CGFloat pathRight = CGRectGetMaxX(notch) + 4.5;
    CGFloat pathTop = MAX(9.0, CGRectGetMinY(notch) + 9.0);
    CGFloat pathBottom = CGRectGetMaxY(notch) + 4.0;
    CGFloat radius = MIN(16.0, (pathBottom - pathTop) * 0.65);
    CGFloat markerRadius = 2.5;
    CGPoint points[] = {
        CGPointMake(pathLeft, pathTop),
        CGPointMake(pathLeft, pathBottom - radius),
        CGPointMake(pathLeft + radius, pathBottom),
        CGPointMake(pathRight - radius, pathBottom),
        CGPointMake(pathRight, pathBottom - radius),
        CGPointMake(pathRight, pathTop),
    };
    UIBezierPath *markers = [UIBezierPath bezierPath];
    for (NSUInteger index = 0; index < sizeof(points) / sizeof(points[0]); index++) {
        CGRect markerRect = CGRectMake(points[index].x - markerRadius,
                                       points[index].y - markerRadius,
                                       markerRadius * 2.0,
                                       markerRadius * 2.0);
        [markers appendPath:[UIBezierPath bezierPathWithOvalInRect:markerRect]];
    }
    return markers;
}
#endif

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
@property(nonatomic, strong) UILabel *clockLabel;
@property(nonatomic, copy) NSString *lastClockDisplay;
@property(nonatomic) NSInteger lastClockMinute;
@property(nonatomic, strong) UIView *batteryStatus;
@property(nonatomic, strong) UIImageView *batteryIcon;
@property(nonatomic, strong) UILabel *batteryPercentage;
@property(nonatomic, strong) UIImageView *batteryChargingIcon;
@property(nonatomic) BOOL batteryStatusAvailable;
@property(nonatomic) NSInteger batteryPercentageValue;
@property(nonatomic) UIDeviceBatteryState batteryState;
@property(nonatomic, strong) CAShapeLayer *track;
@property(nonatomic, strong) CAShapeLayer *fill;
@property(nonatomic, strong) UILabel *playbackTime;
@property(nonatomic, strong) UILabel *lyricsLabel;
@property(nonatomic, copy) NSString *lastPlaybackTimeDisplay;
@property(nonatomic, copy) NSString *lastLyricsCurrentLine;
@property(nonatomic, copy) NSString *lastLyricsNextLine;
@property(nonatomic) CGFloat fraction;
@property(nonatomic) CGRect lastNotchRect;
@property(nonatomic) BOOL lastNotchRectPrivate;
@property(nonatomic, copy) NSString *marqueeText;
@property(nonatomic) CGFloat marqueeWidth;
@property(nonatomic) CGFloat marqueeFontSize;
@property(nonatomic) BOOL marqueeReducedMotion;
@property(nonatomic) BOOL marqueeAnimating;
@property(nonatomic, strong) NSTimer *marqueeIdleTimer;
@property(nonatomic) NSUInteger marqueeGeneration;
@property(nonatomic, strong) UIImage *accentArtwork;
@property(nonatomic, strong) UIColor *accentColor;
@property(nonatomic, strong) CAShapeLayer *notificationSnakeLayer;
@property(nonatomic, strong) CAShapeLayer *notificationSnakeFinishLayer;
@property(nonatomic, strong) UIView *notificationCard;
@property(nonatomic, strong) UIImageView *notificationCardIcon;
@property(nonatomic, strong) UILabel *notificationCardAppName;
@property(nonatomic, strong) UILabel *notificationCardTitle;
@property(nonatomic, strong) UILabel *notificationCardMessage;
@property(nonatomic) BOOL notificationCardActive;
@property(nonatomic, strong) UIView *notificationIndicatorStrip;
@property(nonatomic, strong) NSArray<UIImageView *> *notificationIndicatorImageViews;
@property(nonatomic, strong) UIView *notificationIndicatorOverflow;
@property(nonatomic, strong) UILabel *notificationIndicatorOverflowLabel;
@property(nonatomic, strong) NSMutableArray<UIImage *> *notificationIndicatorImages;
@property(nonatomic) NSUInteger notificationIndicatorCount;
#if NNP_NOTIFICATION_SNAKE_GEOMETRY_DIAGNOSTICS
@property(nonatomic, strong) CAShapeLayer *notificationSnakeDebugGuideLayer;
@property(nonatomic, strong) CAShapeLayer *notificationSnakeDebugMarkersLayer;
#endif
@property(nonatomic) NSUInteger notificationSnakeGeneration;
- (void)updateTitleMarquee;
- (void)stopTitleMarqueeCycle;
- (void)scheduleTitleMarqueeCycleAfter:(NSTimeInterval)delay;
- (void)startTitleMarqueeCycle;
- (void)titleMarqueeAnimationStopped:(BOOL)finished generation:(NSUInteger)generation;
- (CGRect)notchRectUsingPrivateAPI:(BOOL *)usedPrivateAPI;
- (UIBezierPath *)notificationSnakePath;
- (void)updateNotificationSnakeCounterTransform;
- (BOOL)presentNotificationCardWithPayload:(NSDictionary *)payload generation:(NSUInteger)generation;
- (void)finishNotificationCardForGeneration:(NSUInteger)generation;
- (void)recordNotificationIndicatorForPayload:(NSDictionary *)payload;
- (void)batteryStatusDidChange:(NSNotification *)notification;
- (void)updateBatteryStatus;
- (void)updateClock;
@end

@interface NNPTitleMarqueeDelegate : NSObject <CAAnimationDelegate>
@property(nonatomic, weak) NNPView *view;
@property(nonatomic) NSUInteger generation;
@end

@implementation NNPTitleMarqueeDelegate
- (void)animationDidStop:(__unused CAAnimation *)animation finished:(BOOL)finished {
    [self.view titleMarqueeAnimationStopped:finished generation:self.generation];
}
@end

@implementation NNPView

- (void)setPixelShiftPixels:(CGPoint)pixelShiftPixels {
    _pixelShiftPixels = pixelShiftPixels;
    // Shift every descendant: artwork, text, progress, cards and notification layers.
    NNPAODApplyPixelShift(self.layer, pixelShiftPixels);
    [self updateNotificationSnakeCounterTransform];
}

- (void)updateNotificationSnakeCounterTransform {
    if (!self.notificationSnakeLayer) return;
    self.notificationSnakeLayer.transform = CATransform3DIdentity;
}

- (void)setContentOpacity:(CGFloat)contentOpacity {
    _contentOpacity = MIN(1.0, MAX(0.0, contentOpacity));
    if (!self.notificationCardActive) self.contentContainer.alpha = _contentOpacity;
}

- (void)stopContentAnimation {
    [self.contentContainer.layer removeAllAnimations];
}

- (void)setPlaybackVisible:(BOOL)playbackVisible {
    if (_playbackVisible == playbackVisible) return;
    _playbackVisible = playbackVisible;
    if (!playbackVisible) {
        [self stopTitleMarqueeCycle];
        self.marqueeAnimating = NO;
    }
    [self setNeedsLayout];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateTitleMarquee];
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

    _clockLabel = [UILabel new];
    _clockLabel.font = [UIFont monospacedDigitSystemFontOfSize:10.0 weight:UIFontWeightMedium];
    _clockLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    _clockLabel.hidden = YES;
    _clockLabel.accessibilityTraits = UIAccessibilityTraitStaticText;

    _batteryStatus = [UIView new];
    _batteryStatus.backgroundColor = UIColor.clearColor;
    _batteryStatus.userInteractionEnabled = NO;
    _batteryStatus.hidden = YES;
    _batteryStatus.isAccessibilityElement = YES;
    _batteryIcon = [UIImageView new];
    _batteryIcon.contentMode = UIViewContentModeScaleAspectFit;
    _batteryIcon.tintColor = [UIColor colorWithWhite:1.0 alpha:0.78];
    _batteryPercentage = [UILabel new];
    _batteryPercentage.font = [UIFont monospacedDigitSystemFontOfSize:10.0 weight:UIFontWeightMedium];
    _batteryPercentage.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    _batteryChargingIcon = [UIImageView new];
    _batteryChargingIcon.contentMode = UIViewContentModeScaleAspectFit;
    _batteryChargingIcon.tintColor = UIColor.systemYellowColor;
    _batteryChargingIcon.hidden = YES;
    [_batteryStatus addSubview:_batteryIcon];
    [_batteryStatus addSubview:_batteryPercentage];
    [_batteryStatus addSubview:_batteryChargingIcon];

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

    _notificationIndicatorImages = [NSMutableArray array];
    _notificationIndicatorStrip = [UIView new];
    _notificationIndicatorStrip.backgroundColor = UIColor.clearColor;
    _notificationIndicatorStrip.userInteractionEnabled = NO;
    _notificationIndicatorStrip.hidden = YES;
    NSMutableArray<UIImageView *> *indicatorViews = [NSMutableArray arrayWithCapacity:3];
    for (NSUInteger index = 0; index < 3; index++) {
        UIImageView *iconView = [UIImageView new];
        iconView.contentMode = UIViewContentModeScaleAspectFill;
        iconView.clipsToBounds = YES;
        iconView.layer.cornerRadius = 3.0;
        iconView.layer.borderWidth = 0.5 / MAX(UIScreen.mainScreen.scale, 1.0);
        iconView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
        iconView.hidden = YES;
        [_notificationIndicatorStrip addSubview:iconView];
        [indicatorViews addObject:iconView];
    }
    _notificationIndicatorImageViews = [indicatorViews copy];
    _notificationIndicatorOverflow = [UIView new];
    _notificationIndicatorOverflow.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
    _notificationIndicatorOverflow.layer.cornerRadius = 6.0;
    _notificationIndicatorOverflow.hidden = YES;
    _notificationIndicatorOverflowLabel = [UILabel new];
    _notificationIndicatorOverflowLabel.font = [UIFont systemFontOfSize:8.0 weight:UIFontWeightSemibold];
    _notificationIndicatorOverflowLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.96];
    _notificationIndicatorOverflowLabel.textAlignment = NSTextAlignmentCenter;
    [_notificationIndicatorOverflow addSubview:_notificationIndicatorOverflowLabel];
    [_notificationIndicatorStrip addSubview:_notificationIndicatorOverflow];

    [_contentContainer addSubview:_art];
    [_contentContainer addSubview:_titleViewport];
    [_contentContainer addSubview:_artist];
    [_contentContainer addSubview:_clockLabel];
    [_contentContainer addSubview:_batteryStatus];
    [_contentContainer addSubview:_playbackTime];
    [_contentContainer addSubview:_lyricsLabel];
    [_contentContainer addSubview:_notificationIndicatorStrip];
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
    UIDevice *device = UIDevice.currentDevice;
    device.batteryMonitoringEnabled = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(batteryStatusDidChange:)
                                                 name:UIDeviceBatteryLevelDidChangeNotification
                                               object:device];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(batteryStatusDidChange:)
                                                 name:UIDeviceBatteryStateDidChangeNotification
                                               object:device];
    [self updateBatteryStatus];
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
    // Leave physical room for the notification outline above the metadata row.
    CGFloat top = MAX(11.0, CGRectGetMinY(notch) + 11.0);
    CGFloat leftLaneWidth = MAX(28.0, notchLeft - side - 8.0);
    CGFloat artSize = MIN(MAX(28.0, self.artworkSize), leftLaneWidth);
    BOOL artworkVisible = self.showArtwork;
    self.art.hidden = !artworkVisible;
    self.art.frame = CGRectMake(side + (leftLaneWidth - artSize) / 2.0, top, artSize, artSize);
    self.art.layer.cornerRadius = MIN(self.cornerRadius, artSize / 2.0);
    CGFloat indicatorTop = CGRectGetMaxY(self.art.frame) + 3.0;
    CGFloat indicatorIconSize = 12.0;
    CGFloat indicatorSpacing = 2.0;
    CGFloat indicatorOverflowWidth = 22.0;
    NSString *overflowText = @"";
    BOOL hasOverflow = self.notificationIndicatorCount > 3;
    NSUInteger visibleIconCount = MIN(hasOverflow ? (NSUInteger)2 : (NSUInteger)3,
                                      self.notificationIndicatorImages.count);
    if (hasOverflow) {
        NSUInteger hiddenCount = self.notificationIndicatorCount - visibleIconCount;
        overflowText = hiddenCount > 99 ? @"+99+" : [NSString stringWithFormat:@"+%lu", (unsigned long)hiddenCount];
        CGFloat labelWidth = ceil([overflowText sizeWithAttributes:@{
            NSFontAttributeName: self.notificationIndicatorOverflowLabel.font
        }].width) + 8.0;
        indicatorOverflowWidth = MAX(20.0, labelWidth);
        while (visibleIconCount > 0) {
            CGFloat proposedWidth = visibleIconCount * indicatorIconSize +
                (visibleIconCount - 1) * indicatorSpacing + indicatorSpacing + indicatorOverflowWidth;
            if (proposedWidth <= leftLaneWidth) break;
            visibleIconCount--;
            NSUInteger adjustedHiddenCount = self.notificationIndicatorCount - visibleIconCount;
            overflowText = adjustedHiddenCount > 99 ? @"+99+" : [NSString stringWithFormat:@"+%lu", (unsigned long)adjustedHiddenCount];
            indicatorOverflowWidth = MAX(20.0, ceil([overflowText sizeWithAttributes:@{
                NSFontAttributeName: self.notificationIndicatorOverflowLabel.font
            }].width) + 8.0);
        }
    }
    CGFloat indicatorWidth = visibleIconCount * indicatorIconSize +
        (visibleIconCount > 0 ? (visibleIconCount - 1) * indicatorSpacing : 0.0);
    if (hasOverflow) indicatorWidth += (visibleIconCount > 0 ? indicatorSpacing : 0.0) + indicatorOverflowWidth;
    CGFloat indicatorX = CGRectGetMidX(self.art.frame) - indicatorWidth / 2.0;
    self.notificationIndicatorStrip.frame = CGRectMake(indicatorX, indicatorTop, indicatorWidth, indicatorIconSize);
    self.notificationIndicatorStrip.hidden = self.notificationIndicatorCount == 0 || !self.showArtwork || !self.playbackVisible;
    for (NSUInteger index = 0; index < self.notificationIndicatorImageViews.count; index++) {
        UIImageView *iconView = self.notificationIndicatorImageViews[index];
        iconView.hidden = index >= visibleIconCount;
        if (index < visibleIconCount) {
            NSUInteger firstVisibleImage = self.notificationIndicatorImages.count - visibleIconCount;
            iconView.image = self.notificationIndicatorImages[firstVisibleImage + index];
            iconView.frame = CGRectMake(index * (indicatorIconSize + indicatorSpacing), 0.0,
                                        indicatorIconSize, indicatorIconSize);
        }
    }
    self.notificationIndicatorOverflow.hidden = !hasOverflow;
    if (hasOverflow) {
        CGFloat overflowX = visibleIconCount * (indicatorIconSize + indicatorSpacing);
        if (visibleIconCount > 0) overflowX -= indicatorSpacing;
        self.notificationIndicatorOverflow.frame = CGRectMake(overflowX, 0.0, indicatorOverflowWidth, indicatorIconSize);
        self.notificationIndicatorOverflowLabel.frame = self.notificationIndicatorOverflow.bounds;
        self.notificationIndicatorOverflowLabel.text = overflowText;
    }

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
    CGFloat clockTop = self.showArtist ? CGRectGetMaxY(self.artist.frame) + 1.0
                                       : CGRectGetMaxY(self.titleViewport.frame) + 2.0;
    self.clockLabel.frame = CGRectMake(textX, clockTop, MIN(76.0, textWidth), 14.0);
    self.clockLabel.hidden = !self.playbackVisible;
    CGFloat batteryTop = CGRectGetMaxY(self.clockLabel.frame) + 1.0;
    self.batteryStatus.frame = CGRectMake(textX, batteryTop, 58.0, 14.0);
    self.batteryStatus.hidden = !self.batteryStatusAvailable || !self.playbackVisible;
    self.batteryIcon.frame = CGRectMake(0.0, 1.0, 14.0, 12.0);
    self.batteryPercentage.frame = CGRectMake(17.0, 0.0, 29.0, 14.0);
    self.batteryChargingIcon.frame = CGRectMake(47.0, 1.0, 9.0, 12.0);

    CGFloat progressHeight = MAX(2.0, self.progressHeight);
    CGFloat pathLeft = notchLeft - 4.5;
    CGFloat pathRight = notchRight + 4.5;
    CGFloat pathTop = MAX(9.0, CGRectGetMinY(notch) + 9.0);
    CGFloat pathBottom = CGRectGetMaxY(notch) + 4.0;
    CGFloat radius = MIN(16.0, (pathBottom - pathTop) * 0.65);
    UIBezierPath *path = NNPPlaybackTrackPath(notch, NO);
    self.playbackTime.frame = CGRectMake(pathLeft + radius, pathBottom + 3.0,
                                         MAX(1.0, pathRight - pathLeft - radius * 2.0), 15.0);
    CGFloat lyricsTop = CGRectGetMaxY(self.playbackTime.frame) + 5.0;
    if (!self.notificationIndicatorStrip.hidden)
        lyricsTop = MAX(lyricsTop, CGRectGetMaxY(self.notificationIndicatorStrip.frame) + 4.0);
    if (!self.clockLabel.hidden)
        lyricsTop = MAX(lyricsTop, CGRectGetMaxY(self.clockLabel.frame) + 4.0);
    if (!self.batteryStatus.hidden)
        lyricsTop = MAX(lyricsTop, CGRectGetMaxY(self.batteryStatus.frame) + 4.0);
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
        self.notificationSnakeFinishLayer.path = NNPNotificationSnakeFinishPath(notch).CGPath;
        self.notificationSnakeFinishLayer.lineWidth = self.track.lineWidth + 2.5;
    }
    if (self.notificationCard) {
        CGFloat cardWidth = MIN(340.0, MAX(1.0, width - 32.0));
        CGFloat cardHeight = 92.0;
        CGFloat cardTop = CGRectGetMaxY(notch) + 16.0;
        if (cardTop + cardHeight > CGRectGetHeight(self.bounds) - 24.0)
            cardTop = MAX(8.0, CGRectGetHeight(self.bounds) * 0.18);
        self.notificationCard.frame = CGRectMake((width - cardWidth) / 2.0, cardTop, cardWidth, cardHeight);
        self.notificationCardIcon.frame = CGRectMake(12.0, 24.0, 44.0, 44.0);
        CGFloat textWidth = MAX(1.0, cardWidth - 80.0);
        self.notificationCardAppName.frame = CGRectMake(68.0, 9.0, textWidth, 14.0);
        self.notificationCardTitle.frame = CGRectMake(68.0, 25.0, textWidth, 19.0);
        self.notificationCardMessage.frame = CGRectMake(68.0, 45.0, textWidth, 38.0);
    }
#if NNP_NOTIFICATION_SNAKE_GEOMETRY_DIAGNOSTICS
    if (self.notificationSnakeDebugGuideLayer) {
        self.notificationSnakeDebugGuideLayer.frame = self.bounds;
        self.notificationSnakeDebugGuideLayer.path = NNPNotificationSnakeFinishPath(notch).CGPath;
    }
    if (self.notificationSnakeDebugMarkersLayer) {
        self.notificationSnakeDebugMarkersLayer.frame = self.bounds;
        self.notificationSnakeDebugMarkersLayer.path = NNPNotificationSnakeCornerMarkersPath(notch).CGPath;
    }
#endif
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
    CGFloat contentTop = CGRectGetMinY(self.titleViewport.frame);
    if (!self.art.hidden) contentTop = MIN(contentTop, CGRectGetMinY(self.art.frame));
    CGFloat topClearance = NNPNotificationSnakeLineWidth * 0.5 + 1.0;
    // Keep the upper perimeter above the cover/title row so it stays visible
    // continuously on both sides of the notch.
    CGFloat top = MAX(1.5, MIN(7.0, contentTop - topClearance));
    CGFloat bottom = MAX(top + 80.0, height - 7.0);
    CGFloat radius = MIN(24.0, MIN((right - left) * 0.12, (bottom - top) * 0.055));
    CGFloat notchLeft = CGRectGetMinX(notch) - 4.5;
    CGFloat notchRight = CGRectGetMaxX(notch) + 4.5;
    CGFloat notchTop = MAX(9.0, CGRectGetMinY(notch) + 9.0);

    UIBezierPath *path = [UIBezierPath bezierPath];
    // Run around the display, then return to the start along the exact playback
    // U so each lap is closed and the head never jumps across the notch.
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
    NNPAddPlaybackTrackSegments(path, notch, YES, YES);
    [path closePath];
    return path;
}

- (BOOL)playNotificationSnakeAnimation {
    return [self playNotificationSnakeAnimationWithPayload:nil];
}

- (BOOL)playNotificationSnakeAnimationWithPayload:(NSDictionary *)payload {
    if (![NSThread isMainThread] || !self.window || CGRectIsEmpty(self.bounds)) return NO;
    if (!self.track.path) [self layoutIfNeeded];
    if (!self.track.path) return NO;
    if ([payload isKindOfClass:NSDictionary.class]) [self recordNotificationIndicatorForPayload:payload];
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
#if NNP_NOTIFICATION_SNAKE_GEOMETRY_DIAGNOSTICS
    if (!self.notificationSnakeDebugGuideLayer) {
        self.notificationSnakeDebugGuideLayer = [CAShapeLayer layer];
        self.notificationSnakeDebugGuideLayer.fillColor = UIColor.clearColor.CGColor;
        self.notificationSnakeDebugGuideLayer.lineCap = kCALineCapRound;
        self.notificationSnakeDebugGuideLayer.lineJoin = kCALineJoinRound;
        self.notificationSnakeDebugGuideLayer.contentsScale = MAX(UIScreen.mainScreen.scale, 1.0);
        [self.layer addSublayer:self.notificationSnakeDebugGuideLayer];
    }
    if (!self.notificationSnakeDebugMarkersLayer) {
        self.notificationSnakeDebugMarkersLayer = [CAShapeLayer layer];
        self.notificationSnakeDebugMarkersLayer.fillColor = [UIColor colorWithRed:1.0 green:0.1 blue:0.72 alpha:1.0].CGColor;
        self.notificationSnakeDebugMarkersLayer.strokeColor = UIColor.whiteColor.CGColor;
        self.notificationSnakeDebugMarkersLayer.lineWidth = 1.0;
        self.notificationSnakeDebugMarkersLayer.contentsScale = MAX(UIScreen.mainScreen.scale, 1.0);
        [self.layer addSublayer:self.notificationSnakeDebugMarkersLayer];
    }
#endif

    CAShapeLayer *snake = self.notificationSnakeLayer;
    CAShapeLayer *finish = self.notificationSnakeFinishLayer;
    NSUInteger generation = ++self.notificationSnakeGeneration;
    [snake removeAllAnimations];
    [finish removeAllAnimations];
    [self.notificationCard.layer removeAllAnimations];
    [self.contentContainer.layer removeAllAnimations];
    snake.frame = self.bounds;
    snake.path = [self notificationSnakePath].CGPath;
    snake.lineWidth = NNPNotificationSnakeLineWidth;
    snake.zPosition = 1000.0;
    snake.strokeColor = self.accentColor.CGColor;
    snake.shadowColor = self.accentColor.CGColor;
    snake.shadowOpacity = 1.0;
    snake.shadowRadius = 16.0;
    snake.shadowOffset = CGSizeZero;
    snake.opacity = 1.0;
    self.notificationCardActive = NO;
    self.contentContainer.alpha = self.contentOpacity;
    self.notificationCard.hidden = YES;
    self.notificationCard.alpha = 0.0;
    self.notificationCard.transform = CGAffineTransformIdentity;
    finish.frame = self.bounds;
    // The closed perimeter ends at the track's left endpoint, so trace the U
    // from left to right as a visible, continuous final phase.
    finish.path = NNPNotificationSnakeFinishPath([self notchRectUsingPrivateAPI:NULL]).CGPath;
    finish.zPosition = 1001.0;
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
#if NNP_NOTIFICATION_SNAKE_GEOMETRY_DIAGNOSTICS
    CGRect debugNotch = [self notchRectUsingPrivateAPI:NULL];
    CAShapeLayer *debugGuide = self.notificationSnakeDebugGuideLayer;
    debugGuide.frame = self.bounds;
    debugGuide.path = NNPNotificationSnakeFinishPath(debugNotch).CGPath;
    debugGuide.zPosition = 1002.0;
    debugGuide.lineWidth = MAX(2.0, self.track.lineWidth + 1.0);
    debugGuide.strokeColor = [UIColor colorWithRed:0.0 green:0.95 blue:1.0 alpha:0.92].CGColor;
    debugGuide.lineDashPattern = @[@3.0, @2.0];
    debugGuide.shadowColor = debugGuide.strokeColor;
    debugGuide.shadowOpacity = 1.0;
    debugGuide.shadowRadius = 7.0;
    debugGuide.shadowOffset = CGSizeZero;
    debugGuide.opacity = 1.0;
    debugGuide.hidden = NO;

    CAShapeLayer *debugMarkers = self.notificationSnakeDebugMarkersLayer;
    debugMarkers.frame = self.bounds;
    debugMarkers.path = NNPNotificationSnakeCornerMarkersPath(debugNotch).CGPath;
    debugMarkers.zPosition = 1003.0;
    debugMarkers.opacity = 1.0;
    debugMarkers.hidden = NO;

    NSMutableArray<NSString *> *ancestorDescriptions = [NSMutableArray array];
    UIView *ancestor = self;
    for (NSUInteger depth = 0; ancestor && depth < 10; depth++, ancestor = ancestor.superview) {
        [ancestorDescriptions addObject:[NSString stringWithFormat:@"%@ frame=%@ bounds=%@ clips=%@ masks=%@ z=%.1f",
            NSStringFromClass(ancestor.class), NSStringFromCGRect(ancestor.frame), NSStringFromCGRect(ancestor.bounds),
            ancestor.clipsToBounds ? @"YES" : @"NO", ancestor.layer.masksToBounds ? @"YES" : @"NO", ancestor.layer.zPosition]];
    }
    CGFloat debugPathLeft = CGRectGetMinX(debugNotch) - 4.5;
    CGFloat debugPathRight = CGRectGetMaxX(debugNotch) + 4.5;
    CGFloat debugPathTop = MAX(9.0, CGRectGetMinY(debugNotch) + 9.0);
    CGFloat debugPathBottom = CGRectGetMaxY(debugNotch) + 4.0;
    CGFloat debugRadius = MIN(16.0, (debugPathBottom - debugPathTop) * 0.65);
    NNPDiagnosticLogTransition([NSString stringWithFormat:
        @"NOTIFICATION_SNAKE_GEOMETRY viewBounds=%@ notch=%@ U=(left=%.2f right=%.2f top=%.2f bottom=%.2f radius=%.2f) pixelShift=%@ ancestors=[%@] guide=cyan-dashed markers=magenta",
        NSStringFromCGRect(self.bounds), NSStringFromCGRect(debugNotch), debugPathLeft, debugPathRight,
        debugPathTop, debugPathBottom, debugRadius, NSStringFromCGPoint(self.pixelShiftPixels),
        [ancestorDescriptions componentsJoinedByString:@" <- "]]);
#endif
    [self updateNotificationSnakeCounterTransform];

    [self presentNotificationCardWithPayload:payload generation:generation];

    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    NSTimeInterval duration = 2.2;
    NSTimeInterval finishDuration = 1.0;
    NSTimeInterval handoffFadeDuration = 0.14;
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
        notchFinish.beginTime = CACurrentMediaTime() + duration * 2.0 + handoffFadeDuration;
        notchFinish.removedOnCompletion = NO;
        notchFinish.fillMode = kCAFillModeBoth;
        [finish addAnimation:notchFinish forKey:@"nnp.notificationSnakeNotchFinish"];

        CABasicAnimation *edgeFade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        edgeFade.fromValue = @1.0;
        edgeFade.toValue = @0.0;
        edgeFade.duration = handoffFadeDuration;
        edgeFade.beginTime = CACurrentMediaTime() + duration * 2.0;
        edgeFade.removedOnCompletion = NO;
        edgeFade.fillMode = kCAFillModeBoth;
        [snake addAnimation:edgeFade forKey:@"nnp.notificationSnakeEdgeFade"];
    }

    NSTimeInterval cleanupDelay = duration * (reduceMotion ? 1.0 : 2.0) +
        (reduceMotion ? 0.15 : handoffFadeDuration + finishDuration + 0.15);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(cleanupDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != self.notificationSnakeGeneration) return;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        snake.hidden = YES;
        finish.hidden = YES;
        [snake removeAllAnimations];
        [finish removeAllAnimations];
        snake.opacity = 0.0;
        snake.strokeStart = 0.0;
        snake.strokeEnd = 0.0;
        finish.opacity = 0.0;
        finish.strokeStart = 0.0;
        finish.strokeEnd = 0.0;
#if NNP_NOTIFICATION_SNAKE_GEOMETRY_DIAGNOSTICS
        self.notificationSnakeDebugGuideLayer.hidden = YES;
        self.notificationSnakeDebugGuideLayer.opacity = 0.0;
        self.notificationSnakeDebugMarkersLayer.hidden = YES;
        self.notificationSnakeDebugMarkersLayer.opacity = 0.0;
#endif
        [CATransaction commit];
        [self finishNotificationCardForGeneration:generation];
    });
    return YES;
}

- (void)recordNotificationIndicatorForPayload:(NSDictionary *)payload {
    id candidate = payload[@"icon"];
    UIImage *icon = [candidate isKindOfClass:UIImage.class] ? candidate : nil;
    if (!icon) icon = [UIImage systemImageNamed:@"app.fill"];
    if (!icon) return;

    BOOL wasHidden = self.notificationIndicatorStrip.hidden;
    self.notificationIndicatorCount++;
    [self.notificationIndicatorImages addObject:icon];
    while (self.notificationIndicatorImages.count > 3) [self.notificationIndicatorImages removeObjectAtIndex:0];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    if (wasHidden && !self.notificationIndicatorStrip.hidden) {
        self.notificationIndicatorStrip.alpha = 0.0;
        self.notificationIndicatorStrip.transform = CGAffineTransformMakeScale(0.88, 0.88);
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.12 : 0.24
                              delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            self.notificationIndicatorStrip.alpha = 1.0;
            self.notificationIndicatorStrip.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)clearNotificationIndicators {
    self.notificationIndicatorCount = 0;
    [self.notificationIndicatorImages removeAllObjects];
    [self.notificationIndicatorStrip.layer removeAllAnimations];
    self.notificationIndicatorStrip.hidden = YES;
    self.notificationIndicatorStrip.alpha = 1.0;
    self.notificationIndicatorStrip.transform = CGAffineTransformIdentity;
    for (UIImageView *iconView in self.notificationIndicatorImageViews) iconView.image = nil;
    self.notificationIndicatorOverflowLabel.text = nil;
    [self setNeedsLayout];
}

- (void)batteryStatusDidChange:(__unused NSNotification *)notification {
    if ([NSThread isMainThread]) {
        [self updateBatteryStatus];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateBatteryStatus]; });
    }
}

- (void)updateBatteryStatus {
    UIDevice *device = UIDevice.currentDevice;
    float level = device.batteryLevel;
    BOOL available = isfinite(level) && level >= 0.0f;
    BOOL availabilityChanged = self.batteryStatusAvailable != available;
    if (!available) {
        self.batteryStatusAvailable = NO;
        self.batteryStatus.hidden = YES;
        if (availabilityChanged) [self setNeedsLayout];
        return;
    }

    NSInteger percentage = (NSInteger)lroundf(MIN(1.0f, level) * 100.0f);
    UIDeviceBatteryState batteryState = device.batteryState;
    BOOL valueChanged = availabilityChanged || percentage != self.batteryPercentageValue || batteryState != self.batteryState;
    self.batteryStatusAvailable = YES;
    if (!valueChanged) return;
    self.batteryPercentageValue = percentage;
    self.batteryState = batteryState;
    NSString *symbolName = self.batteryPercentageValue < 15 ? @"battery.0percent" :
        (self.batteryPercentageValue < 40 ? @"battery.25percent" :
        (self.batteryPercentageValue < 65 ? @"battery.50percent" :
        (self.batteryPercentageValue < 90 ? @"battery.75percent" : @"battery.100percent")));
    UIImage *batteryImage = [UIImage systemImageNamed:symbolName];
    if (!batteryImage) batteryImage = [UIImage systemImageNamed:@"battery.100"];
    self.batteryIcon.image = batteryImage;
    self.batteryIcon.tintColor = self.batteryPercentageValue <= 20
        ? UIColor.systemRedColor : [UIColor colorWithWhite:1.0 alpha:0.78];
    self.batteryPercentage.text = [NSString stringWithFormat:@"%ld%%", (long)self.batteryPercentageValue];
    BOOL charging = self.batteryState == UIDeviceBatteryStateCharging;
    self.batteryChargingIcon.image = charging ? [UIImage systemImageNamed:@"bolt.fill"] : nil;
    self.batteryChargingIcon.hidden = !charging;
    self.batteryStatus.accessibilityLabel = charging
        ? [NSString stringWithFormat:@"電量 %ld%%，正在充電", (long)self.batteryPercentageValue]
        : [NSString stringWithFormat:@"電量 %ld%%", (long)self.batteryPercentageValue];
    if (availabilityChanged) [self setNeedsLayout];
}

- (BOOL)presentNotificationCardWithPayload:(NSDictionary *)payload generation:(NSUInteger)generation {
    if (![payload isKindOfClass:NSDictionary.class]) return NO;
    NSString *appName = [payload[@"appName"] isKindOfClass:NSString.class] ? payload[@"appName"] : @"";
    NSString *title = [payload[@"title"] isKindOfClass:NSString.class] ? payload[@"title"] : @"";
    NSString *subtitle = [payload[@"subtitle"] isKindOfClass:NSString.class] ? payload[@"subtitle"] : @"";
    NSString *message = [payload[@"message"] isKindOfClass:NSString.class] ? payload[@"message"] : @"";
    NSString *primaryText = title.length ? title : (subtitle.length ? subtitle : message);
    NSString *secondaryText = @"";
    if (title.length) {
        if (subtitle.length && message.length) secondaryText = [NSString stringWithFormat:@"%@ · %@", subtitle, message];
        else secondaryText = subtitle.length ? subtitle : message;
    }
    if (!primaryText.length && !secondaryText.length) primaryText = @"有新通知";
    UIImage *icon = [payload[@"icon"] isKindOfClass:UIImage.class] ? payload[@"icon"] : nil;
    if (!appName.length && !primaryText.length && !secondaryText.length && !icon) return NO;

    if (!self.notificationCard) {
        UIView *card = [UIView new];
        card.backgroundColor = [UIColor colorWithWhite:0.055 alpha:0.96];
        card.layer.cornerRadius = 22.0;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        card.layer.borderWidth = 1.0 / MAX(UIScreen.mainScreen.scale, 1.0);
        card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
        card.layer.shadowColor = UIColor.blackColor.CGColor;
        card.layer.shadowOpacity = 0.42;
        card.layer.shadowRadius = 18.0;
        card.layer.shadowOffset = CGSizeMake(0.0, 7.0);
        card.layer.zPosition = 1004.0;
        card.userInteractionEnabled = NO;

        UIImageView *iconView = [UIImageView new];
        iconView.contentMode = UIViewContentModeScaleAspectFill;
        iconView.clipsToBounds = YES;
        iconView.layer.cornerRadius = 12.0;
        iconView.layer.cornerCurve = kCACornerCurveContinuous;
        iconView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];

        UILabel *appLabel = [UILabel new];
        appLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
        appLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.62];
        appLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        UILabel *titleLabel = [UILabel new];
        titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
        titleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.96];
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        UILabel *messageLabel = [UILabel new];
        messageLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
        messageLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.76];
        messageLabel.numberOfLines = 2;
        messageLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        [card addSubview:iconView];
        [card addSubview:appLabel];
        [card addSubview:titleLabel];
        [card addSubview:messageLabel];
        [self addSubview:card];
        self.notificationCard = card;
        self.notificationCardIcon = iconView;
        self.notificationCardAppName = appLabel;
        self.notificationCardTitle = titleLabel;
        self.notificationCardMessage = messageLabel;
    }

    self.notificationCardAppName.text = appName;
    self.notificationCardTitle.text = primaryText;
    self.notificationCardTitle.hidden = !primaryText.length;
    self.notificationCardMessage.text = secondaryText;
    self.notificationCardMessage.hidden = !secondaryText.length;
    UIImage *displayIcon = icon ?: [UIImage systemImageNamed:@"app.fill"];
    self.notificationCardIcon.image = displayIcon;
    self.notificationCard.accessibilityLabel = [@[appName ?: @"", primaryText ?: @"", secondaryText ?: @""]
        componentsJoinedByString:@", "];
    self.notificationCardActive = YES;
    self.notificationCard.hidden = NO;
    self.notificationCard.alpha = 0.0;
    self.notificationCard.transform = CGAffineTransformMakeTranslation(0.0, -12.0);
    self.notificationCard.transform = CGAffineTransformScale(self.notificationCard.transform, 0.94, 0.94);
    [self setNeedsLayout];
    [self layoutIfNeeded];

    NSTimeInterval delay = UIAccessibilityIsReduceMotionEnabled() ? 0.05 : 0.28;
    NSTimeInterval duration = UIAccessibilityIsReduceMotionEnabled() ? 0.18 : 0.34;
    [UIView animateWithDuration:duration delay:delay
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        if (generation != self.notificationSnakeGeneration) return;
        self.contentContainer.alpha = 0.0;
        self.notificationCard.alpha = 1.0;
        self.notificationCard.transform = CGAffineTransformIdentity;
    } completion:nil];
    return YES;
}

- (void)finishNotificationCardForGeneration:(NSUInteger)generation {
    if (!self.notificationCardActive || generation != self.notificationSnakeGeneration) return;
    NSTimeInterval duration = UIAccessibilityIsReduceMotionEnabled() ? 0.10 : 0.18;
    [UIView animateWithDuration:duration delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.notificationCard.alpha = 0.0;
        self.contentContainer.alpha = self.contentOpacity;
    } completion:^(__unused BOOL finished) {
        if (generation != self.notificationSnakeGeneration) return;
        self.notificationCard.hidden = YES;
        self.notificationCard.transform = CGAffineTransformIdentity;
        self.notificationCardActive = NO;
        self.contentContainer.alpha = self.contentOpacity;
        self.notificationCardIcon.image = nil;
        self.notificationCardAppName.text = nil;
        self.notificationCardTitle.text = nil;
        self.notificationCardMessage.text = nil;
        self.notificationCard.accessibilityLabel = nil;
    }];
}

- (void)cancelNotificationSnakeAnimation {
    self.notificationSnakeGeneration++;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self.notificationSnakeLayer removeAllAnimations];
    [self.notificationSnakeFinishLayer removeAllAnimations];
    self.notificationSnakeLayer.hidden = YES;
    self.notificationSnakeFinishLayer.hidden = YES;
    self.notificationSnakeLayer.opacity = 0.0;
    self.notificationSnakeFinishLayer.opacity = 0.0;
#if NNP_NOTIFICATION_SNAKE_GEOMETRY_DIAGNOSTICS
    [self.notificationSnakeDebugGuideLayer removeAllAnimations];
    [self.notificationSnakeDebugMarkersLayer removeAllAnimations];
    self.notificationSnakeDebugGuideLayer.hidden = YES;
    self.notificationSnakeDebugMarkersLayer.hidden = YES;
#endif
    [CATransaction commit];
    [self.notificationCard.layer removeAllAnimations];
    [self.contentContainer.layer removeAllAnimations];
    self.notificationCard.hidden = YES;
    self.notificationCard.alpha = 0.0;
    self.notificationCard.transform = CGAffineTransformIdentity;
    self.notificationCardActive = NO;
    self.contentContainer.alpha = self.contentOpacity;
    self.notificationCardIcon.image = nil;
    self.notificationCardAppName.text = nil;
    self.notificationCardTitle.text = nil;
    self.notificationCardMessage.text = nil;
    self.notificationCard.accessibilityLabel = nil;
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
    [self stopTitleMarqueeCycle];
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
    [self scheduleTitleMarqueeCycleAfter:NNPTitleMarqueeInitialPause];
    NNPDiagnosticSetBool(@"TitleMarqueeSinglePass", YES);
    NNPDiagnosticSetDouble(@"TitleMarqueeIdleSeconds", NNPTitleMarqueeIdleSeconds);
}

- (void)stopTitleMarqueeCycle {
    self.marqueeGeneration++;
    [self.marqueeIdleTimer invalidate];
    self.marqueeIdleTimer = nil;
    [self.titleViewport.layer removeAnimationForKey:NNPTitleMarqueeAnimationKey];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.titleViewport.layer.sublayerTransform = CATransform3DIdentity;
    [CATransaction commit];
}

- (void)scheduleTitleMarqueeCycleAfter:(NSTimeInterval)delay {
    [self.marqueeIdleTimer invalidate];
    NSUInteger generation = self.marqueeGeneration;
    __weak typeof(self) weakSelf = self;
    self.marqueeIdleTimer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(__unused NSTimer *timer) {
        NNPView *view = weakSelf;
        if (!view || generation != view.marqueeGeneration) return;
        view.marqueeIdleTimer = nil;
        [view startTitleMarqueeCycle];
    }];
    self.marqueeIdleTimer.tolerance = MIN(2.0, delay * 0.1);
    [[NSRunLoop mainRunLoop] addTimer:self.marqueeIdleTimer forMode:NSRunLoopCommonModes];
}

- (void)startTitleMarqueeCycle {
    if (!self.marqueeAnimating || !self.playbackVisible || !self.window || UIAccessibilityIsReduceMotionEnabled()) {
        [self updateTitleMarquee];
        return;
    }
    CGFloat repeatDistance = CGRectGetMinX(self.titleDuplicate.frame);
    if (repeatDistance <= 0) return;
    NNPTitleMarqueeDelegate *delegate = [NNPTitleMarqueeDelegate new];
    delegate.view = self;
    delegate.generation = self.marqueeGeneration;
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"sublayerTransform"];
    animation.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    animation.toValue = [NSValue valueWithCATransform3D:CATransform3DMakeTranslation(-repeatDistance, 0, 0)];
    animation.duration = repeatDistance / 30.0;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.repeatCount = 0;
    animation.removedOnCompletion = YES;
    animation.delegate = delegate;
    [self.titleViewport.layer addAnimation:animation forKey:NNPTitleMarqueeAnimationKey];
}

- (void)titleMarqueeAnimationStopped:(BOOL)finished generation:(NSUInteger)generation {
    if (!finished || generation != self.marqueeGeneration || !self.marqueeAnimating || !self.playbackVisible || !self.window) return;
    // No render animation exists during this one-shot idle timer.
    [self scheduleTitleMarqueeCycleAfter:NNPTitleMarqueeIdleSeconds];
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
        self.lastPlaybackTimeDisplay = nil;
        self.lastLyricsCurrentLine = nil;
        self.lastLyricsNextLine = nil;
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
    [self updateClock];
    BOOL valid = duration > 0.0 && isfinite(duration);
    self.track.hidden = self.fill.hidden = !valid || !self.showProgress;
    self.playbackTime.hidden = !valid || !self.showProgress;
    if (!valid) return;
    elapsed = MIN(duration, MAX(0.0, elapsed));
    NSString *played = NNPPlaybackTimeString(elapsed);
    NSString *remaining = [@"−" stringByAppendingString:NNPPlaybackTimeString(ceil(duration - elapsed))];
    NSString *display = [NSString stringWithFormat:@"%@  ·  %@", played, remaining];
    if (![self.lastPlaybackTimeDisplay isEqualToString:display]) {
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
        self.lastPlaybackTimeDisplay = display;
    }
    self.fraction = elapsed / duration;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.fill.strokeEnd = self.fraction;
    self.fill.opacity = playing ? 1.0 : 0.55;
    [CATransaction commit];
}

- (void)updateClock {
    NSDate *now = NSDate.date;
    NSInteger minute = (NSInteger)floor(now.timeIntervalSince1970 / 60.0);
    if (minute == self.lastClockMinute && self.lastClockDisplay.length) return;

    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = NSTimeZone.localTimeZone;
        formatter.dateFormat = @"HH:mm";
    });
    NSString *display = [formatter stringFromDate:now];
    if (![self.lastClockDisplay isEqualToString:display]) {
        self.clockLabel.text = display;
        self.clockLabel.accessibilityLabel = [NSString stringWithFormat:@"目前時間 %@", display];
        self.lastClockDisplay = display;
    }
    self.lastClockMinute = minute;
}

- (void)updateLyricsText:(NSString *)currentLine nextLine:(NSString *)nextLine {
    NSString *current = [currentLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSString *next = [nextLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSString *text = current.length && next.length && ![current isEqualToString:next]
        ? [NSString stringWithFormat:@"%@\n%@", current, next] : current;
    if ([self.lastLyricsCurrentLine isEqualToString:current] &&
        [self.lastLyricsNextLine isEqualToString:next]) {
        self.lyricsLabel.hidden = !self.showLyrics || text.length == 0;
        self.lyricsLabel.accessibilityLabel = text;
        return;
    }
    self.lastLyricsCurrentLine = current;
    self.lastLyricsNextLine = next;
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
    [self.marqueeIdleTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
