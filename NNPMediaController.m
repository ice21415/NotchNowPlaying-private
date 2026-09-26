#import "NNPMediaController.h"
#import "NNPState.h"
#import "NNPDiagnostics.h"
#import <UIKit/UIKit.h>
#import <MediaRemote/MediaRemote.h>
#import <objc/message.h>
#import <math.h>

static NSString * const NNPLog = @"[Lilywhite/NowPlaying]";
static const NSTimeInterval NNPTransientPlaybackGrace = 2.5;

@interface NNPMediaController ()
@property(nonatomic) BOOL started;
@property(nonatomic) int pid;
@property(nonatomic, strong) NSDictionary *info;
@property(nonatomic, strong) NSMutableArray *observerTokens;
@property(nonatomic) NSUInteger refreshGeneration;
@property(nonatomic) NSUInteger transientGeneration;
@property(nonatomic) BOOL transientPending;
@property(nonatomic, strong) NNPState *pendingTransientState;
@property(nonatomic, strong) NNPState *publishedState;
- (void)deliverState:(NNPState *)state;
@end

static id NNPValue(NSDictionary *info, CFStringRef key) {
    return info[(__bridge NSString *)key];
}
static NSString *NNPString(NSDictionary *info, CFStringRef key) {
    id value = NNPValue(info, key);
    return [value isKindOfClass:NSString.class] ? value : nil;
}
static NSTimeInterval NNPTime(NSDictionary *info, CFStringRef key) {
    id value = NNPValue(info, key);
    if ([value isKindOfClass:NSNumber.class]) return [value doubleValue];
    if ([value isKindOfClass:NSDate.class]) return [value timeIntervalSince1970];
    return 0.0;
}
static NSString *NNPBundleForPID(int pid) {
    Class cls = NSClassFromString(@"SBApplicationController");
    if (!cls || pid <= 0) return nil;
    id (*noArg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id (*withPID)(id, SEL, NSInteger) = (id (*)(id, SEL, NSInteger))objc_msgSend;
    id controller = noArg(cls, @selector(sharedInstance));
    id application = controller ? withPID(controller, @selector(applicationWithPid:), pid) : nil;
    return [application respondsToSelector:@selector(bundleIdentifier)] ? [application bundleIdentifier] : nil;
}
static UIImage *NNPArtwork(NSDictionary *info) {
    id value = NNPValue(info, kMRMediaRemoteNowPlayingInfoArtworkData);
    if ([value isKindOfClass:UIImage.class]) return value;
    if ([value isKindOfClass:NSData.class]) return [UIImage imageWithData:value scale:UIScreen.mainScreen.scale];
    if ([value isKindOfClass:NSDictionary.class]) {
        id data = value[@"data"] ?: value[@"artworkData"];
        if ([data isKindOfClass:NSData.class]) return [UIImage imageWithData:data scale:UIScreen.mainScreen.scale];
    }
    return nil;
}

@implementation NNPMediaController
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _observerTokens = [NSMutableArray array];
    return self;
}
- (void)start {
    if (self.started) return;
    self.started = YES;
    __weak typeof(self) weakSelf = self;
    NSArray *names = @[
        (__bridge NSString *)kMRMediaRemoteNowPlayingInfoDidChangeNotification,
        (__bridge NSString *)kMRMediaRemoteNowPlayingApplicationDidChangeNotification,
        (__bridge NSString *)kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification
    ];
    for (NSString *name in names) {
        id token = [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            [weakSelf refresh];
        }];
        if (token) [self.observerTokens addObject:token];
    }
    MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_get_main_queue());
    NSLog(@"%@ MediaRemote connected", NNPLog);
    [self refresh];
}
- (void)refresh {
    if (!self.started) return;
    __weak typeof(self) weakSelf = self;
    NSUInteger generation = ++self.refreshGeneration;
    __block BOOL receivedPID = NO, receivedInfo = NO;
    __block int nextPID = 0;
    __block NSDictionary *nextInfo = nil;
    void (^finishIfReady)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.refreshGeneration || !receivedPID || !receivedInfo) return;
        strongSelf.pid = nextPID;
        strongSelf.info = nextInfo;
        [strongSelf publish];
    };
    MRMediaRemoteGetNowPlayingApplicationPID(dispatch_get_main_queue(), ^(int pid) {
        nextPID = pid;
        receivedPID = YES;
        finishIfReady();
    });
    MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef rawInfo) {
        nextInfo = rawInfo ? CFBridgingRelease(CFRetain(rawInfo)) : nil;
        receivedInfo = YES;
        finishIfReady();
    });
}
- (void)publish {
    if (!self.started) return;
    NSDictionary *info = self.info ?: @{};
    NNPState *state = [NNPState new];
    state.title = NNPString(info, kMRMediaRemoteNowPlayingInfoTitle);
    state.artist = NNPString(info, kMRMediaRemoteNowPlayingInfoArtist);
    state.album = NNPString(info, kMRMediaRemoteNowPlayingInfoAlbum);
    state.uniqueIdentifier = NNPString(info, kMRMediaRemoteNowPlayingInfoUniqueIdentifier);
    state.artwork = NNPArtwork(info);
    state.duration = NNPTime(info, kMRMediaRemoteNowPlayingInfoDuration);
    state.elapsed = NNPTime(info, kMRMediaRemoteNowPlayingInfoElapsedTime);
    state.timestamp = NNPTime(info, kMRMediaRemoteNowPlayingInfoTimestamp);
    NSNumber *rate = NNPValue(info, kMRMediaRemoteNowPlayingInfoPlaybackRate);
    state.playbackRate = [rate isKindOfClass:NSNumber.class] ? rate.floatValue : 0.0f;
    state.playing = state.playbackRate > 0.001f;
    state.validDuration = isfinite(state.duration) && state.duration > 0.0;
    state.bundleIdentifier = NNPBundleForPID(self.pid);
#if NNP_PHASE2D2_DIAGNOSTIC
    static BOOL lastPlaying = NO;
    static NSString *lastBundle = nil;
    NSString *bundle = state.bundleIdentifier ?: @"unknown";
    if (state.playing != lastPlaying || ![bundle isEqualToString:lastBundle ?: @""]) {
        NNPDiagnosticLog([NSString stringWithFormat:@"MEDIA playing=%d bundle=%@ title-present=%d", state.playing, bundle, state.title.length > 0]);
        lastPlaying = state.playing;
        lastBundle = [bundle copy];
    }
#endif
    BOOL ready = state.playing && state.hasTrack && state.bundleIdentifier.length > 0;
    if (ready) {
        if (self.transientPending) NNPDiagnosticLogTransition(@"MEDIA transient playback state recovered before grace period ended");
        self.transientPending = NO;
        self.pendingTransientState = nil;
        self.transientGeneration++;
        [self deliverState:state];
        return;
    }
    if (self.transientPending) {
        self.pendingTransientState = [state copyState];
        return;
    }
    if (self.publishedState.playing) {
        self.transientPending = YES;
        self.pendingTransientState = [state copyState];
        NSUInteger generation = ++self.transientGeneration;
        NNPDiagnosticLogTransition(@"MEDIA transient playback state held for 2.5s");
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NNPTransientPlaybackGrace * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.transientPending || generation != strongSelf.transientGeneration) return;
            NNPState *pending = strongSelf.pendingTransientState;
            strongSelf.transientPending = NO;
            strongSelf.pendingTransientState = nil;
            NNPDiagnosticLogTransition(@"MEDIA transient playback state persisted after grace period");
            [strongSelf deliverState:pending];
        });
        return;
    }
    [self deliverState:state];
}

- (void)deliverState:(NNPState *)state {
    if (!state) return;
    self.publishedState = [state copyState];
    if (state.bundleIdentifier.length) NSLog(@"%@ Now Playing application: %@", NNPLog, state.bundleIdentifier);
    if (self.stateHandler) self.stateHandler([state copyState]);
}
@end
