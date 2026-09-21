#import "NNPController.h"
#import "NNPMediaController.h"
#import "NNPState.h"
#import "NNPView.h"
#import "NNPPreferences.h"
#import "NNPLockStateController.h"
#import "NNPDisplayController.h"
#import "NNPDiagnostics.h"
#import <UIKit/UIKit.h>

static NSString * const NNPLog = @"[NotchNowPlaying]";
static NSString * const NNPSpotify = @"com.spotify.client";

@interface NNPController ()
@property(nonatomic, strong) NNPMediaController *media;
@property(nonatomic, strong) NNPLockStateController *lockState;
@property(nonatomic, strong) NNPDisplayController *display;
@property(nonatomic, strong) NNPPreferences *preferences;
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) NNPView *view;
@property(nonatomic, strong) NNPState *state;
@property(nonatomic, strong) NSTimer *progressTimer;
@property(nonatomic) BOOL locked;
@property(nonatomic) BOOL installed;
@end

@implementation NNPController
+ (instancetype)sharedController { static NNPController *controller; static dispatch_once_t once; dispatch_once(&once, ^{ controller = [self new]; }); return controller; }
- (void)install {
    if (_installed) return; _installed = YES;
    self.preferences = [NNPPreferences sharedPreferences]; [self.preferences startObserving];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(preferencesChanged:) name:NNPPreferencesDidChangeNotification object:self.preferences];
    self.display = [NNPDisplayController new]; self.lockState = [NNPLockStateController new];
    __weak typeof(self) weakSelf = self;
    self.lockState.stateHandler = ^(BOOL locked) { [weakSelf setLocked:locked]; };
    [self.lockState start]; self.locked = self.lockState.isLocked;
    NNPDiagnosticSetBool(@"ControllerInitialized", YES); NNPDiagnosticSetBool(@"LogicalLockState", self.locked);
#if NNP_SAFE_BOOT_TEST
    NSLog(@"%@ safe boot build loaded; media and UI disabled", NNPLog); return;
#else
    self.media = [NNPMediaController new]; self.media.stateHandler = ^(NNPState *state) { [weakSelf receive:state]; };
    [self.media start]; NNPDiagnosticSetBool(@"MediaRemoteConnected", YES);
    NSLog(@"%@ loaded, locked=%@", NNPLog, self.locked ? @"YES" : @"NO");
#endif
}
- (void)preferencesChanged:(NSNotification *)note { [self.preferences reload]; [self reconcile]; }
- (void)refreshDiagnosticUI { [self reconcile]; }
- (void)setLocked:(BOOL)locked { if (_locked == locked) return; _locked = locked; NNPDiagnosticSetBool(@"LogicalLockState", locked); NSLog(@"%@ device %@", NNPLog, locked ? @"locked" : @"unlocked"); [self reconcile]; }
- (void)receive:(NNPState *)state { dispatch_async(dispatch_get_main_queue(), ^{ self.state = state; NNPDiagnosticSetString(@"ActiveMediaBundle", state.bundleIdentifier ?: @""); NNPDiagnosticSetBool(@"SpotifyDetected", [self isAllowedMedia:state]); NNPDiagnosticSetBool(@"PlaybackActive", state.playing); [self reconcile]; }); }
- (BOOL)isAllowedMedia:(NNPState *)state { if (!state.bundleIdentifier.length) return NO; return !self.preferences.spotifyOnly || [state.bundleIdentifier isEqualToString:NNPSpotify]; }
- (BOOL)shouldShow { NNPState *state = self.state; if (!self.preferences.enabled || !state.hasTrack || ![self isAllowedMedia:state]) return NO; if (self.locked && !self.preferences.showOnLockScreen) return NO; if (!self.locked && !self.preferences.showWhileUnlocked) return NO; if (!state.playing && self.preferences.hideWhenPaused) return NO; return YES; }
- (void)makeWindow {
    if (self.window) return;
    UIWindowScene *scene = nil; for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) { if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState != UISceneActivationStateUnattached) { scene = (UIWindowScene *)candidate; break; } }
    self.window = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; self.window.frame = UIScreen.mainScreen.bounds; self.window.windowLevel = UIWindowLevelStatusBar + 1.0; self.window.backgroundColor = UIColor.clearColor; self.window.userInteractionEnabled = NO;
    UIViewController *root = [UIViewController new]; root.view.backgroundColor = UIColor.clearColor; root.view.userInteractionEnabled = NO; self.view = [[NNPView alloc] initWithFrame:self.window.bounds]; self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [root.view addSubview:self.view]; self.window.rootViewController = root; self.window.hidden = YES;
}
- (void)applyViewPreferences { self.view.showArtwork = self.preferences.showArtwork; self.view.showArtist = self.preferences.showArtist; self.view.showProgress = self.preferences.showProgress; self.view.artworkSize = self.preferences.artworkSize; self.view.cornerRadius = self.preferences.cornerRadius; self.view.textSize = self.preferences.textSize; self.view.progressHeight = self.preferences.progressHeight; [self.view setNeedsLayout]; }
- (void)reconcile { dispatch_async(dispatch_get_main_queue(), ^{ BOOL show = [self shouldShow]; NNPDiagnosticSetBool(@"UIVisible", show); if (!show) { [self hide]; return; } [self makeWindow]; [self applyViewPreferences]; [self.view updateState:self.state]; if (self.window.hidden) { self.window.hidden = NO; NSLog(@"%@ overlay shown", NNPLog); } [self startProgressTimer]; [self updateProgress]; }); }
- (void)hide { if (!self.window.hidden) { self.window.hidden = YES; NSLog(@"%@ overlay hidden", NNPLog); } [self.progressTimer invalidate]; self.progressTimer = nil; }
- (void)startProgressTimer { if (self.progressTimer) return; __weak typeof(self) weakSelf = self; self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:self.preferences.progressUpdateInterval repeats:YES block:^(__unused NSTimer *timer) { [weakSelf updateProgress]; }]; }
- (void)updateProgress { if (!self.state || self.window.hidden) return; NSTimeInterval elapsed = self.state.elapsed; if (self.state.playing && self.state.playbackRate > 0.0 && self.state.timestamp > 0.0) elapsed += MAX(0.0, NSDate.date.timeIntervalSince1970 - self.state.timestamp) * self.state.playbackRate; if (self.state.duration > 0.0) elapsed = MIN(self.state.duration, MAX(0.0, elapsed)); [self.view updateElapsed:elapsed duration:self.state.duration playing:self.state.playing]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_lockState stop]; [_progressTimer invalidate]; }
@end
