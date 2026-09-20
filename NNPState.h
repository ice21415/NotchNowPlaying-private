#import <Foundation/Foundation.h>

@class UIImage;

@interface NNPState : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *artist;
@property(nonatomic, copy) NSString *album;
@property(nonatomic, strong) UIImage *artwork;
@property(nonatomic) NSTimeInterval duration;
@property(nonatomic) NSTimeInterval elapsed;
@property(nonatomic) NSTimeInterval timestamp;
@property(nonatomic) float playbackRate;
@property(nonatomic) BOOL playing;
@property(nonatomic, copy) NSString *bundleIdentifier;
@property(nonatomic, copy) NSString *uniqueIdentifier;
@property(nonatomic) BOOL validDuration;
- (BOOL)hasTrack;
- (NNPState *)copyState;
@end
