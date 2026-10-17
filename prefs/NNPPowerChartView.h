#import <UIKit/UIKit.h>

@interface NNPChartBar : NSObject
@property(nonatomic) double idleSeconds;
@property(nonatomic) double mediaSeconds;
@property(nonatomic) double chargeSeconds;
@property(nonatomic) double percent;       // battery percent at the end of the interval, negative when unknown
@property(nonatomic) double power;         // average whole-device mW during AOD, negative when unknown
@property(nonatomic, copy) NSString *label;
@property(nonatomic) BOOL showLabel;
@end

typedef NS_ENUM(NSInteger, NNPChartKind) {
    NNPChartKindBattery,   // battery level line with charging intervals shaded
    NNPChartKindTime,      // AOD time per interval, idle clock and music stacked
    NNPChartKindPower,     // average power per interval with the range average as a dashed line
};

// One chart of the "AOD 耗電量" page. All charts on the page share the same bars and selection.
@interface NNPPowerChartView : UIView
@property(nonatomic) NNPChartKind kind;
@property(nonatomic, copy) NSArray<NNPChartBar *> *bars;
@property(nonatomic) double maxValue;      // seconds for the time chart, mW for the power chart
@property(nonatomic) double averagePower;  // power chart only, negative hides the line
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic, copy) void (^onSelect)(NSInteger index);
@end
