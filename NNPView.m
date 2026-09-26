#import "NNPView.h"
#import "NNPState.h"
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

@interface NNPView ()
@property(nonatomic, strong) UIImageView *art;
@property(nonatomic, strong) UIView *titleViewport;
@property(nonatomic, strong) UILabel *title;
@property(nonatomic, strong) UILabel *titleDuplicate;
@property(nonatomic, strong) UILabel *artist;
@property(nonatomic, strong) UIView *track;
@property(nonatomic, strong) UIView *fill;
@property(nonatomic) CGFloat fraction;
@property(nonatomic, copy) NSString *marqueeText;
@property(nonatomic) CGFloat marqueeWidth;
@property(nonatomic) CGFloat marqueeFontSize;
@property(nonatomic) BOOL marqueeReducedMotion;
@property(nonatomic) BOOL marqueeAnimating;
- (void)updateTitleMarquee;
@end

@implementation NNPView

- (void)setPixelShiftPixels:(CGPoint)pixelShiftPixels {
    _pixelShiftPixels = pixelShiftPixels;
    CGFloat scale = MAX(UIScreen.mainScreen.scale, 1.0);
    // Move only player content; the full-screen black mask remains fixed.
    self.layer.sublayerTransform = CATransform3DMakeTranslation(
        pixelShiftPixels.x / scale, pixelShiftPixels.y / scale, 0.0);
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
    _title.textColor = UIColor.whiteColor;
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

    _track = [UIView new];
    _track.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.20];
    _fill = [UIView new];
    _fill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    [_track addSubview:_fill];

    [self addSubview:_art];
    [self addSubview:_titleViewport];
    [self addSubview:_artist];
    [self addSubview:_track];

    _showArtwork = YES;
    _showArtist = YES;
    _showProgress = YES;
    _artworkSize = 40.0;
    _cornerRadius = 9.0;
    _textSize = 14.0;
    _progressHeight = 3.0;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reduceMotionChanged:)
                                                 name:UIAccessibilityReduceMotionStatusDidChangeNotification
                                               object:nil];
    return self;
}

- (void)reduceMotionChanged:(__unused NSNotification *)notification {
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat side = MAX(18.0, safe.left + 18.0);
    CGFloat top = MAX(66.0, safe.top + 15.0);
    CGFloat artSize = MIN(MAX(28.0, self.artworkSize), MAX(28.0, width * 0.18));
    BOOL artworkVisible = self.showArtwork;
    self.art.hidden = !artworkVisible;
    self.art.frame = CGRectMake(side, top, artSize, artSize);
    self.art.layer.cornerRadius = MIN(self.cornerRadius, artSize / 2.0);

    CGFloat textX = artworkVisible ? side + artSize + 14.0 : side;
    CGFloat textWidth = MAX(1.0, width - side - textX);
    BOOL reducedMotion = UIAccessibilityIsReduceMotionEnabled();
    CGFloat titleHeight = reducedMotion ? MAX(38.0, self.textSize * 2.5) : MAX(21.0, self.textSize + 7.0);
    self.title.font = [UIFont systemFontOfSize:self.textSize weight:UIFontWeightSemibold];
    self.titleDuplicate.font = self.title.font;
    self.title.numberOfLines = reducedMotion ? 2 : 1;
    self.titleViewport.frame = CGRectMake(textX, top + 1.0, textWidth, titleHeight);

    self.artist.hidden = !self.showArtist;
    CGFloat artistTop = CGRectGetMaxY(self.titleViewport.frame) + 3.0;
    self.artist.frame = CGRectMake(textX, artistTop, textWidth, 17.0);

    CGFloat contentBottom = self.showArtist ? CGRectGetMaxY(self.artist.frame) : CGRectGetMaxY(self.titleViewport.frame);
    CGFloat rowBottom = artworkVisible ? MAX(top + artSize, contentBottom) : contentBottom;
    CGFloat progressTop = rowBottom + 11.0;
    CGFloat progressHeight = MAX(2.0, self.progressHeight);
    self.track.frame = CGRectMake(textX, progressTop, textWidth, progressHeight);
    self.track.layer.cornerRadius = progressHeight / 2.0;
    self.fill.frame = CGRectMake(0.0, 0.0, textWidth * self.fraction, progressHeight);
    self.fill.layer.cornerRadius = progressHeight / 2.0;
    [self updateTitleMarquee];
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
    self.art.image = artwork ?: [UIImage systemImageNamed:@"music.note"];
    self.art.contentMode = artwork ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
    self.art.backgroundColor = artwork ? UIColor.clearColor : [UIColor colorWithWhite:1.0 alpha:0.11];
    self.art.tintColor = [UIColor colorWithWhite:1.0 alpha:0.7];
    [self setNeedsLayout];
}

- (void)updateElapsed:(NSTimeInterval)elapsed duration:(NSTimeInterval)duration playing:(BOOL)playing {
    BOOL valid = duration > 0.0 && isfinite(duration);
    self.track.hidden = !valid || !self.showProgress;
    if (!valid) return;
    elapsed = MIN(duration, MAX(0.0, elapsed));
    self.fraction = elapsed / duration;
    self.fill.alpha = playing ? 1.0 : 0.55;
    [self setNeedsLayout];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
