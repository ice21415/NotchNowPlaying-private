#import "NNPMediaController.h"
#import "NNPState.h"
#import <UIKit/UIKit.h>
#import <MediaRemote/MediaRemote.h>
#import <objc/message.h>
#import <math.h>

static NSString * const NNPLog = @"[Lilywhite/NowPlaying]";

@interface NNPMediaController ()
@property(nonatomic) BOOL started;
@property(nonatomic) int pid;
@property(nonatomic, strong) NSDictionary *info;
@property(nonatomic, strong) NSMutableArray *observerTokens;
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
    MRMediaRemoteGetNowPlayingApplicationPID(dispatch_get_main_queue(), ^(int pid) {
        weakSelf.pid = pid;
        [weakSelf publish];
    });
    MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef rawInfo) {
        weakSelf.info = rawInfo ? CFBridgingRelease(CFRetain(rawInfo)) : nil;
        [weakSelf publish];
    });
}
- (void)publish {
    if (!self.started || !self.info) return;
    NSDictionary *info = self.info;
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
    if (state.bundleIdentifier.length) NSLog(@"%@ Now Playing application: %@", NNPLog, state.bundleIdentifier);
    if (self.stateHandler) self.stateHandler([state copyState]);
}
@end
