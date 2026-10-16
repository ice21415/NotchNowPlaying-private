#import "NNPPowerController.h"
#import "NNPPowerChartView.h"
#import "NNPPowerStatsShared.h"

typedef struct {
    double idleS, mediaS, dischS, chgS, usedMAh, pwrSum, pwrN;
} NNPAggregate;

static double NNPValue(NSDictionary *dictionary, NSString *key, double fallback) {
    id value = dictionary[key];
    return [value isKindOfClass:NSNumber.class] ? [(NSNumber *)value doubleValue] : fallback;
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

@implementation NNPPowerController {
    UISegmentedControl *_range;
    NNPPowerChartView *_chart;
    UILabel *_legend;
    UILabel *_detail;
    UIView *_header;
    NSArray<NSDictionary *> *_hours;
    NSDictionary *_battery;
    NSArray<NSString *> *_barDetails;
}

- (NSString *)plistName { return @"Power"; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AOD 耗電量";
    _range = [[UISegmentedControl alloc] initWithItems:@[@"過去 24 小時", @"過去 10 天"]];
    _range.selectedSegmentIndex = 0;
    [_range addTarget:self action:@selector(rangeChanged) forControlEvents:UIControlEventValueChanged];
    _chart = [[NNPPowerChartView alloc] initWithFrame:CGRectZero];
    __weak typeof(self) weakSelf = self;
    _chart.onSelect = ^(NSInteger index) { [weakSelf showDetailForIndex:index]; };
    _legend = [UILabel new];
    _legend.font = [UIFont systemFontOfSize:12.0];
    _legend.textColor = UIColor.secondaryLabelColor;
    _legend.numberOfLines = 0;
    _legend.text = @"藍色：無音樂時鐘　綠色：音樂播放　橘線：電量";
    _detail = [UILabel new];
    _detail.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    _detail.textColor = UIColor.labelColor;
    _detail.numberOfLines = 0;
    _detail.text = @"點一下長條可看該時段的詳細資料。";
    _header = [UIView new];
    [_header addSubview:_range];
    [_header addSubview:_chart];
    [_header addSubview:_legend];
    [_header addSubview:_detail];
    self.table.tableHeaderView = _header;
    [self reloadStats];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadStats];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.table.bounds);
    if (width <= 0) return;
    CGFloat margin = 16.0;
    CGFloat inner = width - margin * 2.0;
    _range.frame = CGRectMake(margin, 12.0, inner, 32.0);
    _chart.frame = CGRectMake(margin - 8.0, CGRectGetMaxY(_range.frame) + 12.0, inner + 16.0, 190.0);
    CGSize legendSize = [_legend sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)];
    _legend.frame = CGRectMake(margin, CGRectGetMaxY(_chart.frame) + 4.0, inner, legendSize.height);
    CGSize detailSize = [_detail sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)];
    _detail.frame = CGRectMake(margin, CGRectGetMaxY(_legend.frame) + 8.0, inner, MAX(36.0, detailSize.height));
    CGRect header = CGRectMake(0, 0, width, CGRectGetMaxY(_detail.frame) + 12.0);
    if (!CGRectEqualToRect(_header.frame, header)) {
        _header.frame = header;
        self.table.tableHeaderView = _header;
    }
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
    [self rebuildChart];
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
        sum.dischS += NNPValue(entry, @"dischS", 0);
        sum.chgS += NNPValue(entry, @"chgS", 0);
        sum.usedMAh += NNPValue(entry, @"usedMAh", 0);
        sum.pwrSum += NNPValue(entry, @"pwrSum", 0);
        sum.pwrN += NNPValue(entry, @"pwrN", 0);
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
    return nowHour - ([self showsDays] ? 239 : 23);
}

- (void)rebuildChart {
    NSMutableArray<NNPChartBar *> *bars = [NSMutableArray array];
    NSMutableArray<NSString *> *details = [NSMutableArray array];
    long long nowHour = (long long)([NSDate date].timeIntervalSince1970 / 3600.0);
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDateFormatter *hourFormatter = [NSDateFormatter new];
    hourFormatter.dateFormat = @"HH:00";
    NSDateFormatter *dayFormatter = [NSDateFormatter new];
    dayFormatter.dateFormat = @"M/d";
    double maxSeconds = 0;

    if (![self showsDays]) {
        for (long long hour = nowHour - 23; hour <= nowHour; hour++) {
            NNPAggregate sum = [self aggregateFrom:hour to:hour];
            NNPChartBar *bar = [NNPChartBar new];
            bar.idleSeconds = sum.idleS;
            bar.mediaSeconds = sum.mediaS;
            bar.percent = [self lastPercentFrom:hour to:hour];
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:(double)hour * 3600.0];
            bar.label = [[hourFormatter stringFromDate:date] substringToIndex:2];
            bar.showLabel = ((nowHour - hour) % 6) == 0;
            [bars addObject:bar];
            maxSeconds = MAX(maxSeconds, sum.idleS + sum.mediaS);
            [details addObject:[self detailTextForTitle:[hourFormatter stringFromDate:date] aggregate:sum percent:bar.percent]];
        }
        maxSeconds = MAX(3600.0, maxSeconds);
    } else {
        NSDate *today = [calendar startOfDayForDate:[NSDate date]];
        for (NSInteger offset = 9; offset >= 0; offset--) {
            NSDate *day = [calendar dateByAddingUnit:NSCalendarUnitDay value:-offset toDate:today options:0];
            long long startHour = (long long)llround(day.timeIntervalSince1970 / 3600.0);
            NSDate *next = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:day options:0];
            long long endHour = (long long)llround(next.timeIntervalSince1970 / 3600.0) - 1;
            NNPAggregate sum = [self aggregateFrom:startHour to:endHour];
            NNPChartBar *bar = [NNPChartBar new];
            bar.idleSeconds = sum.idleS;
            bar.mediaSeconds = sum.mediaS;
            bar.percent = [self lastPercentFrom:startHour to:endHour];
            bar.label = [dayFormatter stringFromDate:day];
            bar.showLabel = (offset % 3) == 0;
            [bars addObject:bar];
            maxSeconds = MAX(maxSeconds, sum.idleS + sum.mediaS);
            [details addObject:[self detailTextForTitle:[dayFormatter stringFromDate:day] aggregate:sum percent:bar.percent]];
        }
        maxSeconds = MAX(3.0 * 3600.0, ceil(maxSeconds / 3600.0 / 3.0) * 3.0 * 3600.0);
    }
    _barDetails = details;
    _chart.maxSeconds = maxSeconds;
    _chart.selectedIndex = -1;
    _chart.bars = bars;
    _detail.text = @"點一下長條可看該時段的詳細資料。";
}

- (NSString *)detailTextForTitle:(NSString *)title aggregate:(NNPAggregate)sum percent:(double)percent {
    double total = sum.idleS + sum.mediaS;
    if (total <= 0) return [NSString stringWithFormat:@"%@：沒有 AOD 紀錄", title];
    NSMutableArray *parts = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@　AOD %@", title, NNPDuration(total)]];
    if (sum.idleS > 0) [parts addObject:[NSString stringWithFormat:@"時鐘 %@", NNPDuration(sum.idleS)]];
    if (sum.mediaS > 0) [parts addObject:[NSString stringWithFormat:@"音樂 %@", NNPDuration(sum.mediaS)]];
    if (sum.pwrN > 0) [parts addObject:[NSString stringWithFormat:@"平均 %.0f mW", sum.pwrSum / sum.pwrN]];
    if (percent >= 0) [parts addObject:[NSString stringWithFormat:@"電量 %.0f%%", percent]];
    return [parts componentsJoinedByString:@" · "];
}

- (void)showDetailForIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_barDetails.count) {
        _detail.text = @"點一下長條可看該時段的詳細資料。";
    } else {
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
    return sum.pwrN >= 3 ? [NSString stringWithFormat:@"%.0f mW", sum.pwrSum / sum.pwrN] : @"資料不足";
}

- (id)valueUsedPercent:(__unused PSSpecifier *)specifier {
    NNPAggregate sum = [self currentAggregate];
    double capacity = [self batteryCapacityMAh];
    if (sum.dischS < 600 || capacity <= 0) return @"資料不足";
    return [NSString stringWithFormat:@"約 %.1f%%", sum.usedMAh / capacity * 100.0];
}

- (id)valuePerHour:(__unused PSSpecifier *)specifier {
    NNPAggregate sum = [self currentAggregate];
    double capacity = [self batteryCapacityMAh];
    if (sum.dischS < 1800 || capacity <= 0) return @"資料不足";
    return [NSString stringWithFormat:@"約 %.1f%% / 小時", sum.usedMAh / (sum.dischS / 3600.0) / capacity * 100.0];
}

- (id)valueCharging:(__unused PSSpecifier *)specifier {
    return NNPDuration([self currentAggregate].chgS);
}

- (id)valueBattery:(__unused PSSpecifier *)specifier {
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
