#import "NNPPowerController.h"
#import "NNPPowerChartView.h"
#import "NNPPowerStatsShared.h"

typedef struct {
    double idleS, mediaS, dischS, chgS, chgAllS, usedMAh, pwrSum, pwrN, usedPct, pctS;
} NNPAggregate;

static double NNPValue(NSDictionary *dictionary, NSString *key, double fallback) {
    id value = dictionary[key];
    double number = [value isKindOfClass:NSNumber.class] ? [(NSNumber *)value doubleValue] : fallback;
    return isfinite(number) ? number : fallback;
}

static NSString *NNPDuration(double seconds) {
    long minutes = (long)llround(seconds / 60.0);
    if (seconds <= 0) return @"—";
    if (minutes < 1) return @"不到 1 分鐘";
    if (minutes < 60) return [NSString stringWithFormat:@"%ld 分鐘", minutes];
    long hours = minutes / 60;
    long rest = minutes % 60;
    return rest ? [NSString stringWithFormat:@"%ld 小時 %ld 分", hours, rest] : [NSString stringWithFormat:@"%ld 小時", hours];
}

static UIView *NNPCard(void) {
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 12.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    return card;
}

static UILabel *NNPLabel(CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

static NSAttributedString *NNPLegend(NSArray<NSArray *> *items) {
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    UIFont *font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    for (NSArray *item in items) {
        if (text.length) [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"　" attributes:@{NSFontAttributeName: font}]];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"● " attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: item[1]}]];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:item[0] attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.secondaryLabelColor}]];
    }
    return text;
}

@implementation NNPPowerController {
    UISegmentedControl *_range;
    UIView *_header;
    UIView *_summaryCard;
    UILabel *_bigValue, *_bigCaption, *_summaryLine, *_modeLegend;
    UIView *_modeTrack, *_modeIdle, *_modeMedia;
    NSMutableArray<UIView *> *_chartCards;
    NSMutableArray<UILabel *> *_chartTitles, *_chartLegends;
    NSMutableArray<NNPPowerChartView *> *_charts;
    UIView *_detailCard;
    UILabel *_detailTitle, *_detail;
    NSArray<NSDictionary *> *_hours;
    NSDictionary *_battery;
    NSArray<NSString *> *_barTitles, *_barDetails;
    NSTimer *_refreshTimer;
    id _batteryObserver;
}

- (NSString *)plistName { return @"Power"; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AOD 耗電量";
    _header = [UIView new];
    _range = [[UISegmentedControl alloc] initWithItems:@[@"過去 24 小時", @"過去 10 天"]];
    _range.selectedSegmentIndex = 0;
    [_range addTarget:self action:@selector(rangeChanged) forControlEvents:UIControlEventValueChanged];
    [_header addSubview:_range];

    _summaryCard = NNPCard();
    _bigValue = NNPLabel(34.0, UIFontWeightBold, UIColor.labelColor);
    _bigValue.font = [UIFont monospacedDigitSystemFontOfSize:34.0 weight:UIFontWeightBold];
    _bigCaption = NNPLabel(13.0, UIFontWeightRegular, UIColor.secondaryLabelColor);
    _summaryLine = NNPLabel(15.0, UIFontWeightSemibold, UIColor.labelColor);
    _modeTrack = [UIView new];
    _modeTrack.backgroundColor = UIColor.tertiarySystemFillColor;
    _modeTrack.layer.cornerRadius = 4.0;
    _modeTrack.clipsToBounds = YES;
    _modeIdle = [UIView new];
    _modeIdle.backgroundColor = UIColor.systemBlueColor;
    _modeMedia = [UIView new];
    _modeMedia.backgroundColor = UIColor.systemGreenColor;
    [_modeTrack addSubview:_modeIdle];
    [_modeTrack addSubview:_modeMedia];
    _modeLegend = NNPLabel(12.0, UIFontWeightMedium, UIColor.secondaryLabelColor);
    for (UIView *view in @[_bigValue, _bigCaption, _summaryLine, _modeTrack, _modeLegend]) [_summaryCard addSubview:view];
    [_header addSubview:_summaryCard];

    _chartCards = [NSMutableArray array];
    _chartTitles = [NSMutableArray array];
    _chartLegends = [NSMutableArray array];
    _charts = [NSMutableArray array];
    NSArray *titles = @[@"電量", @"AOD 顯示時間", @"AOD 期間平均功率"];
    NSArray *legends = @[
        NNPLegend(@[@[@"電量", UIColor.systemOrangeColor], @[@"充電中", UIColor.systemGreenColor]]),
        NNPLegend(@[@[@"無音樂時鐘", UIColor.systemBlueColor], @[@"音樂播放", UIColor.systemGreenColor]]),
        NNPLegend(@[@[@"以時鐘為主", UIColor.systemIndigoColor], @[@"以音樂為主", UIColor.systemGreenColor], @[@"整段平均", UIColor.systemRedColor]]),
    ];
    NSArray *kinds = @[@(NNPChartKindBattery), @(NNPChartKindTime), @(NNPChartKindPower)];
    __weak typeof(self) weakSelf = self;
    for (NSUInteger index = 0; index < titles.count; index++) {
        UIView *card = NNPCard();
        UILabel *title = NNPLabel(15.0, UIFontWeightSemibold, UIColor.labelColor);
        title.text = titles[index];
        UILabel *legend = NNPLabel(12.0, UIFontWeightMedium, UIColor.secondaryLabelColor);
        legend.attributedText = legends[index];
        NNPPowerChartView *chart = [[NNPPowerChartView alloc] initWithFrame:CGRectZero];
        chart.kind = (NNPChartKind)[kinds[index] integerValue];
        chart.onSelect = ^(NSInteger selected) { [weakSelf selectIndex:selected]; };
        [card addSubview:title];
        [card addSubview:legend];
        [card addSubview:chart];
        [_header addSubview:card];
        [_chartCards addObject:card];
        [_chartTitles addObject:title];
        [_chartLegends addObject:legend];
        [_charts addObject:chart];
    }

    _detailCard = NNPCard();
    _detailTitle = NNPLabel(15.0, UIFontWeightSemibold, UIColor.labelColor);
    _detail = NNPLabel(14.0, UIFontWeightRegular, UIColor.secondaryLabelColor);
    [_detailCard addSubview:_detailTitle];
    [_detailCard addSubview:_detail];
    [_header addSubview:_detailCard];

    self.table.tableHeaderView = _header;
    [self reloadStats];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    __weak typeof(self) weakSelf = self;
    // SpringBoard records each battery change within a minute; refresh while the page is visible.
    if (!_batteryObserver) _batteryObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceBatteryLevelDidChangeNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { [weakSelf reloadStats]; }];
    [_refreshTimer invalidate];
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf reloadStats]; }];
    [self reloadStats];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_refreshTimer invalidate];
    _refreshTimer = nil;
    if (_batteryObserver) [NSNotificationCenter.defaultCenter removeObserver:_batteryObserver];
    _batteryObserver = nil;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.table.bounds);
    if (width <= 0) return;
    CGFloat margin = 16.0, pad = 14.0;
    CGFloat inner = width - margin * 2.0, content = inner - pad * 2.0;
    _range.frame = CGRectMake(margin, 12.0, inner, 32.0);

    CGFloat y = pad;
    _bigValue.frame = CGRectMake(pad, y, content, 40.0);
    y += 40.0;
    _bigCaption.frame = CGRectMake(pad, y, content, [_bigCaption sizeThatFits:CGSizeMake(content, CGFLOAT_MAX)].height);
    y = CGRectGetMaxY(_bigCaption.frame) + 10.0;
    _summaryLine.frame = CGRectMake(pad, y, content, [_summaryLine sizeThatFits:CGSizeMake(content, CGFLOAT_MAX)].height);
    y = CGRectGetMaxY(_summaryLine.frame) + 10.0;
    _modeTrack.frame = CGRectMake(pad, y, content, 8.0);
    y += 14.0;
    _modeLegend.frame = CGRectMake(pad, y, content, [_modeLegend sizeThatFits:CGSizeMake(content, CGFLOAT_MAX)].height);
    y = CGRectGetMaxY(_modeLegend.frame) + pad;
    _summaryCard.frame = CGRectMake(margin, CGRectGetMaxY(_range.frame) + 12.0, inner, y);
    [self layoutModeBar];

    CGFloat top = CGRectGetMaxY(_summaryCard.frame) + 12.0;
    for (NSUInteger index = 0; index < _chartCards.count; index++) {
        UILabel *title = _chartTitles[index], *legend = _chartLegends[index];
        CGFloat cy = pad;
        title.frame = CGRectMake(pad, cy, content, 20.0);
        cy += 22.0;
        legend.frame = CGRectMake(pad, cy, content, [legend sizeThatFits:CGSizeMake(content, CGFLOAT_MAX)].height);
        cy = CGRectGetMaxY(legend.frame) + 6.0;
        _charts[index].frame = CGRectMake(pad - 4.0, cy, content + 8.0, index == 0 ? 120.0 : 130.0);
        cy = CGRectGetMaxY(_charts[index].frame) + pad - 4.0;
        _chartCards[index].frame = CGRectMake(margin, top, inner, cy);
        top = CGRectGetMaxY(_chartCards[index].frame) + 12.0;
    }

    CGFloat dy = pad;
    _detailTitle.frame = CGRectMake(pad, dy, content, [_detailTitle sizeThatFits:CGSizeMake(content, CGFLOAT_MAX)].height);
    dy = CGRectGetMaxY(_detailTitle.frame) + 6.0;
    _detail.frame = CGRectMake(pad, dy, content, [_detail sizeThatFits:CGSizeMake(content, CGFLOAT_MAX)].height);
    dy = CGRectGetMaxY(_detail.frame) + pad;
    _detailCard.frame = CGRectMake(margin, top, inner, dy);

    CGRect header = CGRectMake(0, 0, width, CGRectGetMaxY(_detailCard.frame) + 4.0);
    if (!CGRectEqualToRect(_header.frame, header)) {
        _header.frame = header;
        self.table.tableHeaderView = _header;
    }
}

- (void)layoutModeBar {
    NNPAggregate sum = [self currentAggregate];
    double total = sum.idleS + sum.mediaS;
    CGFloat width = CGRectGetWidth(_modeTrack.bounds), height = CGRectGetHeight(_modeTrack.bounds);
    CGFloat idle = total > 0 ? width * (CGFloat)(sum.idleS / total) : 0;
    _modeIdle.frame = CGRectMake(0, 0, idle, height);
    _modeMedia.frame = CGRectMake(idle, 0, total > 0 ? width - idle : 0, height);
}

- (void)rangeChanged {
    [self reloadStats];
}

- (void)reloadStats {
    CFStringRef domain = (__bridge CFStringRef)NNPStatsDomain;
    CFPreferencesAppSynchronize(domain);
    id hours = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)NNPStatsHoursKey, domain));
    id battery = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)NNPStatsBatteryKey, domain));
    _hours = [hours isKindOfClass:NSArray.class] ? hours : @[];
    _battery = [battery isKindOfClass:NSDictionary.class] ? battery : @{};
    [self rebuildCharts];
    [self updateSummary];
    [self selectIndex:-1];
    [self.table reloadData];
    [self.view setNeedsLayout];
}

- (BOOL)showsDays { return _range.selectedSegmentIndex == 1; }

- (NNPAggregate)aggregateFrom:(long long)startHour to:(long long)endHour {
    NNPAggregate sum = {0};
    for (NSDictionary *entry in _hours) {
        long long hour = (long long)NNPValue(entry, @"h", -1);
        if (hour < startHour || hour > endHour) continue;
        sum.idleS += NNPValue(entry, @"idleS", 0);
        sum.mediaS += NNPValue(entry, @"mediaS", 0);
        sum.dischS += NNPValue(entry, @"dischS2", 0);
        sum.chgS += NNPValue(entry, @"chgS", 0);
        sum.chgAllS += NNPValue(entry, @"chgAllS", 0);
        sum.usedMAh += NNPValue(entry, @"usedMAh2", 0);
        sum.pwrSum += NNPValue(entry, @"energyMWs", 0);
        sum.pwrN += NNPValue(entry, @"powerS", 0);
        sum.usedPct += NNPValue(entry, @"usedPct2", 0);
        sum.pctS += NNPValue(entry, @"pctS2", 0);
    }
    return sum;
}

- (double)lastPercentFrom:(long long)startHour to:(long long)endHour {
    double percent = -1;
    for (NSDictionary *entry in _hours) {
        long long hour = (long long)NNPValue(entry, @"h", -1);
        if (hour < startHour || hour > endHour) continue;
        double value = NNPValue(entry, @"pct1", -1);
        if (value >= 0) percent = value;
    }
    return percent;
}

- (long long)rangeStartHour {
    long long nowHour = (long long)([NSDate date].timeIntervalSince1970 / 3600.0);
    if ([self showsDays]) {
        NSDate *today = [NSCalendar.currentCalendar startOfDayForDate:[NSDate date]];
        NSDate *first = [NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitDay value:-9 toDate:today options:0];
        return (long long)floor(first.timeIntervalSince1970 / 3600.0);
    }
    return nowHour - 23;
}

- (void)rebuildCharts {
    NSMutableArray<NNPChartBar *> *bars = [NSMutableArray array];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<NSString *> *details = [NSMutableArray array];
    long long nowHour = (long long)([NSDate date].timeIntervalSince1970 / 3600.0);
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDateFormatter *hourFormatter = [NSDateFormatter new];
    hourFormatter.dateFormat = @"HH:00";
    NSDateFormatter *dayFormatter = [NSDateFormatter new];
    dayFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_Hant_TW"];
    dayFormatter.dateFormat = @"M月d日 EEEE";
    NSDateFormatter *shortDay = [NSDateFormatter new];
    shortDay.dateFormat = @"M/d";

    void (^add)(long long, long long, NSString *, NSString *, BOOL) = ^(long long start, long long end, NSString *label, NSString *title, BOOL showLabel) {
        NNPAggregate sum = [self aggregateFrom:start to:end];
        NNPChartBar *bar = [NNPChartBar new];
        bar.idleSeconds = sum.idleS;
        bar.mediaSeconds = sum.mediaS;
        bar.chargeSeconds = MAX(sum.chgS, sum.chgAllS);
        bar.percent = [self lastPercentFrom:start to:end];
        bar.power = sum.pwrN > 0 ? sum.pwrSum / sum.pwrN : -1;
        bar.label = label;
        bar.showLabel = showLabel;
        [bars addObject:bar];
        [titles addObject:title];
        [details addObject:[self detailTextForAggregate:sum percent:bar.percent]];
    };
    if (![self showsDays]) {
        for (long long hour = nowHour - 23; hour <= nowHour; hour++) {
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:(double)hour * 3600.0];
            NSDate *next = [NSDate dateWithTimeIntervalSince1970:(double)(hour + 1) * 3600.0];
            NSString *title = [NSString stringWithFormat:@"%@–%@", [hourFormatter stringFromDate:date], [hourFormatter stringFromDate:next]];
            add(hour, hour, [hourFormatter stringFromDate:date], title, ((nowHour - hour) % 6) == 0);
        }
    } else {
        NSDate *today = [calendar startOfDayForDate:[NSDate date]];
        for (NSInteger offset = 9; offset >= 0; offset--) {
            NSDate *day = [calendar dateByAddingUnit:NSCalendarUnitDay value:-offset toDate:today options:0];
            NSDate *next = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:day options:0];
            long long start = (long long)llround(day.timeIntervalSince1970 / 3600.0);
            long long end = (long long)llround(next.timeIntervalSince1970 / 3600.0) - 1;
            add(start, end, [shortDay stringFromDate:day], [dayFormatter stringFromDate:day], (offset % 3) == 0);
        }
    }
    double maxSeconds = 0, maxPower = 0;
    for (NNPChartBar *bar in bars) {
        maxSeconds = MAX(maxSeconds, bar.idleSeconds + bar.mediaSeconds);
        maxPower = MAX(maxPower, bar.power);
    }
    // Readable axis steps: an hour bar tops out at 60 min, day bars use 2 h steps, power uses 200 mW steps.
    if ([self showsDays]) maxSeconds = MAX(4.0 * 3600.0, ceil(maxSeconds / 7200.0) * 7200.0);
    else maxSeconds = 3600.0;
    maxPower = MAX(400.0, ceil(maxPower / 200.0) * 200.0);
    NNPAggregate range = [self currentAggregate];
    for (NNPPowerChartView *chart in _charts) {
        chart.bars = bars;
        chart.maxValue = chart.kind == NNPChartKindTime ? maxSeconds : maxPower;
        chart.averagePower = range.pwrN > 0 ? range.pwrSum / range.pwrN : -1;
    }
    _barTitles = titles;
    _barDetails = details;
}

- (void)updateSummary {
    NNPAggregate sum = [self currentAggregate];
    double total = sum.idleS + sum.mediaS;
    _bigValue.text = sum.pwrN >= 180 ? [NSString stringWithFormat:@"%.0f mW", sum.pwrSum / sum.pwrN] : @"—";
    _bigCaption.text = [NSString stringWithFormat:@"%@ AOD 顯示期間，整支手機的平均功率（含螢幕與系統，不只是插件）。",
                        [self showsDays] ? @"過去 10 天" : @"過去 24 小時"];
    NSMutableArray *parts = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"AOD %@", NNPDuration(total)]];
    if (sum.pctS >= 1800)
        [parts addObject:[NSString stringWithFormat:@"每小時約 %.1f%%", sum.usedPct / (sum.pctS / 3600.0)]];
    if (sum.pctS >= 600)
        [parts addObject:[NSString stringWithFormat:@"共用掉約 %.1f%%", sum.usedPct]];
    _summaryLine.text = [parts componentsJoinedByString:@" · "];
    _modeLegend.attributedText = NNPLegend(@[@[[NSString stringWithFormat:@"時鐘 %@", NNPDuration(sum.idleS)], UIColor.systemBlueColor],
                                             @[[NSString stringWithFormat:@"音樂 %@", NNPDuration(sum.mediaS)], UIColor.systemGreenColor]]);
}

- (NSString *)detailTextForAggregate:(NNPAggregate)sum percent:(double)percent {
    double total = sum.idleS + sum.mediaS;
    NSMutableArray *lines = [NSMutableArray array];
    if (total > 0)
        [lines addObject:[NSString stringWithFormat:@"AOD 顯示 %@（時鐘 %@、音樂 %@）", NNPDuration(total), NNPDuration(sum.idleS), NNPDuration(sum.mediaS)]];
    else
        [lines addObject:@"這段期間沒有 AOD 顯示"];
    if (total > 0) [lines addObject:[NSString stringWithFormat:@"有效放電量測 %@（顯示時間的 %.0f%%）", NNPDuration(sum.pwrN), MIN(100.0, sum.pwrN / total * 100.0)]];
    if (sum.pwrN > 0) [lines addObject:[NSString stringWithFormat:@"估計平均功率 %.0f mW（有效量測 %.0f 秒）", sum.pwrSum / sum.pwrN, sum.pwrN]];
    if (sum.usedMAh > 0) {
        NSString *share = sum.pctS > 0 ? [NSString stringWithFormat:@"，約 %.1f%%", sum.usedPct] : @"";
        [lines addObject:[NSString stringWithFormat:@"AOD 有效量測期間估計用掉 %.1f mAh%@", sum.usedMAh, share]];
    }
    if (MAX(sum.chgS, sum.chgAllS) > 0) [lines addObject:[NSString stringWithFormat:@"充電 %@", NNPDuration(MAX(sum.chgS, sum.chgAllS))]];
    if (percent >= 0) [lines addObject:[NSString stringWithFormat:@"時段結束時電量 %.0f%%", percent]];
    return [lines componentsJoinedByString:@"\n"];
}

- (void)selectIndex:(NSInteger)index {
    for (NNPPowerChartView *chart in _charts) chart.selectedIndex = index;
    if (index < 0 || index >= (NSInteger)_barDetails.count) {
        _detailTitle.text = @"點選或拖曳圖表";
        _detail.text = @"三張圖會一起標出同一個時段，這裡會顯示該時段的 AOD 時間、平均功率、用掉的電量與充電時間。";
    } else {
        _detailTitle.text = _barTitles[(NSUInteger)index];
        _detail.text = _barDetails[(NSUInteger)index];
    }
    [self.view setNeedsLayout];
}

- (double)batteryCapacityMAh {
    double maxMAh = NNPValue(_battery, @"maxMAh", 0);
    return maxMAh > 0 ? maxMAh : NNPValue(_battery, @"designMAh", 0);
}

#pragma mark - Row getters

- (NNPAggregate)currentAggregate {
    long long nowHour = (long long)([NSDate date].timeIntervalSince1970 / 3600.0);
    return [self aggregateFrom:[self rangeStartHour] to:nowHour];
}

- (id)valueTotalTime:(__unused PSSpecifier *)specifier {
    NNPAggregate sum = [self currentAggregate];
    return NNPDuration(sum.idleS + sum.mediaS);
}
- (id)valueIdleTime:(__unused PSSpecifier *)specifier { return NNPDuration([self currentAggregate].idleS); }
- (id)valueMediaTime:(__unused PSSpecifier *)specifier { return NNPDuration([self currentAggregate].mediaS); }

- (id)valueAveragePower:(__unused PSSpecifier *)specifier {
    NNPAggregate sum = [self currentAggregate];
    return sum.pwrN >= 180 ? [NSString stringWithFormat:@"%.0f mW", sum.pwrSum / sum.pwrN] : @"資料不足";
}

- (id)valueUsedPercent:(__unused PSSpecifier *)specifier {
    NNPAggregate sum = [self currentAggregate];
    if (sum.pctS < 600) return @"資料不足";
    return [NSString stringWithFormat:@"約 %.1f%%", sum.usedPct];
}

- (id)valuePerHour:(__unused PSSpecifier *)specifier {
    NNPAggregate sum = [self currentAggregate];
    if (sum.pctS < 1800) return @"資料不足";
    return [NSString stringWithFormat:@"約 %.1f%% / 小時", sum.usedPct / (sum.pctS / 3600.0)];
}

- (id)valueCharging:(__unused PSSpecifier *)specifier {
    return NNPDuration([self currentAggregate].chgS);
}

- (id)valueBattery:(__unused PSSpecifier *)specifier {
    UIDevice *device = UIDevice.currentDevice;
    if (device.batteryLevel >= 0) {
        BOOL charging = device.batteryState == UIDeviceBatteryStateCharging || device.batteryState == UIDeviceBatteryStateFull;
        return [NSString stringWithFormat:@"%.0f%%%@", device.batteryLevel * 100.0, charging ? @"（充電中）" : @""];
    }
    double percent = NNPValue(_battery, @"percent", -1);
    if (percent < 0) return @"尚無資料";
    NSString *state = [_battery[@"charging"] boolValue] ? @"（充電中）" : @"";
    return [NSString stringWithFormat:@"%.0f%% %@", percent, state];
}

- (id)valueHealth:(__unused PSSpecifier *)specifier {
    double max = NNPValue(_battery, @"maxMAh", 0), design = NNPValue(_battery, @"designMAh", 0);
    if (max <= 0 || design <= 0) return @"尚無資料";
    return [NSString stringWithFormat:@"%.0f%%（%.0f / %.0f mAh）", max / design * 100.0, max, design];
}

- (id)valueCycles:(__unused PSSpecifier *)specifier {
    double cycles = NNPValue(_battery, @"cycles", 0);
    return cycles > 0 ? [NSString stringWithFormat:@"%.0f 次", cycles] : @"尚無資料";
}

- (id)valueTemperature:(__unused PSSpecifier *)specifier {
    double temperature = NNPValue(_battery, @"tempC", 0);
    return temperature > 0 ? [NSString stringWithFormat:@"%.1f °C", temperature] : @"尚無資料";
}

#pragma mark - Actions

- (void)clearStats {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清除耗電統計？"
        message:@"所有 AOD 使用時間與耗電紀錄會被刪除，無法復原。" preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        CFStringRef domain = (__bridge CFStringRef)NNPStatsDomain;
        CFPreferencesSetAppValue((__bridge CFStringRef)NNPStatsHoursKey, NULL, domain);
        CFPreferencesSetAppValue((__bridge CFStringRef)NNPStatsBatteryKey, NULL, domain);
        CFPreferencesAppSynchronize(domain);
        [weakSelf reloadStats];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
