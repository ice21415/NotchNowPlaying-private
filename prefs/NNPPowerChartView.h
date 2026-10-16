#import <UIKit/UIKit.h>

@interface NNPChartBar : NSObject
@property(nonatomic) double idleSeconds;
@property(nonatomic) double mediaSeconds;
@property(nonatomic) double percent;       // battery percent at the end of the interval, negative when unknown
@property(nonatomic, copy) NSString *label;
@property(nonatomic) BOOL showLabel;
@end

// Bars: AOD time per interval (idle clock in blue, music in green). Line: battery level, like the system Battery page.
@interface NNPPowerChartView : UIView
@property(nonatomic, copy) NSArray<NNPChartBar *> *bars;
@property(nonatomic) double maxSeconds;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic, copy) void (^onSelect)(NSInteger index);
@end
