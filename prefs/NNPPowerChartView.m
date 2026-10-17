#import "NNPPowerChartView.h"

@implementation NNPChartBar
@end

static const CGFloat NNPChartLeft = 4.0;
static const CGFloat NNPChartRight = 44.0;
static const CGFloat NNPChartTop = 8.0;
static const CGFloat NNPChartBottom = 20.0;

static NSString *NNPAxisDuration(double seconds) {
    if (seconds >= 3600.0) {
        double hours = seconds / 3600.0;
        return fabs(hours - round(hours)) < 0.05 ? [NSString stringWithFormat:@"%.0f 時", hours] : [NSString stringWithFormat:@"%.1f 時", hours];
    }
    return [NSString stringWithFormat:@"%.0f 分", seconds / 60.0];
}

@implementation NNPPowerChartView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.contentMode = UIViewContentModeRedraw;
        _selectedIndex = -1;
        _averagePower = -1;
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)]];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)setBars:(NSArray<NNPChartBar *> *)bars { _bars = [bars copy]; [self setNeedsDisplay]; }
- (void)setSelectedIndex:(NSInteger)selectedIndex { _selectedIndex = selectedIndex; [self setNeedsDisplay]; }

- (CGRect)plotRect {
    return CGRectMake(NNPChartLeft, NNPChartTop,
                      MAX(1.0, CGRectGetWidth(self.bounds) - NNPChartLeft - NNPChartRight),
                      MAX(1.0, CGRectGetHeight(self.bounds) - NNPChartTop - NNPChartBottom));
}

- (NSInteger)indexAtX:(CGFloat)x {
    if (!self.bars.count) return -1;
    CGRect plot = [self plotRect];
    NSInteger index = (NSInteger)floor((x - plot.origin.x) / (plot.size.width / (CGFloat)self.bars.count));
    return MAX(0, MIN((NSInteger)self.bars.count - 1, index));
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    NSInteger index = [self indexAtX:[tap locationInView:self].x];
    if (index < 0) return;
    if (self.onSelect) self.onSelect(index == self.selectedIndex ? -1 : index);
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    NSInteger index = [self indexAtX:[pan locationInView:self].x];
    if (index >= 0 && index != self.selectedIndex && self.onSelect) self.onSelect(index);
}

- (void)drawAxisValues:(NSArray<NSString *> *)labels plot:(CGRect)plot attributes:(NSDictionary *)attributes {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(context, 0.5);
    for (NSUInteger step = 0; step < labels.count; step++) {
        CGFloat y = CGRectGetMaxY(plot) - plot.size.height * (CGFloat)step / (CGFloat)(labels.count - 1);
        [(step == 0 ? UIColor.separatorColor : [UIColor.separatorColor colorWithAlphaComponent:0.5]) setStroke];
        CGContextMoveToPoint(context, plot.origin.x, y);
        CGContextAddLineToPoint(context, CGRectGetMaxX(plot), y);
        CGContextStrokePath(context);
        [labels[step] drawAtPoint:CGPointMake(CGRectGetMaxX(plot) + 6.0, y - 6.5) withAttributes:attributes];
    }
}

- (void)drawRect:(__unused CGRect)rect {
    CGRect plot = [self plotRect];
    NSArray<NNPChartBar *> *bars = self.bars;
    NSDictionary *axis = @{ NSFontAttributeName: [UIFont monospacedDigitSystemFontOfSize:10.0 weight:UIFontWeightMedium],
                            NSForegroundColorAttributeName: UIColor.secondaryLabelColor };
    CGFloat slot = plot.size.width / (CGFloat)MAX((NSUInteger)1, bars.count);

    // Selection band first, so every chart marks the same interval behind its data.
    if (self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)bars.count) {
        [[UIColor.labelColor colorWithAlphaComponent:0.08] setFill];
        UIRectFill(CGRectMake(plot.origin.x + slot * (CGFloat)self.selectedIndex, plot.origin.y, slot, plot.size.height));
    }

    if (self.kind == NNPChartKindBattery) {
        // Charging intervals shaded behind the line, stronger the longer it charged.
        for (NSUInteger index = 0; index < bars.count; index++) {
            double charge = bars[index].chargeSeconds;
            if (charge <= 0) continue;
            [[UIColor.systemGreenColor colorWithAlphaComponent:0.10 + 0.20 * MIN(1.0, charge / 3600.0)] setFill];
            UIRectFill(CGRectMake(plot.origin.x + slot * (CGFloat)index, plot.origin.y, slot, plot.size.height));
        }
        [self drawAxisValues:@[@"0%", @"50%", @"100%"] plot:plot attributes:axis];
        UIBezierPath *line = [UIBezierPath bezierPath];
        UIBezierPath *area = [UIBezierPath bezierPath];
        line.lineWidth = 2.0;
        line.lineJoinStyle = kCGLineJoinRound;
        BOOL open = NO;
        CGPoint first = CGPointZero, last = CGPointZero;
        for (NSUInteger index = 0; index < bars.count; index++) {
            double percent = bars[index].percent;
            if (percent < 0) continue;
            CGPoint point = CGPointMake(plot.origin.x + slot * ((CGFloat)index + 0.5),
                                        CGRectGetMaxY(plot) - plot.size.height * (CGFloat)MIN(100.0, percent) / 100.0);
            if (!open) { [line moveToPoint:point]; [area moveToPoint:CGPointMake(point.x, CGRectGetMaxY(plot))]; [area addLineToPoint:point]; first = point; open = YES; }
            else { [line addLineToPoint:point]; [area addLineToPoint:point]; }
            last = point;
        }
        if (open) {
            [area addLineToPoint:CGPointMake(last.x, CGRectGetMaxY(plot))];
            [area closePath];
            [[UIColor.systemOrangeColor colorWithAlphaComponent:0.15] setFill];
            [area fill];
            [UIColor.systemOrangeColor setStroke];
            [line stroke];
            (void)first;
        } else {
            [self drawEmpty:@"尚無電量紀錄" plot:plot attributes:axis];
        }
        if (self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)bars.count && bars[self.selectedIndex].percent >= 0) {
            double percent = bars[self.selectedIndex].percent;
            CGPoint point = CGPointMake(plot.origin.x + slot * ((CGFloat)self.selectedIndex + 0.5),
                                        CGRectGetMaxY(plot) - plot.size.height * (CGFloat)MIN(100.0, percent) / 100.0);
            [UIColor.systemBackgroundColor setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(point.x - 4.5, point.y - 4.5, 9.0, 9.0)] fill];
            [UIColor.systemOrangeColor setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(point.x - 3.0, point.y - 3.0, 6.0, 6.0)] fill];
        }
    } else {
        double maxValue = MAX(1.0, self.maxValue);
        NSArray *labels = self.kind == NNPChartKindTime
            ? @[@"0", NNPAxisDuration(maxValue / 2.0), NNPAxisDuration(maxValue)]
            : @[@"0", [NSString stringWithFormat:@"%.0f", maxValue / 2.0], [NSString stringWithFormat:@"%.0f mW", maxValue]];
        [self drawAxisValues:labels plot:plot attributes:axis];
        CGFloat barWidth = MAX(2.0, slot * 0.64);
        BOOL any = NO;
        for (NSUInteger index = 0; index < bars.count; index++) {
            NNPChartBar *bar = bars[index];
            CGFloat x = plot.origin.x + slot * (CGFloat)index + (slot - barWidth) / 2.0;
            BOOL dim = self.selectedIndex >= 0 && (NSInteger)index != self.selectedIndex;
            CGFloat radius = MIN(2.5, barWidth / 2.0);
            if (self.kind == NNPChartKindTime) {
                CGFloat idle = plot.size.height * (CGFloat)MIN(1.0, bar.idleSeconds / maxValue);
                CGFloat media = MIN(plot.size.height - idle, plot.size.height * (CGFloat)(bar.mediaSeconds / maxValue));
                if (idle > 0.5) {
                    [[UIColor.systemBlueColor colorWithAlphaComponent:dim ? 0.35 : 1.0] setFill];
                    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, CGRectGetMaxY(plot) - idle, barWidth, idle) cornerRadius:radius] fill];
                    any = YES;
                }
                if (media > 0.5) {
                    [[UIColor.systemGreenColor colorWithAlphaComponent:dim ? 0.35 : 1.0] setFill];
                    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, CGRectGetMaxY(plot) - idle - media, barWidth, media) cornerRadius:radius] fill];
                    any = YES;
                }
            } else if (bar.power > 0) {
                CGFloat height = plot.size.height * (CGFloat)MIN(1.0, bar.power / maxValue);
                // Color by what the AOD mostly showed in that interval.
                UIColor *color = bar.mediaSeconds > bar.idleSeconds ? UIColor.systemGreenColor : UIColor.systemIndigoColor;
                [[color colorWithAlphaComponent:dim ? 0.35 : 1.0] setFill];
                [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, CGRectGetMaxY(plot) - height, barWidth, height) cornerRadius:radius] fill];
                any = YES;
            }
        }
        if (!any) [self drawEmpty:self.kind == NNPChartKindTime ? @"這段期間沒有 AOD" : @"耗電資料不足" plot:plot attributes:axis];
        if (self.kind == NNPChartKindPower && self.averagePower > 0 && any) {
            CGFloat y = CGRectGetMaxY(plot) - plot.size.height * (CGFloat)MIN(1.0, self.averagePower / maxValue);
            UIBezierPath *dash = [UIBezierPath bezierPath];
            [dash moveToPoint:CGPointMake(plot.origin.x, y)];
            [dash addLineToPoint:CGPointMake(CGRectGetMaxX(plot), y)];
            CGFloat pattern[] = {4.0, 3.0};
            [dash setLineDash:pattern count:2 phase:0];
            dash.lineWidth = 1.0;
            [UIColor.systemRedColor setStroke];
            [dash stroke];
            NSDictionary *tag = @{ NSFontAttributeName: [UIFont monospacedDigitSystemFontOfSize:10.0 weight:UIFontWeightSemibold],
                                   NSForegroundColorAttributeName: UIColor.systemRedColor };
            [@"平均" drawAtPoint:CGPointMake(CGRectGetMaxX(plot) + 6.0, y - 6.5) withAttributes:tag];
        }
    }

    for (NSUInteger index = 0; index < bars.count; index++) {
        NNPChartBar *bar = bars[index];
        if (!bar.showLabel || !bar.label.length) continue;
        CGSize size = [bar.label sizeWithAttributes:axis];
        CGFloat x = plot.origin.x + slot * ((CGFloat)index + 0.5) - size.width / 2.0;
        x = MAX(0.0, MIN(CGRectGetMaxX(plot) - size.width, x));
        [bar.label drawAtPoint:CGPointMake(x, CGRectGetMaxY(plot) + 4.0) withAttributes:axis];
    }
}

- (void)drawEmpty:(NSString *)text plot:(CGRect)plot attributes:(NSDictionary *)attributes {
    CGSize size = [text sizeWithAttributes:attributes];
    [text drawAtPoint:CGPointMake(CGRectGetMidX(plot) - size.width / 2.0, CGRectGetMidY(plot) - size.height / 2.0) withAttributes:attributes];
}

@end
