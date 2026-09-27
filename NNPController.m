#import "NNPController.h"
#import "NNPMediaController.h"
#import "NNPState.h"
#import "NNPView.h"
#import "NNPPreferences.h"
#import "NNPLockStateController.h"
#import "NNPDisplayController.h"
#import "NNPDiagnostics.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import <stdlib.h>

static NSString * const NNPLog = @"[NotchNowPlaying]";
static NSString * const NNPSpotify = @"com.spotify.client";
static NSString *NNPNormalizedTrackTitle(NSString *title) {
    NSString *folded = [(title ?: @"") stringByFoldingWithOptions:NSDiacriticInsensitiveSearch | NSCaseInsensitiveSearch | NSWidthInsensitiveSearch
                                                            locale:NSLocale.currentLocale];
    NSMutableString *normalized = [NSMutableString string];
    NSCharacterSet *lettersAndDigits = NSCharacterSet.alphanumericCharacterSet;
    [folded enumerateSubstringsInRange:NSMakeRange(0, folded.length)
                               options:NSStringEnumerationByComposedCharacterSequences
                            usingBlock:^(NSString *substring, __unused NSRange substringRange,
                                         __unused NSRange enclosingRange, __unused BOOL *stop) {
        if ([substring rangeOfCharacterFromSet:lettersAndDigits].location != NSNotFound)
            [normalized appendString:substring];
    }];
    return normalized;
}
static BOOL NNPTrackTitleMatches(NSString *mediaTitle, NSString *lyricsTitle) {
    NSString *media = NNPNormalizedTrackTitle(mediaTitle);
    NSString *lyrics = NNPNormalizedTrackTitle(lyricsTitle);
    if (!media.length || !lyrics.length) return media.length == lyrics.length;
    if ([media isEqualToString:lyrics]) return YES;
    return MIN(media.length, lyrics.length) >= 4 &&
        ([media containsString:lyrics] || [lyrics containsString:media]);
}
@interface NNPController (TouchDiagnostics)
- (void)observeTouchEvent:(UIEvent *)event;
@end
static void (*NNPOriginalApplicationSendEvent)(id, SEL, UIEvent *);
static id (*NNPOriginalRequestUISensorMode)(id, SEL, id);
static void NNPApplicationSendEventReplacement(id application, SEL selector, UIEvent *event) {
    [[NNPController sharedController] observeTouchEvent:event];
    if (NNPOriginalApplicationSendEvent) NNPOriginalApplicationSendEvent(application, selector, event);
}
static BOOL NNPSensorModeBool(id mode, const char *selectorName) {
    SEL selector = sel_registerName(selectorName);
    return mode && [mode respondsToSelector:selector]
        ? ((BOOL (*)(id, SEL))objc_msgSend)(mode, selector) : NO;
}
static long long NNPSensorModeInteger(id mode, const char *selectorName) {
    SEL selector = sel_registerName(selectorName);
    return mode && [mode respondsToSelector:selector]
        ? ((long long (*)(id, SEL))objc_msgSend)(mode, selector) : -1;
}
static id NNPRequestUISensorModeReplacement(id service, SEL selector, id mode) {
    id result = NNPOriginalRequestUISensorMode ? NNPOriginalRequestUISensorMode(service, selector, mode) : nil;
    static NSUInteger requestCount = 0;
    if (++requestCount <= 30) {
        NSString *reason = [mode respondsToSelector:@selector(reason)] ? [mode reason] : @"unknown";
        NNPDiagnosticLogTransition([NSString stringWithFormat:
            @"TOUCH sensor mode request count=%lu reason=%@ display=%lld digitizer=%@ alwaysOn=%@ tapToWake=%@ wakeOnSwipe=%@ swipeThrough=%@ assertion=%@",
            (unsigned long)requestCount, reason, NNPSensorModeInteger(mode, "displayState"),
            NNPSensorModeBool(mode, "digitizerEnabled") ? @"YES" : @"NO",
            NNPSensorModeBool(mode, "alwaysOnGesturesEnabled") ? @"YES" : @"NO",
            NNPSensorModeBool(mode, "tapToWakeEnabled") ? @"YES" : @"NO",
            NNPSensorModeBool(mode, "wakeOnSwipeEnabled") ? @"YES" : @"NO",
            NNPSensorModeBool(mode, "wakeOnSwipeThroughEnabled") ? @"YES" : @"NO",
            result ? @"YES" : @"NO"]);
    }
    return result;
}

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

@interface NNPNotchGestureWindow : UIWindow
@property(nonatomic) CGRect touchRegion;
@end

@implementation NNPNotchGestureWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(self.touchRegion, point) && [super pointInside:point withEvent:event];
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
@property(nonatomic, strong) NSTimer *pixelShiftTimer;
@property(nonatomic) BOOL unlimitedMediaPausePending;
@property(nonatomic) NSUInteger unlimitedMediaPauseGeneration;
@property(nonatomic, weak) UIView *coverSheetHostView;
@property(nonatomic, strong) UIView *coverSheetBlackoutView;
@property(nonatomic, strong) UIView *statusBarBlackoutView;
@property(nonatomic, weak) UIWindow *statusBarBlackoutWindow;
@property(nonatomic, strong) UIView *statusBarPlayerContainer;
@property(nonatomic, strong) NNPView *statusBarPlayerView;
@property(nonatomic, strong) UIButton *coverSheetControlsToggle;
@property(nonatomic, strong) NNPNotchGestureWindow *notchGestureWindow;
@property(nonatomic) BOOL notchPanHandled;
@property(nonatomic) BOOL coverSheetHostUnavailableRecorded;
@property(nonatomic) BOOL coverSheetBlackoutRevealed;
@property(nonatomic) BOOL locked;
@property(nonatomic) BOOL installed;
- (void)applyLyricsPreferences;
- (void)revealCoverSheetControls;
- (void)revealCoverSheetControlsWithReason:(NSString *)reason;
- (void)clearLockedPresentationBackgroundForUnlock;
- (void)startAODPixelShiftTimer;
- (void)stopAODPixelShiftTimer;
- (void)applyRandomAODPixelShift;
- (void)updateUnlimitedMediaPauseWithEligibleMedia:(BOOL)mediaEligible activeSession:(BOOL)activeSession;
- (void)updateNotchGestureWindow;
- (void)removeNotchGestureWindow;
- (void)handleNotchTrackPan:(UIPanGestureRecognizer *)gesture;
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
    Method sendEventMethod = class_getInstanceMethod(UIApplication.class, @selector(sendEvent:));
    if (sendEventMethod && !NNPOriginalApplicationSendEvent) {
        NNPOriginalApplicationSendEvent = (void (*)(id, SEL, UIEvent *))method_setImplementation(
            sendEventMethod, (IMP)NNPApplicationSendEventReplacement);
        NNPDiagnosticSetBool(@"ApplicationTouchEventHookInstalled", NNPOriginalApplicationSendEvent != NULL);
    }
    Class sensorServiceClass = NSClassFromString(@"BKSHIDUISensorService");
    Method sensorRequestMethod = sensorServiceClass
        ? class_getInstanceMethod(sensorServiceClass, NSSelectorFromString(@"requestUISensorMode:")) : NULL;
    if (sensorRequestMethod && !NNPOriginalRequestUISensorMode) {
        NNPOriginalRequestUISensorMode = (id (*)(id, SEL, id))method_setImplementation(
            sensorRequestMethod, (IMP)NNPRequestUISensorModeReplacement);
        NNPDiagnosticSetBool(@"SensorModeRequestHookInstalled", NNPOriginalRequestUISensorMode != NULL);
    } else {
        NNPDiagnosticSetBool(@"SensorModeRequestHookInstalled", NO);
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(preferencesChanged:) name:NNPPreferencesDidChangeNotification object:self.preferences];
    self.display = [NNPDisplayController new]; self.lockState = [NNPLockStateController new];
    __weak typeof(self) weakSelf = self;
    self.display.stateChangedHandler = ^{
        NNPController *controller = weakSelf;
        if (!controller) return;
        void (^update)(void) = ^{
            if (!controller.display.aodPresentationActive) [controller hide];
            [controller reconcile];
        };
        if ([NSThread isMainThread]) update();
        else dispatch_async(dispatch_get_main_queue(), update);
    };
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
- (void)observeTouchEvent:(UIEvent *)event {
    if (event.type != UIEventTypeTouches || !self.locked ||
        !self.preferences.experimentalLockedVisible) return;
    static NSUInteger observedTouchCount = 0;
    for (UITouch *touch in event.allTouches) {
        if (touch.phase != UITouchPhaseBegan) continue;
        observedTouchCount++;
        if (observedTouchCount > 24) return;
        CGPoint location = [touch locationInView:touch.window];
        NNPDiagnosticLogTransition([NSString stringWithFormat:
            @"TOUCH UIKit began count=%lu aod=%@ window=%@ view=%@ x=%.1f y=%.1f",
            (unsigned long)observedTouchCount, self.display.aodPresentationActive ? @"YES" : @"NO",
            touch.window ? NSStringFromClass(touch.window.class) : @"none",
            touch.view ? NSStringFromClass(touch.view.class) : @"none", location.x, location.y]);
    }
}
- (void)preferencesChanged:(NSNotification *)note { [self.preferences reload]; [self reconcile]; }
- (void)refreshDiagnosticUI { [self reconcile]; }
- (void)setLocked:(BOOL)locked {
    if (_locked == locked) {
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"CONTROLLER lock state unchanged value=%@", locked ? @"YES" : @"NO"]);
        return;
    }
    _locked = locked;
    if (!locked) {
        [self clearLockedPresentationBackgroundForUnlock];
#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
        self.display.deviceLocked = NO;
#endif
        [self hide];
    }
    NNPDiagnosticSetBool(@"LogicalLockState", locked);
    NSLog(@"%@ device %@", NNPLog, locked ? @"locked" : @"unlocked");
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"CONTROLLER self.locked=%@", locked ? @"YES" : @"NO"]);
    [self recordPresentationDiagnostics:locked ? @"logical-lock" : @"logical-unlock"];
    [self reconcile];
}
- (void)receive:(NNPState *)state { dispatch_async(dispatch_get_main_queue(), ^{ self.state = state; NNPDiagnosticSetString(@"ActiveMediaBundle", state.bundleIdentifier ?: @""); NNPDiagnosticSetBool(@"SpotifyDetected", [self isAllowedMedia:state]); NNPDiagnosticSetBool(@"PlaybackActive", state.playing); [self reconcile]; }); }
- (BOOL)isAllowedMedia:(NNPState *)state { if (!state.bundleIdentifier.length) return NO; return !self.preferences.spotifyOnly || [state.bundleIdentifier isEqualToString:NNPSpotify]; }
- (BOOL)shouldShow {
    NNPState *state = self.state;
    if (!self.preferences.enabled || !state.hasTrack || ![self isAllowedMedia:state]) return NO;
    if (self.locked && !self.preferences.showOnLockScreen) return NO;
    if (!self.locked && !self.preferences.showWhileUnlocked) return NO;
    if (!state.playing && self.preferences.hideWhenPaused) return NO;
#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
    if (self.preferences.experimentalLockedVisible &&
        (!self.locked || !self.display.aodPresentationActive || self.display.lifecycleState != NNPDisplayLifecycleStateActive)) return NO;
#endif
    return YES;
}
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
    [self removeNotchGestureWindow];
    [self.coverSheetBlackoutView removeFromSuperview];
    self.coverSheetBlackoutView = nil;
    [self.statusBarBlackoutView removeFromSuperview];
    self.statusBarBlackoutView = nil;
    UIView *departingPlayer = self.statusBarPlayerContainer;
    if (departingPlayer.superview && !departingPlayer.hidden) {
        NSTimeInterval duration = UIAccessibilityIsReduceMotionEnabled() ? 0.10 : 0.18;
        [UIView animateWithDuration:duration delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ departingPlayer.alpha = 0.0; }
                         completion:^(__unused BOOL finished) { [departingPlayer removeFromSuperview]; }];
    } else {
        [departingPlayer removeFromSuperview];
    }
    self.statusBarPlayerContainer = nil;
    self.statusBarPlayerView = nil;
    self.statusBarBlackoutWindow = nil;
    [self.coverSheetControlsToggle removeFromSuperview];
    self.coverSheetControlsToggle = nil;
    self.coverSheetBlackoutRevealed = NO;
    NNPDiagnosticSetBool(@"CoverSheetBlackoutActive", NO);
    NNPDiagnosticSetBool(@"StatusBarBlackoutActive", NO);
    NNPDiagnosticSetBool(@"StatusBarPlayerMirrorActive", NO);
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
    BOOL keepControlsVisible = self.coverSheetBlackoutRevealed;
    self.coverSheetBlackoutView.hidden = keepControlsVisible;

    UIWindow *statusWindow = [self visibleStatusBarWindow];
    if (self.statusBarBlackoutWindow != statusWindow) {
        [self.statusBarBlackoutView removeFromSuperview];
        self.statusBarBlackoutView = nil;
        [self.statusBarPlayerContainer removeFromSuperview];
        self.statusBarPlayerContainer = nil;
        self.statusBarPlayerView = nil;
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
        self.statusBarBlackoutView.hidden = keepControlsVisible;
        if (!self.statusBarPlayerContainer) {
            self.statusBarPlayerContainer = [[UIView alloc] initWithFrame:CGRectZero];
            self.statusBarPlayerContainer.backgroundColor = UIColor.clearColor;
            self.statusBarPlayerContainer.clipsToBounds = YES;
            self.statusBarPlayerContainer.userInteractionEnabled = NO;
            self.statusBarPlayerView = [[NNPView alloc] initWithFrame:statusWindow.bounds];
            self.statusBarPlayerView.contentOpacity = self.view.contentOpacity;
            [self.statusBarPlayerContainer addSubview:self.statusBarPlayerView];
        }
        if (self.statusBarPlayerContainer.superview != statusWindow) [statusWindow addSubview:self.statusBarPlayerContainer];
        self.statusBarPlayerContainer.frame = self.statusBarBlackoutView.frame;
        self.statusBarPlayerContainer.hidden = keepControlsVisible;
        self.statusBarPlayerView.frame = statusWindow.bounds;
        self.statusBarPlayerView.showArtwork = self.view.showArtwork;
        self.statusBarPlayerView.showArtist = self.view.showArtist;
        self.statusBarPlayerView.showProgress = self.view.showProgress;
        self.statusBarPlayerView.artworkSize = self.view.artworkSize;
        self.statusBarPlayerView.cornerRadius = self.view.cornerRadius;
        self.statusBarPlayerView.textSize = self.view.textSize;
        self.statusBarPlayerView.progressHeight = self.view.progressHeight;
        self.statusBarPlayerView.pixelShiftPixels = self.view.pixelShiftPixels;
        [self.statusBarPlayerView updateState:self.state];
        self.statusBarPlayerView.playbackVisible = self.view.playbackVisible;
        [statusWindow bringSubviewToFront:self.statusBarBlackoutView];
        [statusWindow bringSubviewToFront:self.statusBarPlayerContainer];
        NNPDiagnosticSetBool(@"StatusBarBlackoutActive", !keepControlsVisible);
        NNPDiagnosticSetBool(@"StatusBarPlayerMirrorActive", !keepControlsVisible);
    } else {
        [self.statusBarBlackoutView removeFromSuperview];
        self.statusBarBlackoutView = nil;
        [self.statusBarPlayerContainer removeFromSuperview];
        self.statusBarPlayerContainer = nil;
        self.statusBarPlayerView = nil;
        self.statusBarBlackoutWindow = nil;
        NNPDiagnosticSetBool(@"StatusBarBlackoutActive", NO);
        NNPDiagnosticSetBool(@"StatusBarPlayerMirrorActive", NO);
    }

    if (!self.coverSheetControlsToggle) {
        self.coverSheetControlsToggle = [UIButton buttonWithType:UIButtonTypeCustom];
        self.coverSheetControlsToggle.backgroundColor = UIColor.clearColor;
        self.coverSheetControlsToggle.accessibilityLabel = @"切換鎖定畫面控制項";
        self.coverSheetControlsToggle.accessibilityHint = @"點按顯示或隱藏鎖定畫面內容";
        [self.coverSheetControlsToggle addTarget:self action:@selector(toggleCoverSheetBlackout:) forControlEvents:UIControlEventTouchUpInside];
    }
    self.coverSheetControlsToggle.frame = CGRectMake(0.0, 40.0, CGRectGetWidth(host.bounds), 82.0);
    self.coverSheetControlsToggle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    if (self.coverSheetControlsToggle.superview != host) [host addSubview:self.coverSheetControlsToggle];

    [host bringSubviewToFront:self.coverSheetBlackoutView];
    [host bringSubviewToFront:self.view];
    [host bringSubviewToFront:self.coverSheetControlsToggle];
    NNPDiagnosticSetBool(@"CoverSheetBlackoutActive", !keepControlsVisible);
    NNPDiagnosticSetBool(@"CoverSheetControlsRevealed", keepControlsVisible);
}
- (void)removeNotchGestureWindow {
    if (!self.notchGestureWindow || self.notchGestureWindow.hidden) return;
    self.notchGestureWindow.hidden = YES;
    self.notchPanHandled = NO;
    NNPDiagnosticLogTransition(@"MEDIA notch gesture window removed");
}
- (void)updateNotchGestureWindow {
    BOOL eligible = [self shouldPresentInsideCoverSheet] && !self.coverSheetBlackoutRevealed &&
        self.view.playbackVisible && self.state.hasTrack && [self isAllowedMedia:self.state];
    UIWindowScene *scene = self.coverSheetHostView.window.windowScene;
    if (!eligible || !scene) { [self removeNotchGestureWindow]; return; }
    if (!self.notchGestureWindow || self.notchGestureWindow.windowScene != scene) {
        [self removeNotchGestureWindow];
        NNPNotchGestureWindow *window = [[NNPNotchGestureWindow alloc] initWithWindowScene:scene];
        window.backgroundColor = UIColor.clearColor;
        window.opaque = NO;
        window.windowLevel = UIWindowLevelStatusBar + 80.0;
        UIViewController *root = [UIViewController new];
        root.view.backgroundColor = UIColor.clearColor;
        root.view.opaque = NO;
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleNotchTrackPan:)];
        pan.maximumNumberOfTouches = 1;
        [root.view addGestureRecognizer:pan];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleCoverSheetBlackout:)];
        [tap requireGestureRecognizerToFail:pan];
        [root.view addGestureRecognizer:tap];
        window.rootViewController = root;
        self.notchGestureWindow = window;
        NNPDiagnosticLogTransition(@"MEDIA notch gesture window installed");
    }
    CGFloat width = CGRectGetWidth(scene.coordinateSpace.bounds);
    CGFloat height = CGRectGetHeight(scene.coordinateSpace.bounds);
    self.notchGestureWindow.frame = CGRectMake(0.0, 0.0, width, height);
    self.notchGestureWindow.touchRegion = CGRectMake(width * 0.5 - 110.0, 30.0, 220.0, 66.0);
    self.notchGestureWindow.hidden = NO;
}
- (void)handleNotchTrackPan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.notchPanHandled = NO;
        NNPDiagnosticLogTransition(@"MEDIA notch pan began");
        return;
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) { self.notchPanHandled = NO; return; }
    if (gesture.state != UIGestureRecognizerStateChanged || self.notchPanHandled) return;
    CGPoint translation = [gesture translationInView:gesture.view];
    if (fabs(translation.x) < 38.0 || fabs(translation.x) < fabs(translation.y) * 1.4) return;
    self.notchPanHandled = YES;
    if (![self shouldPresentInsideCoverSheet] || self.coverSheetBlackoutRevealed ||
        !self.view.playbackVisible) return;
    BOOL previous = translation.x < 0.0;
    BOOL sent = previous ? [self.media skipToPreviousTrack] : [self.media skipToNextTrack];
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"MEDIA notch pan direction=%@ command=%@ sent=%@ dx=%.1f dy=%.1f",
        previous ? @"left" : @"right", previous ? @"previous" : @"next", sent ? @"YES" : @"NO",
        translation.x, translation.y]);
}
- (void)toggleCoverSheetBlackout:(__unused UIButton *)sender {
    if (!self.coverSheetHostView || !self.coverSheetBlackoutView) return;
    self.coverSheetBlackoutRevealed = !self.coverSheetBlackoutRevealed;
    self.coverSheetBlackoutView.hidden = self.coverSheetBlackoutRevealed;
    self.statusBarBlackoutView.hidden = self.coverSheetBlackoutRevealed;
    self.statusBarPlayerContainer.hidden = self.coverSheetBlackoutRevealed;
    NNPDiagnosticSetBool(@"CoverSheetBlackoutActive", !self.coverSheetBlackoutRevealed);
    NNPDiagnosticSetBool(@"StatusBarBlackoutActive", self.statusBarBlackoutView && !self.coverSheetBlackoutRevealed);
    NNPDiagnosticSetBool(@"StatusBarPlayerMirrorActive", self.statusBarPlayerContainer && !self.coverSheetBlackoutRevealed);
    NNPDiagnosticSetBool(@"CoverSheetControlsRevealed", self.coverSheetBlackoutRevealed);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"COVERSHEET blackout=%@ controlsRevealed=%@ reason=player-area-tap", self.coverSheetBlackoutRevealed ? @"NO" : @"YES", self.coverSheetBlackoutRevealed ? @"YES" : @"NO"]);
    [self updateNotchGestureWindow];
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
    self.statusBarPlayerContainer.hidden = YES;
    NNPDiagnosticSetBool(@"CoverSheetBlackoutActive", NO);
    NNPDiagnosticSetBool(@"StatusBarBlackoutActive", NO);
    NNPDiagnosticSetBool(@"StatusBarPlayerMirrorActive", NO);
    NNPDiagnosticSetBool(@"CoverSheetControlsRevealed", YES);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"COVERSHEET blackout=NO controlsRevealed=YES reason=%@", reason ?: @"unknown"]);
    [self removeNotchGestureWindow];
}
- (BOOL)shouldPresentInsideCoverSheet {
#if NNP_ENABLE_COVERSHEET_PRESENTATION && NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
    return self.locked && self.preferences.experimentalLockedVisible && self.preferences.enabled &&
        self.preferences.showOnLockScreen && self.display.aodPresentationActive &&
        self.display.lifecycleState == NNPDisplayLifecycleStateActive;
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
    if (target && target == self.coverSheetHostView && self.view.superview == target) {
        [self installCoverSheetBlackoutForHost:target];
        return;
    }

    // The AOD experiment is armed while the normal UI remains hidden. In that
    // state a window may not exist yet, so there is nothing to detach.
    if (!self.window || !self.view) {
        [self removeCoverSheetBlackout];
        self.coverSheetHostView = nil;
        NNPDiagnosticSetBool(@"CoverSheetPresentationActive", NO);
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
- (void)clearLockedPresentationBackgroundForUnlock {
    self.window.opaque = NO;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.rootViewController.view.opaque = NO;
    self.window.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.view.backgroundColor = UIColor.clearColor;
    NNPDiagnosticSetBool(@"PresentationDedicatedBlack", NO);
    NNPDiagnosticLogTransition(@"CONTROLLER cleared plugin window black background immediately on logical unlock");
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
- (void)applyViewPreferences {
    self.view.showArtwork = self.preferences.showArtwork;
    self.view.showArtist = self.preferences.showArtist;
    self.view.showProgress = self.preferences.showProgress;
    self.view.showLyrics = self.preferences.showLyrics;
    self.view.artworkSize = self.preferences.artworkSize;
    self.view.cornerRadius = self.preferences.cornerRadius;
    self.view.textSize = self.preferences.textSize;
    self.view.progressHeight = self.preferences.progressHeight;

    [self applyLyricsPreferences];
    [self.view setNeedsLayout];
}
- (void)applyLyricsPreferences {
    BOOL spotifyTrack = [self.state.bundleIdentifier isEqualToString:NNPSpotify];
    BOOL matchingTrack = NNPTrackTitleMatches(self.state.title, self.preferences.spotifyLyricsTrackTitle);
    NNPDiagnosticSetBool(@"SpotifyLyricsTrackMatch", matchingTrack);
    NSString *currentLine = @"";
    NSString *nextLine = @"";
    if (self.preferences.showLyrics && spotifyTrack && matchingTrack) {
        NSArray<NSDictionary *> *timedLines = self.preferences.spotifyLyricsTimedLines;
        if (timedLines.count) {
            NSTimeInterval elapsed = self.state.elapsed;
            if (self.state.playing && self.state.playbackRate > 0.0 && self.state.timestamp > 0.0)
                elapsed += MAX(0.0, NSDate.date.timeIntervalSince1970 - self.state.timestamp) * self.state.playbackRate;
            // Spotify's line timestamps can feel ahead of the vocal on the AOD.
            // Hold the current lyric briefly before advancing to the next line.
            elapsed = MAX(0.0, elapsed - 0.18);
            NSUInteger activeIndex = 0;
            for (NSUInteger index = 1; index < timedLines.count; index++) {
                if ([timedLines[index][@"startTimeMs"] doubleValue] > elapsed * 1000.0) break;
                activeIndex = index;
            }
            currentLine = [timedLines[activeIndex][@"words"] isKindOfClass:NSString.class] ? timedLines[activeIndex][@"words"] : @"";
            if (activeIndex + 1 < timedLines.count)
                nextLine = [timedLines[activeIndex + 1][@"words"] isKindOfClass:NSString.class] ? timedLines[activeIndex + 1][@"words"] : @"";
        } else {
            currentLine = self.preferences.spotifyLyricsText;
            nextLine = self.preferences.spotifyLyricsNextLine;
        }
    }
    [self.view updateLyricsText:currentLine nextLine:nextLine];
}
- (void)updateUnlimitedMediaPauseWithEligibleMedia:(BOOL)mediaEligible activeSession:(BOOL)activeSession {
    BOOL shouldWait = self.preferences.experimentalUnlimitedDuration && activeSession && !mediaEligible;
    if (!shouldWait) {
        if (self.unlimitedMediaPausePending) {
            self.unlimitedMediaPausePending = NO;
            self.unlimitedMediaPauseGeneration++;
            NNPDiagnosticLogTransition(@"DISPLAY unlimited media pause cancelled");
        }
        return;
    }
    if (self.unlimitedMediaPausePending) return;
    self.unlimitedMediaPausePending = YES;
    NSUInteger generation = ++self.unlimitedMediaPauseGeneration;
    NNPDiagnosticLogTransition(@"DISPLAY unlimited media pause grace started duration=15s");
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.unlimitedMediaPausePending ||
            generation != strongSelf.unlimitedMediaPauseGeneration) return;
        strongSelf.unlimitedMediaPausePending = NO;
        BOOL stillPaused = !strongSelf.state.hasTrack || !strongSelf.state.playing ||
            ![strongSelf isAllowedMedia:strongSelf.state];
        if (!strongSelf.locked || !strongSelf.preferences.experimentalUnlimitedDuration ||
            !strongSelf.display.aodPresentationActive || !stillPaused) return;
        NNPDiagnosticLogTransition(@"DISPLAY unlimited session ended after sustained media pause");
        [strongSelf.display stopLockedVisibleMode];
        [strongSelf reconcile];
    });
}
- (void)reconcile { dispatch_async(dispatch_get_main_queue(), ^{
        BOOL experimentEligible = NO;
#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
        self.display.deviceLocked = self.locked;
        self.display.maximumDuration = self.preferences.experimentalMaxDuration;
        self.display.unlimitedDuration = self.preferences.experimentalUnlimitedDuration;
        BOOL mediaEligible = self.state.hasTrack && self.state.playing && [self isAllowedMedia:self.state];
        BOOL activeSession = self.locked && self.display.aodPresentationActive &&
            self.display.lifecycleState == NNPDisplayLifecycleStateActive;
        [self updateUnlimitedMediaPauseWithEligibleMedia:mediaEligible activeSession:activeSession];
        experimentEligible = self.preferences.experimentalLockedVisible && self.preferences.enabled &&
            self.preferences.showOnLockScreen && (mediaEligible || activeSession);
        NNPDiagnosticSetBool(@"MediaSwitchAODSessionRetained", activeSession && !mediaEligible && experimentEligible);
        if (experimentEligible) {
            [self.preferences reloadAODBrightnessMultiplier];
            float brightnessMultiplier = self.preferences.aodBrightnessMultiplier;
            self.display.aodBrightnessMultiplier = brightnessMultiplier;
            // Publish directly on every eligible reconcile so the hook's
            // atomic value cannot lag behind a cached display-controller value.
            NNPPhase7SetAODBrightnessMultiplier(brightnessMultiplier);
            NNPDiagnosticSetDouble(@"Phase7RequestedAODBrightnessMultiplier", brightnessMultiplier);
            [self.display startLockedVisibleMode];
        } else {
            [self.display stopLockedVisibleMode];
        }
#endif
        BOOL show = [self shouldShow];
        NNPDiagnosticSetBool(@"UIVisible", show);
        NNPDiagnosticLogTransition([NSString stringWithFormat:@"CONTROLLER reconcile locked=%@ show=%@ experimentEligible=%@ lifecycle=%ld", self.locked ? @"YES" : @"NO", show ? @"YES" : @"NO", experimentEligible ? @"YES" : @"NO", (long)self.display.lifecycleState]);
        if (!show) { [self hide]; return; }
        [self makeWindow];
        BOOL becomingVisible = self.window.hidden;
        if (becomingVisible) {
            [self.view stopContentAnimation];
            self.view.contentOpacity = 0.0;
        }
        [self applyViewPreferences]; [self.view updateState:self.state]; [self updateCoverSheetPresentation]; [self applyLockedBackground];
        if (self.window.hidden) { self.window.hidden = NO; NSLog(@"%@ overlay shown", NNPLog); NNPDiagnosticLogTransition(@"CONTROLLER window visible=YES"); [self recordPresentationDiagnostics:@"window-visible"]; }
        self.view.playbackVisible = YES;
        self.statusBarPlayerView.playbackVisible = YES;
        [self updateNotchGestureWindow];
        if (becomingVisible) {
            [self.statusBarPlayerView stopContentAnimation];
            self.statusBarPlayerView.contentOpacity = 0.0;
            NSTimeInterval duration = UIAccessibilityIsReduceMotionEnabled() ? 0.16 : 0.32;
            [UIView animateWithDuration:duration delay:0.04
                                options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                                 self.view.contentOpacity = 1.0;
                                 self.statusBarPlayerView.contentOpacity = 1.0;
                             } completion:nil];
        }
        [self startProgressTimer]; [self startAODPixelShiftTimer]; [self updateProgress]; }); }
- (void)hide {
    [self stopAODPixelShiftTimer];
    BOOL keepAmbient = [self shouldPresentInsideCoverSheet];
    if (keepAmbient) {
        [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.10 : 0.18
                              delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                             self.view.contentOpacity = 0.0;
                             self.statusBarPlayerView.contentOpacity = 0.0;
                         } completion:nil];
    } else {
        [self.view stopContentAnimation];
        self.view.contentOpacity = 0.0;
    }
    self.view.playbackVisible = NO;
    self.statusBarPlayerView.playbackVisible = NO;
    [self removeNotchGestureWindow];
    [self updateCoverSheetPresentation];
    if (!self.window.hidden) { self.window.hidden = YES; NSLog(@"%@ overlay hidden", NNPLog); NNPDiagnosticLogTransition(@"CONTROLLER window visible=NO cleanup"); }
    [self.progressTimer invalidate]; self.progressTimer = nil;
}
- (void)applyRandomAODPixelShift {
    if (!self.view) return;
    NSInteger currentX = (NSInteger)llround(self.view.pixelShiftPixels.x);
    NSInteger currentY = (NSInteger)llround(self.view.pixelShiftPixels.y);
    NSInteger x = 0, y = 0;
    do {
        x = (NSInteger)arc4random_uniform(7) - 3;
        y = (NSInteger)arc4random_uniform(7) - 3;
    } while ((x == 0 && y == 0) || (x == currentX && y == currentY));
    self.view.pixelShiftPixels = CGPointMake((CGFloat)x, (CGFloat)y);
    self.statusBarPlayerView.pixelShiftPixels = self.view.pixelShiftPixels;
    NNPDiagnosticSetInteger(@"AODPixelShiftX", x);
    NNPDiagnosticSetInteger(@"AODPixelShiftY", y);
    NNPDiagnosticLogTransition([NSString stringWithFormat:@"CONTROLLER AOD pixel shift x=%ld y=%ld", (long)x, (long)y]);
}
- (void)startAODPixelShiftTimer {
    if (!self.preferences.aodPixelShiftEnabled || !self.display.aodPresentationActive) {
        [self stopAODPixelShiftTimer];
        return;
    }
    if (self.pixelShiftTimer) return;
    [self applyRandomAODPixelShift];
    __weak typeof(self) weakSelf = self;
    self.pixelShiftTimer = [NSTimer timerWithTimeInterval:30.0 repeats:YES block:^(__unused NSTimer *timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!strongSelf.preferences.aodPixelShiftEnabled || !strongSelf.display.aodPresentationActive || ![strongSelf shouldShow]) {
            [strongSelf stopAODPixelShiftTimer];
            return;
        }
        [strongSelf applyRandomAODPixelShift];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.pixelShiftTimer forMode:NSRunLoopCommonModes];
}
- (void)stopAODPixelShiftTimer {
    [self.pixelShiftTimer invalidate];
    self.pixelShiftTimer = nil;
    self.view.pixelShiftPixels = CGPointZero;
    self.statusBarPlayerView.pixelShiftPixels = CGPointZero;
    NNPDiagnosticSetInteger(@"AODPixelShiftX", 0);
    NNPDiagnosticSetInteger(@"AODPixelShiftY", 0);
}
- (void)startProgressTimer { if (self.progressTimer) return; __weak typeof(self) weakSelf = self; self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:self.preferences.progressUpdateInterval repeats:YES block:^(__unused NSTimer *timer) { [weakSelf updateProgress]; }]; }
- (void)updateProgress { if (!self.state || self.window.hidden) return; [self.preferences reloadSpotifyLyricsSnapshot]; [self applyLyricsPreferences]; [self updateCoverSheetPresentation]; NSTimeInterval elapsed = self.state.elapsed; if (self.state.playing && self.state.playbackRate > 0.0 && self.state.timestamp > 0.0) elapsed += MAX(0.0, NSDate.date.timeIntervalSince1970 - self.state.timestamp) * self.state.playbackRate; if (self.state.duration > 0.0) elapsed = MIN(self.state.duration, MAX(0.0, elapsed)); [self.view updateElapsed:elapsed duration:self.state.duration playing:self.state.playing]; [self.statusBarPlayerView updateElapsed:elapsed duration:self.state.duration playing:self.state.playing]; }
- (void)dealloc {
#if NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE
    [_display stopLockedVisibleMode];
#endif
    self.unlimitedMediaPausePending = NO;
    self.unlimitedMediaPauseGeneration++;
    [[NSNotificationCenter defaultCenter] removeObserver:self]; [_lockState stop]; [_progressTimer invalidate]; [_pixelShiftTimer invalidate];
}
@end
