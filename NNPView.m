#import "NNPView.h"
#import "NNPState.h"
#import <math.h>

#ifndef NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG
#define NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG 0
#endif
#ifndef NNP_PHASE4A_BUILD_ID
#define NNP_PHASE4A_BUILD_ID "unknown"
#endif

@interface NNPView ()
@property(nonatomic, strong) UIImageView *art;
@property(nonatomic, strong) UILabel *title;
@property(nonatomic, strong) UILabel *artist;
@property(nonatomic, strong) UIView *track;
@property(nonatomic, strong) UIView *fill;
@property(nonatomic, strong) UIView *dot;
@property(nonatomic) CGFloat fraction;
@end

@implementation NNPView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = NO;
    _art = [UIImageView new]; _art.backgroundColor = [UIColor colorWithWhite:1 alpha:.12];
    _art.contentMode = UIViewContentModeScaleAspectFill; _art.clipsToBounds = YES;
    _art.layer.cornerCurve = kCACornerCurveContinuous;
    _title = [UILabel new]; _title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _title.textColor = [UIColor colorWithWhite:1 alpha:.94]; _title.lineBreakMode = NSLineBreakByTruncatingTail;
    _artist = [UILabel new]; _artist.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    _artist.textColor = [UIColor colorWithWhite:1 alpha:.58]; _artist.lineBreakMode = NSLineBreakByTruncatingTail;
    _track = [UIView new]; _track.backgroundColor = [UIColor colorWithWhite:1 alpha:.22]; _track.layer.cornerRadius = 1.5;
    _fill = [UIView new]; _fill.backgroundColor = [UIColor colorWithWhite:1 alpha:.78]; _fill.layer.cornerRadius = 1.5; [_track addSubview:_fill];
    _dot = [UIView new]; _dot.backgroundColor = [UIColor colorWithWhite:1 alpha:.95]; _dot.layer.cornerRadius = 3.5;
    [self addSubview:_art]; [self addSubview:_title]; [self addSubview:_artist]; [self addSubview:_track]; [self addSubview:_dot];
    _showArtwork = YES; _showArtist = YES; _showProgress = YES; _artworkSize = 40.0; _cornerRadius = 9.0; _textSize = 14.0; _progressHeight = 3.0;
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, center = w / 2.0;
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat gap = MIN(180.0, MAX(132.0, w * .42));
    CGFloat leftLimit = center - gap / 2.0, rightStart = center + gap / 2.0;
    CGFloat side = MAX(12.0, safe.left + 10.0), top = MAX(8.0, safe.top - 7.0);
    CGFloat artSize = MIN(self.artworkSize, MAX(28.0, w * .14));
    _art.frame = CGRectMake(side, top, artSize, artSize);
    _art.hidden = !self.showArtwork; _art.layer.cornerRadius = self.cornerRadius;
    CGFloat textX = rightStart + 8.0, textW = MAX(42.0, w - textX - side);
    _title.font = [UIFont systemFontOfSize:self.textSize weight:UIFontWeightSemibold];
    _title.frame = CGRectMake(textX, top + 1.0, textW, MAX(16.0, self.textSize + 5.0));
    _artist.hidden = !self.showArtist;
    _artist.frame = CGRectMake(textX, top + self.textSize + 7.0, textW, 16.0);
    CGFloat px = MAX(side, leftLimit - 20.0), py = top + artSize + 13.0;
    CGFloat pw = MIN(w - side * 2.0, MAX(120.0, rightStart - px + 20.0));
    if (px + pw > w - side) pw = w - side - px;
    _track.frame = CGRectMake(px, py, MAX(1.0, pw), self.progressHeight);
    CGFloat fw = _track.bounds.size.width * self.fraction;
    _fill.frame = CGRectMake(0, 0, fw, self.progressHeight);
    _dot.frame = CGRectMake(MAX(px - 3.5, MIN(px + pw - 3.5, px + fw - 3.5)), py - 2.5, 7, 7);
}
- (void)updateState:(NNPState *)state {
    NSString *title = state.title.length ? state.title : @"Not Playing";
#if NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG
    title = [title stringByAppendingFormat:@" [P4A-%@]", @NNP_PHASE4A_BUILD_ID];
#endif
    self.title.text = title;
    self.artist.text = state.artist.length ? state.artist : (state.album ?: @"");
    self.art.image = state.artwork;
    [self setNeedsLayout];
}
- (void)updateElapsed:(NSTimeInterval)elapsed duration:(NSTimeInterval)duration playing:(BOOL)playing {
    BOOL valid = duration > 0.0 && isfinite(duration);
    self.track.hidden = self.fill.hidden = self.dot.hidden = !valid || !self.showProgress;
    if (!valid) return;
    elapsed = MIN(duration, MAX(0.0, elapsed)); self.fraction = elapsed / duration; self.dot.alpha = playing ? 1.0 : .55;
    [self setNeedsLayout];
}
@end
