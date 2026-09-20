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
#ifndef NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
#define NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT 0
#endif
#ifndef NNP_PHASE2D2_DIAGNOSTIC
#define NNP_PHASE2D2_DIAGNOSTIC 0
#endif
#if NNP_PHASE2D2_DIAGNOSTIC || NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
#import "NNPDiagnostics.h"
#endif

#if NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
#import "NNPDisplayAssertionController.h"
#endif

#ifndef NNP_DEBUG_SHOW_WHILE_UNLOCKED
#define NNP_DEBUG_SHOW_WHILE_UNLOCKED 0
#endif
#ifndef NNP_SAFE_BOOT_TEST
#define NNP_SAFE_BOOT_TEST 0
#endif
#ifndef NNP_ALLOW_ALL_MEDIA
#define NNP_ALLOW_ALL_MEDIA 0
#endif
#ifndef NNP_UI_SMOKE_TEST
#define NNP_UI_SMOKE_TEST 0
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
#if NNP_PHASE2D2_DIAGNOSTIC
@property(nonatomic) BOOL diagnosticArmed;
@property(nonatomic) BOOL diagnosticAttempted;
#endif
#if NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
@property(nonatomic, strong) NNPDisplayAssertionController *displayAssertion;
#endif
@end

@implementation NNPController
+ (instancetype)sharedController { static NNPController *c; static dispatch_once_t once; dispatch_once(&once, ^{ c = [self new]; }); return c; }
- (void)install {
    if (self.installed) return; self.installed = YES;
#if NNP_UI_SMOKE_TEST
    dispatch_async(dispatch_get_main_queue(), ^{
        NNPState *smoke = [NNPState new];
        smoke.title = @"NotchNowPlaying UI smoke";
        smoke.artist = @"SpringBoard injection is active";
        smoke.playing = YES;
        self.state = smoke;
        [self makeWindow];
        [self.view updateState:smoke];
        self.window.hidden = NO;
        NSLog(@"%@ UI smoke shown", NNPLog);
    });
    return;
#endif
#if NNP_SAFE_BOOT_TEST
    NSLog(@"%@ Safe boot test loaded; MediaRemote and UI disabled", NNPLog);
    return;
#else
    dispatch_async(dispatch_get_main_queue(), ^{
        self.media = [NNPMediaController new]; __weak typeof(self) weakSelf = self;
        self.media.stateHandler = ^(NNPState *state) { [weakSelf receive:state]; };
#if NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
        self.displayAssertion = [NNPDisplayAssertionController new];
#endif
#if NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
        NNPDiagnosticSetBool(@"ControllerInitialized", YES);
#endif
#if NNP_PHASE2D2_DIAGNOSTIC
        NNPDiagnosticLog(@"CONTROLLER_INIT");
#endif
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
    UIWindowScene *activeScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState == UISceneActivationStateUnattached) continue;
        activeScene = (UIWindowScene *)scene;
        break;
    }
    self.window = activeScene ? [[UIWindow alloc] initWithWindowScene:activeScene] : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.frame = UIScreen.mainScreen.bounds;
    self.window.windowLevel = UIWindowLevelAlert + 1.0;
    self.window.backgroundColor = UIColor.clearColor; self.window.userInteractionEnabled = NO;
    UIViewController *root = [UIViewController new]; root.view.backgroundColor = UIColor.clearColor; root.view.userInteractionEnabled = NO;
    root.view.frame = self.window.bounds;
    self.view = [[NNPView alloc] initWithFrame:self.window.bounds]; self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root.view addSubview:self.view]; self.window.rootViewController = root; self.window.hidden = YES;
}
- (void)setLocked:(BOOL)locked {
    dispatch_async(dispatch_get_main_queue(), ^{ if (_locked == locked) return; _locked = locked; NSLog(@"%@ Device %@", NNPLog, locked ? @"locked" : @"unlocked");
#if NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
        NNPDiagnosticSetBool(@"Locked", locked);
        NNPDiagnosticSetString(@"LastLockState", locked ? @"locked" : @"unlocked");
        NNPDiagnosticSetString(@"LastLockStateTimestamp", [[NSDate date] description]);
#endif
        [self reconcile]; });
}
- (void)receive:(NNPState *)state {
    dispatch_async(dispatch_get_main_queue(), ^{ self.state = state;
#if NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
        NNPDiagnosticSetBool(@"SpotifyDetected", [self spotifyState:state]);
        NNPDiagnosticSetBool(@"PlaybackActive", state.playing);
        NNPDiagnosticSetBool(@"NowPlayingValid", state.hasTrack);
        if (state.bundleIdentifier.length) NNPDiagnosticSetString(@"ActiveMediaBundle", state.bundleIdentifier);
#endif
        [self reconcile]; if (!self.window.hidden) { [self.view updateState:state]; [self tick]; } });
}
- (void)pollLockState {
    Class lockClass = NSClassFromString(@"SBLockScreenManager");
    id (*noArg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id manager = lockClass ? noArg(lockClass, @selector(sharedInstance)) : nil;
    if ([manager respondsToSelector:@selector(isUILocked)]) {
        BOOL locked = ((BOOL (*)(id, SEL))objc_msgSend)(manager, @selector(isUILocked));
        if (locked != self.locked) {
            _locked = locked;
            NSLog(@"%@ Device %@", NNPLog, locked ? @"locked" : @"unlocked");
#if NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
            NNPDiagnosticSetBool(@"Locked", locked);
            NNPDiagnosticSetString(@"LastLockState", locked ? @"locked" : @"unlocked");
            NNPDiagnosticSetString(@"LastLockStateTimestamp", [[NSDate date] description]);
#endif
#if NNP_PHASE2D2_DIAGNOSTIC
            NNPDiagnosticLog([NSString stringWithFormat:@"LOCK_STATE locked=%d", locked]);
#endif
            [self reconcile];
        }
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
#if NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
    BOOL eligible = self.locked && self.state.hasTrack && self.state.playing && [self spotifyState:self.state];
    NNPDiagnosticSetBool(@"Locked", self.locked);
    NNPDiagnosticSetBool(@"SpotifyDetected", [self spotifyState:self.state]);
    NNPDiagnosticSetBool(@"PlaybackActive", self.state.playing);
    NNPDiagnosticSetBool(@"NowPlayingValid", self.state.hasTrack);
    NNPDiagnosticSetBool(@"EligibilityPassed", eligible);
#endif
#if NNP_PHASE2D2_DIAGNOSTIC
    BOOL readable = NO;
    BOOL armExists = NNPDiagnosticArmExists(&readable);
    if (armExists && !self.diagnosticAttempted) self.diagnosticArmed = YES;
    NNPDiagnosticLog([NSString stringWithFormat:@"ARM_CHECK exists=%d readable=%d", armExists, readable]);
    NNPDiagnosticLog([NSString stringWithFormat:@"RECONCILE armed=%d locked=%d playing=%d nowPlaying=%d", self.diagnosticArmed, self.locked, self.state.playing, self.state.hasTrack]);
    if (self.diagnosticArmed && !self.diagnosticAttempted && self.locked && self.state.playing && self.state.hasTrack && [self spotifyState:self.state]) {
        self.diagnosticAttempted = YES;
        self.diagnosticArmed = NO;
        NNPDiagnosticLog(@"ASSERTION_WOULD_BE_ATTEMPTED");
        NNPDiagnosticConsumeArm();
    }
#endif
#if NNP_ENABLE_DISPLAY_ASSERTION_EXPERIMENT
    if (self.displayAssertion) {
        [self.displayAssertion refreshManualArming];
        if (eligible && !self.displayAssertion.assertionActive) {
            [self.displayAssertion attemptTemporaryAssertion];
        } else if (!eligible) {
            NSString *reason = self.locked ? @"playback_stopped_or_state_invalid" : @"unlock";
            [self.displayAssertion releaseAssertionWithReason:reason];
        }
    }
#endif
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
    if (self.window && self.window.hidden) self.window.hidden = NO;
    if (self.window && self.window.alpha < 1.0) self.window.alpha = 1.0;
    NSTimeInterval elapsed = state.elapsed;
    if (state.playing && state.playbackRate > 0 && state.timestamp > 0) elapsed += MAX(0, NSDate.date.timeIntervalSince1970 - state.timestamp) * state.playbackRate;
    [self.view updateElapsed:elapsed duration:state.duration playing:state.playing];
    self.ticks += 1;
#if !NNP_SAFE_BOOT_TEST
    if (self.ticks % 10 == 0) [self.media refresh];
#endif
}
@end
