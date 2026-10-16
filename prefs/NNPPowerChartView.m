#import "NNPPowerChartView.h"

@implementation NNPChartBar
@end

static const CGFloat NNPChartLeft = 8.0;
static const CGFloat NNPChartRight = 36.0;
static const CGFloat NNPChartTop = 10.0;
static const CGFloat NNPChartBottom = 24.0;

@implementation NNPPowerChartView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.contentMode = UIViewContentModeRedraw;
        _selectedIndex = -1;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)setBars:(NSArray<NNPChartBar *> *)bars {
    _bars = [bars copy];
    [self setNeedsDisplay];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self setNeedsDisplay];
}

- (CGRect)plotRect {
    return CGRectMake(NNPChartLeft, NNPChartTop,
                      MAX(1.0, CGRectGetWidth(self.bounds) - NNPChartLeft - NNPChartRight),
                      MAX(1.0, CGRectGetHeight(self.bounds) - NNPChartTop - NNPChartBottom));
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    if (!self.bars.count) return;
    CGRect plot = [self plotRect];
    CGFloat x = [tap locationInView:self].x - plot.origin.x;
    NSInteger index = (NSInteger)floor(x / (plot.size.width / (CGFloat)self.bars.count));
    if (index < 0 || index >= (NSInteger)self.bars.count) return;
    self.selectedIndex = (index == self.selectedIndex) ? -1 : index;
    if (self.onSelect) self.onSelect(self.selectedIndex);
}

- (void)drawRect:(__unused CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect plot = [self plotRect];
    NSArray<NNPChartBar *> *bars = self.bars;
    UIFont *axisFont = [UIFont systemFontOfSize:10.0 weight:UIFontWeightMedium];
    UIColor *axisColor = UIColor.secondaryLabelColor;
    NSDictionary *axisAttributes = @{ NSFontAttributeName: axisFont, NSForegroundColorAttributeName: axisColor };

    // Grid lines and the battery percent axis on the right.
    CGContextSetLineWidth(context, 0.5);
    [UIColor.separatorColor setStroke];
    for (int step = 0; step <= 2; step++) {
        CGFloat y = CGRectGetMaxY(plot) - plot.size.height * (CGFloat)step / 2.0;
        CGContextMoveToPoint(context, plot.origin.x, y);
        CGContextAddLineToPoint(context, CGRectGetMaxX(plot), y);
        CGContextStrokePath(context);
        NSString *text = [NSString stringWithFormat:@"%d%%", step * 50];
        [text drawAtPoint:CGPointMake(CGRectGetMaxX(plot) + 4.0, y - 6.0) withAttributes:axisAttributes];
    }
    if (!bars.count) {
        NSString *empty = @"尚無資料";
        CGSize size = [empty sizeWithAttributes:axisAttributes];
        [empty drawAtPoint:CGPointMake(CGRectGetMidX(plot) - size.width / 2.0, CGRectGetMidY(plot) - size.height / 2.0)
            withAttributes:axisAttributes];
        return;
    }

    double maxSeconds = MAX(1.0, self.maxSeconds);
    CGFloat slot = plot.size.width / (CGFloat)bars.count;
    CGFloat barWidth = MAX(2.0, slot * 0.62);
    for (NSUInteger index = 0; index < bars.count; index++) {
        NNPChartBar *bar = bars[index];
        CGFloat x = plot.origin.x + slot * (CGFloat)index + (slot - barWidth) / 2.0;
        CGFloat idleHeight = plot.size.height * (CGFloat)MIN(1.0, bar.idleSeconds / maxSeconds);
        CGFloat mediaHeight = plot.size.height * (CGFloat)MIN(1.0 - idleHeight / plot.size.height, bar.mediaSeconds / maxSeconds);
        BOOL selected = (NSInteger)index == self.selectedIndex;
        if (idleHeight > 0.5) {
            [(selected ? UIColor.systemTealColor : UIColor.systemBlueColor) setFill];
            UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, CGRectGetMaxY(plot) - idleHeight, barWidth, idleHeight)
                                                        cornerRadius:MIN(2.0, barWidth / 2.0)];
            [path fill];
        }
        if (mediaHeight > 0.5) {
            [(selected ? UIColor.systemMintColor : UIColor.systemGreenColor) setFill];
            UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, CGRectGetMaxY(plot) - idleHeight - mediaHeight, barWidth, mediaHeight)
                                                        cornerRadius:MIN(2.0, barWidth / 2.0)];
            [path fill];
        }
        if (bar.showLabel && bar.label.length) {
            CGSize size = [bar.label sizeWithAttributes:axisAttributes];
            [bar.label drawAtPoint:CGPointMake(plot.origin.x + slot * ((CGFloat)index + 0.5) - size.width / 2.0, CGRectGetMaxY(plot) + 5.0)
                    withAttributes:axisAttributes];
        }
    }

    // Battery level line.
    UIBezierPath *line = [UIBezierPath bezierPath];
    line.lineWidth = 1.6;
    line.lineJoinStyle = kCGLineJoinRound;
    BOOL open = NO;
    NSMutableArray<NSValue *> *points = [NSMutableArray array];
    for (NSUInteger index = 0; index < bars.count; index++) {
        double percent = bars[index].percent;
        if (percent < 0) { open = NO; continue; }
        CGPoint point = CGPointMake(plot.origin.x + slot * ((CGFloat)index + 0.5),
                                    CGRectGetMaxY(plot) - plot.size.height * (CGFloat)MIN(100.0, percent) / 100.0);
        [points addObject:[NSValue valueWithCGPoint:point]];
        if (!open) { [line moveToPoint:point]; open = YES; } else { [line addLineToPoint:point]; }
    }
    [UIColor.systemOrangeColor setStroke];
    [line stroke];
    [UIColor.systemOrangeColor setFill];
    for (NSValue *value in points) {
        CGPoint point = value.CGPointValue;
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(point.x - 2.0, point.y - 2.0, 4.0, 4.0)] fill];
    }
}

@end
