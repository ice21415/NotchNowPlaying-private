#import "NNPController.h"
#if !NNP_SAFE_BOOT_TEST
#import "NNPMediaController.h"
#else
@class NNPMediaController;
#endif
#import "NNPState.h"
#import "NNPView.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

#ifndef NNP_DEBUG_SHOW_WHILE_UNLOCKED
#define NNP_DEBUG_SHOW_WHILE_UNLOCKED 0
#endif
#ifndef NNP_SAFE_BOOT_TEST
#define NNP_SAFE_BOOT_TEST 0
#endif
#ifndef NNP_ALLOW_ALL_MEDIA
#define NNP_ALLOW_ALL_MEDIA 0
#endif

static NSString * const NNPLog = @"[Lilywhite/NowPlaying]";
static NSString * const NNPSpotify = @"com.spotify.client";

@interface NNPController ()
@property(nonatomic, strong) NNPMediaController *media;
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) NNPView *view;
@property(nonatomic, strong) NNPState *state;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) BOOL locked;
@property(nonatomic) BOOL installed;
@property(nonatomic) NSUInteger ticks;
@property(nonatomic, strong) NSTimer *lockTimer;
@end

@implementation NNPController
+ (instancetype)sharedController { static NNPController *c; static dispatch_once_t once; dispatch_once(&once, ^{ c = [self new]; }); return c; }
- (void)install {
    if (self.installed) return; self.installed = YES;
#if NNP_SAFE_BOOT_TEST
    NSLog(@"%@ Safe boot test loaded; MediaRemote and UI disabled", NNPLog);
    return;
#else
    dispatch_async(dispatch_get_main_queue(), ^{
        self.media = [NNPMediaController new]; __weak typeof(self) weakSelf = self;
        self.media.stateHandler = ^(NNPState *state) { [weakSelf receive:state]; };
        [self.media start];
        Class lockClass = NSClassFromString(@"SBLockScreenManager");
        id (*noArg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        id manager = lockClass ? noArg(lockClass, @selector(sharedInstance)) : nil;
        if ([manager respondsToSelector:@selector(isUILocked)]) self.locked = ((BOOL (*)(id, SEL))objc_msgSend)(manager, @selector(isUILocked));
        __weak typeof(self) lockWeakSelf = self;
        self.lockTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(__unused NSTimer *timer) {
            [lockWeakSelf pollLockState];
        }];
        NSLog(@"%@ Controller installed locked=%@", NNPLog, self.locked ? @"YES" : @"NO");
    });
#endif
}
- (void)makeWindow {
    if (self.window) return;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.windowLevel = UIWindowLevelStatusBar + 1.0;
    self.window.backgroundColor = UIColor.clearColor; self.window.userInteractionEnabled = NO;
    UIViewController *root = [UIViewController new]; root.view.backgroundColor = UIColor.clearColor; root.view.userInteractionEnabled = NO;
    self.view = [[NNPView alloc] initWithFrame:root.view.bounds]; self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root.view addSubview:self.view]; self.window.rootViewController = root; self.window.hidden = YES;
}
- (void)setLocked:(BOOL)locked {
    dispatch_async(dispatch_get_main_queue(), ^{ if (_locked == locked) return; _locked = locked; NSLog(@"%@ Device %@", NNPLog, locked ? @"locked" : @"unlocked"); [self reconcile]; });
}
- (void)receive:(NNPState *)state {
    dispatch_async(dispatch_get_main_queue(), ^{ self.state = state; [self reconcile]; if (!self.window.hidden) { [self.view updateState:state]; [self tick]; } });
}
- (void)pollLockState {
    Class lockClass = NSClassFromString(@"SBLockScreenManager");
    id (*noArg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id manager = lockClass ? noArg(lockClass, @selector(sharedInstance)) : nil;
    if ([manager respondsToSelector:@selector(isUILocked)]) {
        BOOL locked = ((BOOL (*)(id, SEL))objc_msgSend)(manager, @selector(isUILocked));
        if (locked != self.locked) { _locked = locked; NSLog(@"%@ Device %@", NNPLog, locked ? @"locked" : @"unlocked"); [self reconcile]; }
    }
}
- (BOOL)spotifyState:(NNPState *)state {
#if NNP_ALLOW_ALL_MEDIA
    return state.hasTrack;
#else
    return [state.bundleIdentifier isEqualToString:NNPSpotify];
#endif
}
- (void)reconcile {
    BOOL show = self.state.hasTrack && self.state.playing && [self spotifyState:self.state] && (self.locked || NNP_DEBUG_SHOW_WHILE_UNLOCKED);
    if (!show) {
        if (self.window && !self.window.hidden) { self.window.hidden = YES; [self stopTimer]; NSLog(@"%@ Overlay hidden", NNPLog); }
        return;
    }
    [self makeWindow];
    if (show && self.window.hidden) { [self.view updateState:self.state]; self.window.hidden = NO; [self startTimer]; NSLog(@"%@ Overlay shown", NNPLog); }
    if (!show && !self.window.hidden) { self.window.hidden = YES; [self stopTimer]; NSLog(@"%@ Overlay hidden", NNPLog); }
    if (show) [self tick];
}
- (void)startTimer { if (self.timer) return; self.ticks = 0; __weak typeof(self) weakSelf = self; self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf tick]; }]; }
- (void)stopTimer { [self.timer invalidate]; self.timer = nil; }
- (void)tick {
    NNPState *state = self.state; if (!state) return;
    NSTimeInterval elapsed = state.elapsed;
    if (state.playing && state.playbackRate > 0 && state.timestamp > 0) elapsed += MAX(0, NSDate.date.timeIntervalSince1970 - state.timestamp) * state.playbackRate;
    [self.view updateElapsed:elapsed duration:state.duration playing:state.playing];
    self.ticks += 1;
#if !NNP_SAFE_BOOT_TEST
    if (self.ticks % 10 == 0) [self.media refresh];
#endif
}
@end
