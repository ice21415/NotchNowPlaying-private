#import "NNPSpotifyLyricsProbe.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <fcntl.h>
#import <unistd.h>

static CFStringRef const NNPSpotifySharedPreferences = CFSTR("com.user.notchnowplaying");
static CFStringRef const NNPSpotifyLyricsChangedNotification = CFSTR("com.user.notchnowplaying.preferences.changed");
static NSString *NNPSpotifyLyricsProbePath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"nnp-spotify-lyrics-runtime.log"];
}

static void NNPSpotifyProbeAppend(NSString *line) {
    if (!line.length) return;
    NSString *entry = [line stringByAppendingString:@"\n"];
    NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
    int fd = open(NNPSpotifyLyricsProbePath().fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    const uint8_t *bytes = data.bytes;
    ssize_t remaining = (ssize_t)data.length;
    while (remaining > 0) {
        ssize_t written = write(fd, bytes, (size_t)remaining);
        if (written <= 0) break;
        bytes += written;
        remaining -= written;
    }
    close(fd);
}

static NSString *NNPSpotifyNormalizeLyricsText(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (line.length) [parts addObject:line];
    }
    return [parts componentsJoinedByString:@" "];
}

static BOOL NNPSpotifyIsNonLyricLabel(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *lowercase = trimmed.lowercaseString;
    if ([lowercase isEqualToString:@"歌詞"] || [lowercase isEqualToString:@"lyrics"] ||
        [lowercase containsString:@"musixmatch"] || [trimmed containsString:@"歌詞提供者"]) return YES;

    NSDictionary *nowPlaying = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    NSString *title = [nowPlaying[MPMediaItemPropertyTitle] isKindOfClass:NSString.class]
        ? nowPlaying[MPMediaItemPropertyTitle] : @"";
    NSString *artist = [nowPlaying[MPMediaItemPropertyArtist] isKindOfClass:NSString.class]
        ? nowPlaying[MPMediaItemPropertyArtist] : @"";
    if ((title.length && [trimmed isEqualToString:title]) ||
        (artist.length && [trimmed isEqualToString:artist])) return YES;

    NSString *clock = [trimmed hasPrefix:@"-"] ? [trimmed substringFromIndex:1] : trimmed;
    NSArray<NSString *> *clockParts = [clock componentsSeparatedByString:@":"];
    if (clockParts.count == 2 && clockParts[0].length <= 2 && clockParts[1].length == 2) {
        NSCharacterSet *notDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
        if ([clock rangeOfCharacterFromSet:notDigits].location == NSNotFound) return YES;
    }
    return NO;
}

static void NNPSpotifyCollectLyricLabels(UIView *view, UIWindow *window, BOOL inLyricsPage,
                                        NSMutableArray<NSDictionary *> *rows, NSUInteger depth) {
    if (!view || depth > 48 || rows.count >= 160 || view.hidden || view.alpha < 0.01) return;
    NSString *className = NSStringFromClass(view.class) ?: @"";
    BOOL insideLyrics = inLyricsPage || [className rangeOfString:@"Lyrics" options:NSCaseInsensitiveSearch].location != NSNotFound;
    if (insideLyrics && [view isKindOfClass:UILabel.class]) {
        NSString *text = NNPSpotifyNormalizeLyricsText(((UILabel *)view).text ?: view.accessibilityLabel);
        CGRect frame = [view convertRect:view.bounds toView:window];
        if (text.length >= 2 && !NNPSpotifyIsNonLyricLabel(text) &&
            frame.size.height >= 12.0 && frame.size.height <= 100.0 &&
            CGRectIntersectsRect(frame, window.bounds)) {
            [rows addObject:@{@"text": text, @"midY": @(CGRectGetMidY(frame))}];
        }
    }
    for (UIView *child in view.subviews)
        NNPSpotifyCollectLyricLabels(child, window, insideLyrics, rows, depth + 1);
}

static BOOL NNPSpotifyPublishLyrics(NSString *current, NSString *next, NSArray<NSString *> *visibleLines) {
    static NSString *lastCurrent;
    static NSString *lastNext;
    static NSString *lastTrackTitle;
    static NSString *lastTrackArtist;
    static NSArray<NSString *> *lastLines;
    current = current ?: @"";
    next = next ?: @"";
    NSDictionary *nowPlaying = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    NSString *trackTitle = [nowPlaying[MPMediaItemPropertyTitle] isKindOfClass:NSString.class] ? nowPlaying[MPMediaItemPropertyTitle] : @"";
    NSString *trackArtist = [nowPlaying[MPMediaItemPropertyArtist] isKindOfClass:NSString.class] ? nowPlaying[MPMediaItemPropertyArtist] : @"";
    if ([lastCurrent isEqualToString:current] && [lastNext isEqualToString:next] &&
        [lastTrackTitle isEqualToString:trackTitle] && [lastTrackArtist isEqualToString:trackArtist] &&
        [lastLines isEqualToArray:visibleLines]) return NO;
    lastCurrent = [current copy];
    lastNext = [next copy];
    lastTrackTitle = [trackTitle copy];
    lastTrackArtist = [trackArtist copy];
    lastLines = [visibleLines copy];

    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsText"), (__bridge CFStringRef)current, NNPSpotifySharedPreferences);
    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsNextLine"), (__bridge CFStringRef)next, NNPSpotifySharedPreferences);
    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsVisibleLines"), (__bridge CFArrayRef)visibleLines, NNPSpotifySharedPreferences);
    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsUpdatedAt"), (__bridge CFDateRef)NSDate.date, NNPSpotifySharedPreferences);
    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsTrackTitle"), (__bridge CFStringRef)trackTitle, NNPSpotifySharedPreferences);
    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsTrackArtist"), (__bridge CFStringRef)trackArtist, NNPSpotifySharedPreferences);
    Boolean synchronized = CFPreferencesAppSynchronize(NNPSpotifySharedPreferences);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         NNPSpotifyLyricsChangedNotification, NULL, NULL, true);
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"LYRICS publish lines=%lu sync=%@ track=%@ current=%@", (unsigned long)visibleLines.count,
                           synchronized ? @"YES" : @"NO", trackTitle, current]);
    [NSUserDefaults.standardUserDefaults setBool:synchronized forKey:@"NNPSpotifyLyricsSharedWriteSucceeded"];
    [NSUserDefaults.standardUserDefaults synchronize];
    return YES;
}

static void NNPSpotifyLyricsProbeCapture(void) {
    UIApplication *application = UIApplication.sharedApplication;
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState == UISceneActivationStateUnattached) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha < 0.01) continue;
            NNPSpotifyCollectLyricLabels(window, window, NO, rows, 0);
        }
    }

    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"midY"] compare:right[@"midY"]];
    }];
    NSMutableArray<NSDictionary *> *uniqueRows = [NSMutableArray arrayWithCapacity:rows.count];
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSString *text = row[@"text"];
        if (text.length && ![lines.lastObject isEqualToString:text]) {
            [lines addObject:text];
            [uniqueRows addObject:row];
        }
    }
    if (lines.count == 0) {
        // Background Spotify can temporarily detach or hide its lyrics scene.
        // Preserve the most recent line instead of replacing it with an empty
        // value while playback continues.
        return;
    }

    // Spotify auto-scrolls the lyrics view around the active verse. Use the
    // visible line nearest the lyrics viewport's vertical center as the lead.
    CGFloat targetY = UIScreen.mainScreen.bounds.size.height * 0.31;
    NSUInteger activeIndex = 0;
    CGFloat nearestDistance = CGFLOAT_MAX;
    for (NSUInteger index = 0; index < uniqueRows.count; index++) {
        CGFloat distance = fabs([uniqueRows[index][@"midY"] doubleValue] - targetY);
        if (distance < nearestDistance) { nearestDistance = distance; activeIndex = index; }
    }
    NSString *current = lines[MIN(activeIndex, lines.count - 1)];
    NSString *next = activeIndex + 1 < lines.count ? lines[activeIndex + 1] : @"";
    NNPSpotifyPublishLyrics(current, next, lines);
}

void NNPSpotifyLyricsProbeStart(void) {
    [NSUserDefaults.standardUserDefaults setObject:[NSDate date] forKey:@"NNPSpotifyLyricsProbeStartedAt"];
    [NSUserDefaults.standardUserDefaults setObject:@(getpid()) forKey:@"NNPSpotifyLyricsProbePID"];
    [NSUserDefaults.standardUserDefaults synchronize];
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"START pid=%d process=%@ bundle=%@", getpid(),
                           NSProcessInfo.processInfo.processName ?: @"?", NSBundle.mainBundle.bundleIdentifier ?: @"?"]);
    dispatch_async(dispatch_get_main_queue(), ^{
        NNPSpotifyLyricsProbeCapture();
        [NSTimer scheduledTimerWithTimeInterval:0.8 repeats:YES block:^(__unused NSTimer *timer) {
            NNPSpotifyLyricsProbeCapture();
        }];
    });
}
