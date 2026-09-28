#import <UIKit/UIKit.h>
@class NNPState;
@interface NNPView : UIView
@property(nonatomic) BOOL showArtwork;
@property(nonatomic) BOOL showArtist;
@property(nonatomic) BOOL showProgress;
@property(nonatomic) BOOL showLyrics;
@property(nonatomic) CGFloat artworkSize;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic) CGFloat textSize;
@property(nonatomic) CGFloat progressHeight;
@property(nonatomic) CGPoint pixelShiftPixels;
@property(nonatomic) BOOL playbackVisible;
@property(nonatomic) CGFloat contentOpacity;
- (void)updateState:(NNPState *)state;
- (void)updateElapsed:(NSTimeInterval)elapsed duration:(NSTimeInterval)duration playing:(BOOL)playing;
- (void)updateLyricsText:(NSString *)currentLine nextLine:(NSString *)nextLine;
- (void)stopContentAnimation;
- (BOOL)playNotificationSnakeAnimation;
- (BOOL)playNotificationSnakeAnimationWithPayload:(NSDictionary *)payload;
- (void)cancelNotificationSnakeAnimation;
@end
