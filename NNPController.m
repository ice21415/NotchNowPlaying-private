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

#ifndef NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
#define NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE 0
#endif
#ifndef NNP_ENABLE_COVERSHEET_PRESENTATION
#define NNP_ENABLE_COVERSHEET_PRESENTATION 0
#endif

@interface NNPBlackoutView : UIView
@property(nonatomic, copy) void (^revealHandler)(void);
@end

@implementation NNPBlackoutView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat cornerWidth = MIN(120.0, width * 0.34);
    CGFloat cornerHeight = MIN(170.0, height * 0.24);
    BOOL bottomCorner = point.y >= height - cornerHeight &&
        (point.x <= cornerWidth || point.x >= width - cornerWidth);
    BOOL bottomCenter = point.y >= height - cornerHeight &&
        point.x > cornerWidth && point.x < width - cornerWidth;
    if (bottomCenter && !self.hidden && event && event.type == UIEventTypeTouches && self.revealHandler) {
        self.revealHandler();
        return nil;
    }
    return bottomCorner ? self : nil;
}
@end

@interface NNPController ()
@property(nonatomic, strong) NNPMediaController *media;
@property(nonatomic, strong) NNPLockStateController *lockState;
@property(nonatomic, strong) NNPDisplayController *display;
@property(nonatomic, strong) NNPPreferences *preferences;
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) NNPView *view;
@property(nonatomic, strong) NNPState *state;
@property(nonatomic, strong) NSTimer *progressTimer;
@property(nonatomic, weak) UIView *coverSheetHostView;
@property(nonatomic, strong) UIView *coverSheetBlackoutView;
@property(nonatomic, strong) UIView *statusBarBlackoutView;
@property(nonatomic, weak) UIWindow *statusBarBlackoutWindow;
@property(nonatomic, strong) UIButton *coverSheetControlsToggle;
@property(nonatomic) BOOL coverSheetHostUnavailableRecorded;
@property(nonatomic) BOOL coverSheetBlackoutRevealed;
@property(nonatomic) BOOL locked;
@property(nonatomic) BOOL installed;
- (void)revealCoverSheetControls;
- (void)revealCoverSheetControlsWithReason:(NSString *)reason;
@end

@implementation NNPController
+ (instancetype)sharedController { static NNPController *controller; static dispatch_once_t once; dispatch_once(&once, ^{ controller = [self new]; }); return controller; }
- (void)recordPresentationDiagnostics:(NSString *)reason {
    UIApplication *application = UIApplication.sharedApplication;
    UIScreen *screen = UIScreen.mainScreen;
    NSInteger visibleWindows = 0;
    NSInteger opaqueVisibleWindows = 0;
    NSMutableArray<UIWindow *> *visibleWindowList = [NSMutableArray array];
    NSMutableArray<NSString *> *sceneSummaries = [NSMutableArray array];
    NSUInteger sceneIndex = 0;
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        NSString *sceneRole = windowScene.session.role ?: @"unknown";
        [sceneSummaries addObject:[NSString stringWithFormat:@"%lu:%@ state=%ld windows=%lu key=%@", (unsigned long)sceneIndex, sceneRole, (long)windowScene.activationState, (unsigned long)windowScene.windows.count, windowScene.keyWindow ? NSStringFromClass(windowScene.keyWindow.class) : @"none"]];
        for (UIWindow *candidate in windowScene.windows) {
            if (candidate.hidden || candidate.alpha <= 0.01) continue;
            visibleWindows += 1;
            [visibleWindowList addObject:candidate];
            CGFloat backgroundAlpha = candidate.backgroundColor ? CGColorGetAlpha(candidate.backgroundColor.CGColor) : 0.0;
            if (candidate.opaque || backgroundAlpha >= 0.99) opaqueVisibleWindows += 1;
        }
        sceneIndex += 1;
    }
    NSInteger connectedScenes = application.connectedScenes.count;
    CGFloat screenBrightness = screen.brightness;
    UIWindowScene *presentationScene = self.window.windowScene;
    NSInteger presentationSceneState = presentationScene ? presentationScene.activationState : UISceneActivationStateUnattached;
    NSInteger presentationSceneWindowCount = presentationScene ? presentationScene.windows.count : 0;
    NNPDiagnosticSetInteger(@"PresentationVisibleWindowCount", visibleWindows);
    NNPDiagnosticSetInteger(@"PresentationOpaqueWindowCount", opaqueVisibleWindows);
    NNPDiagnosticSetInteger(@"PresentationConnectedSceneCount", connectedScenes);
    NNPDiagnosticSetDouble(@"PresentationUIScreenBrightness", screenBrightness);
    NNPDiagnosticSetDouble(@"PresentationUIScreenScale", screen.scale);
    NNPDiagnosticSetBool(@"PresentationScreenBrightnessNonzero", screenBrightness > 0.001);
    NNPDiagnosticSetInteger(@"PresentationSceneActivationState", presentationSceneState);
    NNPDiagnosticSetInteger(@"PresentationSceneWindowCount", presentationSceneWindowCount);
    NNPDiagnosticSetBool(@"PresentationWindowVisible", !self.window.hidden);
    NNPDiagnosticSetBool(@"PresentationWindowOpaque", self.window.opaque);
    NNPDiagnosticSetBool(@"PresentationRootOpaque", self.window.rootViewController.view.opaque);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"CONTROLLER presentation snapshot reason=%@ locked=%@ visibleWindows=%ld opaqueWindows=%ld scenes=%ld UIKitBrightness=%.4f sceneState=%ld sceneWindows=%ld windowVisible=%@ windowLevel=%.1f windowOpaque=%@ rootOpaque=%@ expectedBlack=%@", reason ?: @"unknown", self.locked ? @"YES" : @"NO", (long)visibleWindows, (long)opaqueVisibleWindows, (long)connectedScenes, screenBrightness, (long)presentationSceneState, (long)presentationSceneWindowCount, self.window.hidden ? @"NO" : @"YES", self.window.windowLevel, self.window.opaque ? @"YES" : @"NO", self.window.rootViewController.view.opaque ? @"YES" : @"NO", self.locked ? @"YES" : @"NO"]);

    [visibleWindowList sortUsingComparator:^NSComparisonResult(UIWindow *left, UIWindow *right) {
        if (left.windowLevel > right.windowLevel) return NSOrderedAscending;
        if (left.windowLevel < right.windowLevel) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"WINDOW_DIAGNOSTIC scenes=[%@] visibleTopDown=YES", [sceneSummaries componentsJoinedByString:@" | "]]);
    for (NSUInteger index = 0; index < visibleWindowList.count; index++) {
        UIWindow *candidate = visibleWindowList[index];
        UIWindowScene *scene = candidate.windowScene;
        NSString *marker = candidate == self.window ? @"PLUGIN" : @"SYSTEM";
        NSString *rootClass = candidate.rootViewController ? NSStringFromClass(candidate.rootViewController.class) : @"none";
        NSString *sceneRole = scene.session.role ?: @"unknown";
        NSUInteger rootSubviewCount = candidate.rootViewController.isViewLoaded ? candidate.rootViewController.view.subviews.count : 0;
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"WINDOW_DIAGNOSTIC order=%lu/%lu kind=%@ class=%@ level=%.1f key=%@ hidden=%@ alpha=%.2f opaque=%@ z=%.1f frame=%@ scene=%@ sceneState=%ld root=%@ rootSubviews=%lu", (unsigned long)(index + 1), (unsigned long)visibleWindowList.count, marker, NSStringFromClass(candidate.class), candidate.windowLevel, candidate.isKeyWindow ? @"YES" : @"NO", candidate.hidden ? @"YES" : @"NO", candidate.alpha, candidate.opaque ? @"YES" : @"NO", candidate.layer.zPosition, NSStringFromCGRect(candidate.frame), sceneRole, (long)scene.activationState, rootClass, (unsigned long)rootSubviewCount]);
    }
    if (self.view) {
        NSMutableArray<NSString *> *contentViews = [NSMutableArray array];
        for (UIView *subview in self.view.subviews) {
            [contentViews addObject:[NSString stringWithFormat:@"%@ hidden=%@ alpha=%.2f frame=%@", NSStringFromClass(subview.class), subview.hidden ? @"YES" : @"NO", subview.alpha, NSStringFromCGRect(subview.frame)]];
        }
        NSString *attachment = self.view.window == self.window ? @"plugin-window" : (self.coverSheetHostView && self.view.superview == self.coverSheetHostView ? @"coversheet-root" : @"other-or-detached");
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"WINDOW_DIAGNOSTIC pluginContent attachment=%@ attachedWindow=%@ viewHidden=%@ viewAlpha=%.2f viewBounds=%@ childViews=[%@]", attachment, self.view.window ? NSStringFromClass(self.view.window.class) : @"none", self.view.hidden ? @"YES" : @"NO", self.view.alpha, NSStringFromCGRect(self.view.bounds), [contentViews componentsJoinedByString:@" | "]]);
    }
}
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
- (void)setLocked:(BOOL)locked { if (_locked == locked) { NNPDiagnosticLogTransition([NSString stringWithFormat:@"CONTROLLER lock state unchanged value=%@", locked ? @"YES" : @"NO"]); return; } _locked = locked; NNPDiagnosticSetBool(@"LogicalLockState", locked); NSLog(@"%@ device %@", NNPLog, locked ? @"locked" : @"unlocked"); NNPDiagnosticLogTransition([NSString stringWithFormat:@"CONTROLLER self.locked=%@", locked ? @"YES" : @"NO"]); [self recordPresentationDiagnostics:locked ? @"logical-lock" : @"logical-unlock"]; [self reconcile]; }
- (void)receive:(NNPState *)state { dispatch_async(dispatch_get_main_queue(), ^{ self.state = state; NNPDiagnosticSetString(@"ActiveMediaBundle", state.bundleIdentifier ?: @""); NNPDiagnosticSetBool(@"SpotifyDetected", [self isAllowedMedia:state]); NNPDiagnosticSetBool(@"PlaybackActive", state.playing); [self reconcile]; }); }
- (BOOL)isAllowedMedia:(NNPState *)state { if (!state.bundleIdentifier.length) return NO; return !self.preferences.spotifyOnly || [state.bundleIdentifier isEqualToString:NNPSpotify]; }
- (BOOL)shouldShow { NNPState *state = self.state; if (!self.preferences.enabled || !state.hasTrack || ![self isAllowedMedia:state]) return NO; if (self.locked && !self.preferences.showOnLockScreen) return NO; if (!self.locked && !self.preferences.showWhileUnlocked) return NO; if (!state.playing && self.preferences.hideWhenPaused) return NO; return YES; }
- (void)makeWindow {
    if (self.window) return;
    UIWindowScene *scene = nil; for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) { if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState != UISceneActivationStateUnattached) { scene = (UIWindowScene *)candidate; break; } }
    self.window = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; self.window.frame = UIScreen.mainScreen.bounds; self.window.windowLevel = UIWindowLevelStatusBar + 1.0; self.window.backgroundColor = UIColor.clearColor; self.window.userInteractionEnabled = NO; self.window.clipsToBounds = YES;
    UIViewController *root = [UIViewController new]; root.view.backgroundColor = UIColor.clearColor; root.view.opaque = NO; root.view.userInteractionEnabled = NO; self.view = [[NNPView alloc] initWithFrame:self.window.bounds]; self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [root.view addSubview:self.view]; self.window.rootViewController = root; self.window.hidden = YES;
}
- (UIView *)visibleCoverSheetRootView {
#if NNP_ENABLE_COVERSHEET_PRESENTATION && NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
    UIWindowScene *scene = self.window.windowScene;
    if (!scene || scene.activationState == UISceneActivationStateUnattached) return nil;
    Class expectedControllerClass = NSClassFromString(@"SBCoverSheetPrimarySlidingViewController");
    if (!expectedControllerClass) return nil;
    for (UIWindow *candidate in scene.windows) {
        if (candidate.hidden || candidate.alpha <= 0.01 ||
            ![NSStringFromClass(candidate.class) isEqualToString:@"SBCoverSheetWindow"] ||
            ![candidate.rootViewController isKindOfClass:expectedControllerClass] ||
            !candidate.rootViewController.isViewLoaded) continue;
        UIView *rootView = candidate.rootViewController.view;
        if (rootView.window != candidate || CGRectIsEmpty(rootView.bounds)) continue;
        return rootView;
    }
#endif
    return nil;
}
- (UIWindow *)visibleStatusBarWindow {
#if NNP_ENABLE_COVERSHEET_PRESENTATION && NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
    for (UIWindow *candidate in self.window.windowScene.windows) {
        if (!candidate.hidden && candidate.alpha > 0.01 &&
            [NSStringFromClass(candidate.class) isEqualToString:@"SBStatusBarWindow"]) return candidate;
    }
#endif
    return nil;
}
- (void)removeCoverSheetBlackout {
    [self.coverSheetBlackoutView removeFromSuperview];
    self.coverSheetBlackoutView = nil;
    [self.statusBarBlackoutView removeFromSuperview];
    self.statusBarBlackoutView = nil;
    self.statusBarBlackoutWindow = nil;
    [self.coverSheetControlsToggle removeFromSuperview];
    self.coverSheetControlsToggle = nil;
    self.coverSheetBlackoutRevealed = NO;
    NNPDiagnosticSetBool(@"CoverSheetBlackoutActive", NO);
    NNPDiagnosticSetBool(@"StatusBarBlackoutActive", NO);
    NNPDiagnosticSetBool(@"CoverSheetControlsRevealed", NO);
}
- (void)installCoverSheetBlackoutForHost:(UIView *)host {
    if (!self.coverSheetBlackoutView) {
        self.coverSheetBlackoutView = [[NNPBlackoutView alloc] initWithFrame:host.bounds];
        self.coverSheetBlackoutView.backgroundColor = UIColor.blackColor;
        self.coverSheetBlackoutView.opaque = YES;
        self.coverSheetBlackoutView.userInteractionEnabled = YES;
        self.coverSheetBlackoutView.accessibilityElementsHidden = YES;
        self.coverSheetBlackoutView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        __weak typeof(self) weakSelf = self;
        ((NNPBlackoutView *)self.coverSheetBlackoutView).revealHandler = ^{ [weakSelf revealCoverSheetControls]; };
    }
    if (self.coverSheetBlackoutView.superview != host) [host addSubview:self.coverSheetBlackoutView];
    self.coverSheetBlackoutView.frame = host.bounds;
    self.coverSheetBlackoutView.hidden = self.coverSheetBlackoutRevealed;

    UIWindow *statusWindow = [self visibleStatusBarWindow];
    if (self.statusBarBlackoutWindow != statusWindow) {
        [self.statusBarBlackoutView removeFromSuperview];
        self.statusBarBlackoutView = nil;
        self.statusBarBlackoutWindow = statusWindow;
    }
    if (statusWindow) {
        if (!self.statusBarBlackoutView) {
            self.statusBarBlackoutView = [[UIView alloc] initWithFrame:CGRectZero];
            self.statusBarBlackoutView.backgroundColor = UIColor.blackColor;
            self.statusBarBlackoutView.opaque = YES;
            self.statusBarBlackoutView.userInteractionEnabled = NO;
            self.statusBarBlackoutView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        }
        if (self.statusBarBlackoutView.superview != statusWindow) [statusWindow addSubview:self.statusBarBlackoutView];
        CGFloat statusMaskHeight = MIN(40.0, CGRectGetHeight(statusWindow.bounds));
        self.statusBarBlackoutView.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(statusWindow.bounds), statusMaskHeight);
        self.statusBarBlackoutView.hidden = self.coverSheetBlackoutRevealed;
        [statusWindow bringSubviewToFront:self.statusBarBlackoutView];
        NNPDiagnosticSetBool(@"StatusBarBlackoutActive", !self.coverSheetBlackoutRevealed);
    } else {
        [self.statusBarBlackoutView removeFromSuperview];
        self.statusBarBlackoutView = nil;
        self.statusBarBlackoutWindow = nil;
        NNPDiagnosticSetBool(@"StatusBarBlackoutActive", NO);
    }

    if (!self.coverSheetControlsToggle) {
        self.coverSheetControlsToggle = [UIButton buttonWithType:UIButtonTypeCustom];
        self.coverSheetControlsToggle.backgroundColor = UIColor.clearColor;
        self.coverSheetControlsToggle.accessibilityLabel = @"切換鎖定畫面控制項";
        self.coverSheetControlsToggle.accessibilityHint = @"點按播放資訊區，顯示或隱藏原鎖定畫面內容";
        [self.coverSheetControlsToggle addTarget:self action:@selector(toggleCoverSheetBlackout:) forControlEvents:UIControlEventTouchUpInside];
    }
    self.coverSheetControlsToggle.frame = CGRectMake(0.0, 40.0, CGRectGetWidth(host.bounds), 82.0);
    self.coverSheetControlsToggle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    if (self.coverSheetControlsToggle.superview != host) [host addSubview:self.coverSheetControlsToggle];

    [host bringSubviewToFront:self.coverSheetBlackoutView];
    [host bringSubviewToFront:self.view];
    [host bringSubviewToFront:self.coverSheetControlsToggle];
    NNPDiagnosticSetBool(@"CoverSheetBlackoutActive", !self.coverSheetBlackoutRevealed);
    NNPDiagnosticSetBool(@"CoverSheetControlsRevealed", self.coverSheetBlackoutRevealed);
}
- (void)toggleCoverSheetBlackout:(__unused UIButton *)sender {
    if (!self.coverSheetHostView || !self.coverSheetBlackoutView) return;
    self.coverSheetBlackoutRevealed = !self.coverSheetBlackoutRevealed;
    self.coverSheetBlackoutView.hidden = self.coverSheetBlackoutRevealed;
    self.statusBarBlackoutView.hidden = self.coverSheetBlackoutRevealed;
    NNPDiagnosticSetBool(@"CoverSheetBlackoutActive", !self.coverSheetBlackoutRevealed);
    NNPDiagnosticSetBool(@"StatusBarBlackoutActive", self.statusBarBlackoutView && !self.coverSheetBlackoutRevealed);
    NNPDiagnosticSetBool(@"CoverSheetControlsRevealed", self.coverSheetBlackoutRevealed);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"COVERSHEET blackout=%@ controlsRevealed=%@ reason=player-area-tap", self.coverSheetBlackoutRevealed ? @"NO" : @"YES", self.coverSheetBlackoutRevealed ? @"YES" : @"NO"]);
}
- (void)revealCoverSheetControls {
    [self revealCoverSheetControlsWithReason:@"bottom-center-unlock-gesture"];
}
- (void)revealCoverSheetControlsForWake {
    if (!self.locked || !self.coverSheetHostView || !self.coverSheetBlackoutView) return;
    [self revealCoverSheetControlsWithReason:@"side-button-wake"];
}
- (void)revealCoverSheetControlsWithReason:(NSString *)reason {
    if (!self.coverSheetHostView || !self.coverSheetBlackoutView || self.coverSheetBlackoutRevealed) return;
    self.coverSheetBlackoutRevealed = YES;
    self.coverSheetBlackoutView.hidden = YES;
    self.statusBarBlackoutView.hidden = YES;
    NNPDiagnosticSetBool(@"CoverSheetBlackoutActive", NO);
    NNPDiagnosticSetBool(@"StatusBarBlackoutActive", NO);
    NNPDiagnosticSetBool(@"CoverSheetControlsRevealed", YES);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"COVERSHEET blackout=NO controlsRevealed=YES reason=%@", reason ?: @"unknown"]);
}
- (BOOL)shouldPresentInsideCoverSheet {
#if NNP_ENABLE_COVERSHEET_PRESENTATION && NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
    return self.locked && self.preferences.experimentalLockedVisible && self.preferences.enabled &&
        self.preferences.showOnLockScreen && self.state.hasTrack && self.state.playing &&
        [self isAllowedMedia:self.state] && self.display.lifecycleState == NNPDisplayLifecycleStateActive;
#else
    return NO;
#endif
}
- (void)updateCoverSheetPresentation {
#if NNP_ENABLE_COVERSHEET_PRESENTATION && NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
    BOOL eligible = [self shouldPresentInsideCoverSheet];
    UIView *target = eligible ? [self visibleCoverSheetRootView] : nil;
    if (eligible && !target && !self.coverSheetHostUnavailableRecorded) {
        self.coverSheetHostUnavailableRecorded = YES;
        NNPDiagnosticSetBool(@"CoverSheetPresentationActive", NO);
        NNPDiagnosticSetString(@"CoverSheetPresentationHost", @"unavailable-or-unexpected-class");
        NNPDiagnosticLogTransition(@"COVERSHEET presentation skipped; expected visible SBCoverSheetWindow with SBCoverSheetPrimarySlidingViewController in the plugin scene");
    } else if (target) {
        self.coverSheetHostUnavailableRecorded = NO;
        NNPDiagnosticSetString(@"CoverSheetPresentationHost", @"SBCoverSheetPrimarySlidingViewController");
    } else if (!eligible) {
        self.coverSheetHostUnavailableRecorded = NO;
    }
    if (target == self.coverSheetHostView && self.view.superview == target) {
        [self installCoverSheetBlackoutForHost:target];
        return;
    }

    UIView *previousHost = self.coverSheetHostView;
    if (self.coverSheetHostView || self.view.superview != self.window.rootViewController.view) {
        [self removeCoverSheetBlackout];
        [self.view removeFromSuperview];
        self.coverSheetHostView = nil;
        UIView *pluginRoot = self.window.rootViewController.view;
        self.view.frame = pluginRoot.bounds;
        self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [pluginRoot addSubview:self.view];
        if (!target) {
            NNPDiagnosticSetBool(@"CoverSheetPresentationActive", NO);
            NNPDiagnosticLogTransition([NSString stringWithFormat:@"COVERSHEET presentation detached reason=%@", previousHost ? @"eligibility-ended-or-host-replaced" : @"host-unavailable"]);
        }
    }

    if (target) {
        [self.view removeFromSuperview];
        self.view.frame = target.bounds;
        self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.view.backgroundColor = UIColor.clearColor;
        self.view.userInteractionEnabled = NO;
        [target addSubview:self.view];
        self.coverSheetHostView = target;
        [self installCoverSheetBlackoutForHost:target];
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
        NNPDiagnosticSetBool(@"CoverSheetPresentationActive", YES);
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"COVERSHEET presentation attached host=%@ hostBounds=%@ viewFrame=%@ interactive=NO blackout=YES statusBarWindow=%@", NSStringFromClass(target.window.rootViewController.class), NSStringFromCGRect(target.bounds), NSStringFromCGRect(self.view.frame), self.statusBarBlackoutWindow ? @"masked-top-40pt" : @"unavailable"]);
    } else if (previousHost || self.coverSheetBlackoutView || self.statusBarBlackoutView) {
        [self removeCoverSheetBlackout];
    }
#endif
}
- (void)applyLockedBackground {
    BOOL dedicatedBlackPresentation = self.locked;
    UIColor *background = dedicatedBlackPresentation ? UIColor.blackColor : UIColor.clearColor;
    self.window.opaque = dedicatedBlackPresentation;
    self.window.backgroundColor = background;
    self.window.rootViewController.view.opaque = dedicatedBlackPresentation;
    self.window.rootViewController.view.backgroundColor = background;
    self.view.backgroundColor = self.coverSheetHostView && self.view.superview == self.coverSheetHostView ? UIColor.clearColor : background;
    NNPDiagnosticSetBool(@"PresentationDedicatedBlack", dedicatedBlackPresentation);
    [self recordPresentationDiagnostics:dedicatedBlackPresentation ? @"black-presentation" : @"transparent-presentation"];
}
- (void)applyViewPreferences { self.view.showArtwork = self.preferences.showArtwork; self.view.showArtist = self.preferences.showArtist; self.view.showProgress = self.preferences.showProgress; self.view.artworkSize = self.preferences.artworkSize; self.view.cornerRadius = self.preferences.cornerRadius; self.view.textSize = self.preferences.textSize; self.view.progressHeight = self.preferences.progressHeight; [self.view setNeedsLayout]; }
- (void)reconcile { dispatch_async(dispatch_get_main_queue(), ^{ BOOL show = [self shouldShow]; NNPDiagnosticSetBool(@"UIVisible", show);
#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
        self.display.deviceLocked = self.locked;
        self.display.maximumDuration = self.preferences.experimentalMaxDuration;
        BOOL experimentEligible = self.preferences.experimentalLockedVisible && self.preferences.enabled && self.state.hasTrack && self.state.playing && [self isAllowedMedia:self.state] && (self.locked ? self.preferences.showOnLockScreen : self.preferences.showWhileUnlocked);
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"CONTROLLER reconcile locked=%@ show=%@ experimentEligible=%@ lifecycle=%ld", self.locked ? @"YES" : @"NO", show ? @"YES" : @"NO", experimentEligible ? @"YES" : @"NO", (long)self.display.lifecycleState]);
        if (experimentEligible) { [self.display startLockedVisibleMode]; } else { [self.display stopLockedVisibleMode]; }
#endif
        if (!show) { [self hide]; return; } [self makeWindow]; [self applyViewPreferences]; [self.view updateState:self.state]; [self updateCoverSheetPresentation]; [self applyLockedBackground];
        if (self.window.hidden) { self.window.hidden = NO; NSLog(@"%@ overlay shown", NNPLog); NNPDiagnosticLogTransition(@"CONTROLLER window visible=YES"); [self recordPresentationDiagnostics:@"window-visible"]; } [self startProgressTimer]; [self updateProgress]; }); }
- (void)hide {
#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
    [self.display stopLockedVisibleMode];
#endif
    [self updateCoverSheetPresentation];
    if (!self.window.hidden) { self.window.hidden = YES; NSLog(@"%@ overlay hidden", NNPLog); NNPDiagnosticLogTransition(@"CONTROLLER window visible=NO cleanup"); }
    [self.progressTimer invalidate]; self.progressTimer = nil;
}
- (void)startProgressTimer { if (self.progressTimer) return; __weak typeof(self) weakSelf = self; self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:self.preferences.progressUpdateInterval repeats:YES block:^(__unused NSTimer *timer) { [weakSelf updateProgress]; }]; }
- (void)updateProgress { if (!self.state || self.window.hidden) return; [self updateCoverSheetPresentation]; NSTimeInterval elapsed = self.state.elapsed; if (self.state.playing && self.state.playbackRate > 0.0 && self.state.timestamp > 0.0) elapsed += MAX(0.0, NSDate.date.timeIntervalSince1970 - self.state.timestamp) * self.state.playbackRate; if (self.state.duration > 0.0) elapsed = MIN(self.state.duration, MAX(0.0, elapsed)); [self.view updateElapsed:elapsed duration:self.state.duration playing:self.state.playing]; }
- (void)dealloc {
#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
    [_display stopLockedVisibleMode];
#endif
    [[NSNotificationCenter defaultCenter] removeObserver:self]; [_lockState stop]; [_progressTimer invalidate];
}
@end
