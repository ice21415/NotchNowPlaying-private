#import <Foundation/Foundation.h>

@interface NNPAODAmbientLight : NSObject
@property(nonatomic, copy) void (^sampleHandler)(double lux, BOOL valid);
- (void)setActive:(BOOL)active;
@end
