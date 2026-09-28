#import "NNPSpotifyLyricsProbe.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import <fcntl.h>
#import <limits.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

static CFStringRef const NNPSpotifySharedPreferences = CFSTR("com.user.notchnowplaying");
static CFStringRef const NNPSpotifyLyricsChangedNotification = CFSTR("com.user.notchnowplaying.preferences.changed");
static BOOL NNPSpotifyStringContainsAny(NSString *value, NSArray<NSString *> *needles);
static void NNPSpotifyProbeAppend(NSString *line);
static char NNPSpotifyNetworkBodyAssociationKey;
static char NNPSpotifyNetworkBodyTruncatedAssociationKey;
static NSMutableDictionary<NSString *, NSDictionary *> *NNPSpotifyTrackContextByRequestPath;
static NSMutableDictionary<NSString *, NSNumber *> *NNPSpotifyLyricsFetchAttempts;
static NSObject *NNPSpotifyTrackContextLock;
static dispatch_once_t NNPSpotifyTrackContextOnce;
static NSURLSession *NNPSpotifyLyricsRequestSession;
static NSURLRequest *NNPSpotifyLyricsRequestTemplate;
static NSString *NNPSpotifyVerifiedLyricsTrackTitle;
static NSString *NNPSpotifyVerifiedLyricsTrackArtist;
static NSString *NNPSpotifyVerifiedLyricsTrackIdentifierValue;

static void NNPSpotifyEnsureTrackContextStore(void) {
    dispatch_once(&NNPSpotifyTrackContextOnce, ^{
        NNPSpotifyTrackContextByRequestPath = [NSMutableDictionary dictionary];
        NNPSpotifyLyricsFetchAttempts = [NSMutableDictionary dictionary];
        NNPSpotifyTrackContextLock = [NSObject new];
    });
}

static BOOL NNPSpotifyMetadataStringMatches(NSString *left, NSString *right) {
    NSString *first = [(left ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *second = [(right ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!first.length || !second.length) return NO;
    return [first compare:second options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch |
            NSWidthInsensitiveSearch] == NSOrderedSame;
}

static BOOL NNPSpotifyTrackMetadataMatches(NSString *titleA, NSString *artistA,
                                           NSString *titleB, NSString *artistB) {
    if (!NNPSpotifyMetadataStringMatches(titleA, titleB)) return NO;
    if (artistA.length && artistB.length && !NNPSpotifyMetadataStringMatches(artistA, artistB)) return NO;
    return YES;
}

static NSString *NNPSpotifyTrackIdentifierFromMetadata(NSDictionary *metadata) {
    id value = metadata[MPNowPlayingInfoPropertyExternalContentIdentifier];
    if (![value isKindOfClass:NSString.class] || ![value length]) return @"";
    NSString *identifier = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRange playbackInstance = [identifier rangeOfString:@"#"];
    if (playbackInstance.location != NSNotFound)
        identifier = [identifier substringToIndex:playbackInstance.location];
    NSString *lastComponent = [[identifier componentsSeparatedByCharactersInSet:
                                [NSCharacterSet characterSetWithCharactersInString:@":/"]] lastObject];
    NSRange queryStart = [lastComponent rangeOfString:@"?"];
    if (queryStart.location != NSNotFound) lastComponent = [lastComponent substringToIndex:queryStart.location];
    return lastComponent ?: @"";
}

static void NNPSpotifySetVerifiedLyricsTrack(NSString *title, NSString *artist, NSString *identifier) {
    NNPSpotifyEnsureTrackContextStore();
    @synchronized (NNPSpotifyTrackContextLock) {
        NNPSpotifyVerifiedLyricsTrackTitle = [title copy] ?: @"";
        NNPSpotifyVerifiedLyricsTrackArtist = [artist copy] ?: @"";
        NNPSpotifyVerifiedLyricsTrackIdentifierValue = [identifier copy] ?: @"";
    }
}

static NSString *NNPSpotifyVerifiedLyricsTrackIdentifier(void) {
    NNPSpotifyEnsureTrackContextStore();
    @synchronized (NNPSpotifyTrackContextLock) {
        return [NNPSpotifyVerifiedLyricsTrackIdentifierValue copy] ?: @"";
    }
}

static BOOL NNPSpotifyVisibleLyricsMatchVerifiedTrack(NSString *title, NSString *artist, NSString *identifier) {
    NNPSpotifyEnsureTrackContextStore();
    @synchronized (NNPSpotifyTrackContextLock) {
        if (identifier.length && NNPSpotifyVerifiedLyricsTrackIdentifierValue.length)
            return [identifier isEqualToString:NNPSpotifyVerifiedLyricsTrackIdentifierValue];
        return NNPSpotifyTrackMetadataMatches(title, artist,
                                              NNPSpotifyVerifiedLyricsTrackTitle,
                                              NNPSpotifyVerifiedLyricsTrackArtist);
    }
}

static void NNPSpotifyInitializeLyricsTrackAssociation(void) {
    CFPreferencesAppSynchronize(NNPSpotifySharedPreferences);
    id versionValue = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("SpotifyLyricsAssociationVersion"),
                                                                   NNPSpotifySharedPreferences));
    if (![versionValue isEqual:@3]) {
        CFPreferencesSetAppValue(CFSTR("SpotifyLyricsText"), CFSTR(""), NNPSpotifySharedPreferences);
        CFPreferencesSetAppValue(CFSTR("SpotifyLyricsNextLine"), CFSTR(""), NNPSpotifySharedPreferences);
        CFPreferencesSetAppValue(CFSTR("SpotifyLyricsVisibleLines"), (__bridge CFArrayRef)@[], NNPSpotifySharedPreferences);
        CFPreferencesSetAppValue(CFSTR("SpotifyLyricsTimedLines"), (__bridge CFArrayRef)@[], NNPSpotifySharedPreferences);
        CFPreferencesSetAppValue(CFSTR("SpotifyLyricsTrackTitle"), CFSTR(""), NNPSpotifySharedPreferences);
        CFPreferencesSetAppValue(CFSTR("SpotifyLyricsTrackArtist"), CFSTR(""), NNPSpotifySharedPreferences);
        CFPreferencesSetAppValue(CFSTR("SpotifyLyricsTrackIdentifier"), CFSTR(""), NNPSpotifySharedPreferences);
        CFPreferencesSetAppValue(CFSTR("SpotifyLyricsAssociationVersion"), (__bridge CFNumberRef)@3, NNPSpotifySharedPreferences);
        Boolean synchronized = CFPreferencesAppSynchronize(NNPSpotifySharedPreferences);
        NNPSpotifySetVerifiedLyricsTrack(@"", @"", @"");
        if (synchronized) {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 NNPSpotifyLyricsChangedNotification, NULL, NULL, true);
        }
        NNPSpotifyProbeAppend(@"LYRICS snapshot reset for request-bound track association");
        return;
    }

    id titleValue = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("SpotifyLyricsTrackTitle"), NNPSpotifySharedPreferences));
    id artistValue = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("SpotifyLyricsTrackArtist"), NNPSpotifySharedPreferences));
    id identifierValue = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("SpotifyLyricsTrackIdentifier"), NNPSpotifySharedPreferences));
    id linesValue = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("SpotifyLyricsTimedLines"), NNPSpotifySharedPreferences));
    NSString *title = [titleValue isKindOfClass:NSString.class] ? titleValue : @"";
    NSString *artist = [artistValue isKindOfClass:NSString.class] ? artistValue : @"";
    NSString *identifier = [identifierValue isKindOfClass:NSString.class] ? identifierValue : @"";
    BOOL hasLines = [linesValue isKindOfClass:NSArray.class] && [linesValue count];
    NNPSpotifySetVerifiedLyricsTrack(hasLines ? title : @"", hasLines ? artist : @"", hasLines ? identifier : @"");
}

static void NNPSpotifyRememberTrackForLyricsRequest(NSURLRequest *request) {
    NSString *path = request.URL.path;
    if (!path.length || ![request.URL.absoluteString.lowercaseString containsString:@"lyrics"]) return;
    NSDictionary *nowPlaying = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo ?: @{};
    NSString *title = [nowPlaying[MPMediaItemPropertyTitle] isKindOfClass:NSString.class]
        ? nowPlaying[MPMediaItemPropertyTitle] : @"";
    NSString *artist = [nowPlaying[MPMediaItemPropertyArtist] isKindOfClass:NSString.class]
        ? nowPlaying[MPMediaItemPropertyArtist] : @"";
    NSString *identifier = request.URL.lastPathComponent ?: @"";
    NSString *currentIdentifier = NNPSpotifyTrackIdentifierFromMetadata(nowPlaying);
    NNPSpotifyEnsureTrackContextStore();
    NSDictionary *context = @{@"capturedAt": @(NSDate.date.timeIntervalSince1970),
                              @"title": title, @"artist": artist, @"identifier": identifier};
    @synchronized (NNPSpotifyTrackContextLock) {
        NSTimeInterval cutoff = NSDate.date.timeIntervalSince1970 - 300.0;
        for (NSString *key in NNPSpotifyTrackContextByRequestPath.allKeys.copy) {
            if ([NNPSpotifyTrackContextByRequestPath[key][@"capturedAt"] doubleValue] < cutoff)
                [NNPSpotifyTrackContextByRequestPath removeObjectForKey:key];
        }
        if (NNPSpotifyTrackContextByRequestPath.count >= 64 && !NNPSpotifyTrackContextByRequestPath[path])
            [NNPSpotifyTrackContextByRequestPath removeObjectForKey:NNPSpotifyTrackContextByRequestPath.allKeys.firstObject];
        NNPSpotifyTrackContextByRequestPath[path] = context;
    }
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"NETWORK-CONTEXT id=%@ currentID=%@ title=%@ artist=%@",
                           identifier, currentIdentifier, title, artist]);
}

static NSDictionary *NNPSpotifyTrackContextForLyricsRequest(NSURLRequest *request) {
    NSString *path = request.URL.path;
    if (!path.length) return nil;
    NNPSpotifyEnsureTrackContextStore();
    @synchronized (NNPSpotifyTrackContextLock) {
        return NNPSpotifyTrackContextByRequestPath[path];
    }
}

static NSString *NNPSpotifyLyricsProbePath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"nnp-spotify-lyrics-runtime.log"];
}

void NNPSpotifyLyricsProbeResetLog(void) {
    int fd = open(NNPSpotifyLyricsProbePath().fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) close(fd);
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

void NNPSpotifyLyricsProbeAppendDiagnostic(NSString *line) {
    NNPSpotifyProbeAppend(line);
}

typedef struct {
    const uint8_t *bytes;
    NSUInteger length;
    NSUInteger offset;
} NNPSpotifyProtoReader;

static BOOL NNPSpotifyProtoReadVarint(NNPSpotifyProtoReader *reader, uint64_t *value) {
    if (!reader || !value) return NO;
    uint64_t result = 0;
    for (NSUInteger shift = 0; shift < 64 && reader->offset < reader->length; shift += 7) {
        uint8_t byte = reader->bytes[reader->offset++];
        result |= ((uint64_t)(byte & 0x7f)) << shift;
        if ((byte & 0x80) == 0) {
            *value = result;
            return YES;
        }
    }
    return NO;
}

static BOOL NNPSpotifyProtoReadBytes(NNPSpotifyProtoReader *reader, const uint8_t **bytes, NSUInteger *length) {
    uint64_t encodedLength = 0;
    if (!NNPSpotifyProtoReadVarint(reader, &encodedLength) || encodedLength > NSUIntegerMax) return NO;
    NSUInteger count = (NSUInteger)encodedLength;
    if (count > reader->length - reader->offset) return NO;
    if (bytes) *bytes = reader->bytes + reader->offset;
    if (length) *length = count;
    reader->offset += count;
    return YES;
}

static BOOL NNPSpotifyProtoSkipField(NNPSpotifyProtoReader *reader, uint32_t wireType) {
    uint64_t ignored = 0;
    const uint8_t *bytes = NULL;
    NSUInteger length = 0;
    switch (wireType) {
        case 0: return NNPSpotifyProtoReadVarint(reader, &ignored);
        case 1:
            if (reader->length - reader->offset < 8) return NO;
            reader->offset += 8;
            return YES;
        case 2: return NNPSpotifyProtoReadBytes(reader, &bytes, &length);
        case 5:
            if (reader->length - reader->offset < 4) return NO;
            reader->offset += 4;
            return YES;
        default: return NO;
    }
}

static NSDictionary *NNPSpotifyParseColorLyricsLine(const uint8_t *bytes, NSUInteger length) {
    NNPSpotifyProtoReader reader = {bytes, length, 0};
    uint64_t startTimeMs = 0;
    BOOL hasStartTime = NO;
    NSString *words = nil;
    while (reader.offset < reader.length) {
        uint64_t tag = 0;
        if (!NNPSpotifyProtoReadVarint(&reader, &tag) || tag == 0) return nil;
        uint32_t fieldNumber = (uint32_t)(tag >> 3);
        uint32_t wireType = (uint32_t)(tag & 7);
        if (fieldNumber == 1 && wireType == 0) {
            if (!NNPSpotifyProtoReadVarint(&reader, &startTimeMs)) return nil;
            hasStartTime = YES;
        } else if (fieldNumber == 2 && wireType == 2) {
            const uint8_t *textBytes = NULL;
            NSUInteger textLength = 0;
            if (!NNPSpotifyProtoReadBytes(&reader, &textBytes, &textLength)) return nil;
            words = [[NSString alloc] initWithBytes:textBytes length:textLength encoding:NSUTF8StringEncoding];
        } else if (!NNPSpotifyProtoSkipField(&reader, wireType)) {
            return nil;
        }
    }
    if (!hasStartTime || !words.length || [words isEqualToString:@"♪"] || startTimeMs > LLONG_MAX) return nil;
    return @{@"startTimeMs": @((long long)startTimeMs), @"words": words};
}

static NSArray<NSDictionary *> *NNPSpotifyParseColorLyricsResponse(NSData *data, NSString **syncTypeOut) {
    if (!data.length) return nil;
    NNPSpotifyProtoReader response = {data.bytes, data.length, 0};
    NSMutableArray<NSDictionary *> *lines = [NSMutableArray array];
    NSString *syncType = @"UNSYNCED";
    BOOL foundLyricsMessage = NO;
    while (response.offset < response.length) {
        uint64_t tag = 0;
        if (!NNPSpotifyProtoReadVarint(&response, &tag) || tag == 0) return nil;
        uint32_t fieldNumber = (uint32_t)(tag >> 3);
        uint32_t wireType = (uint32_t)(tag & 7);
        if (fieldNumber == 1 && wireType == 2) {
            const uint8_t *lyricsBytes = NULL;
            NSUInteger lyricsLength = 0;
            if (!NNPSpotifyProtoReadBytes(&response, &lyricsBytes, &lyricsLength)) return nil;
            foundLyricsMessage = YES;
            NNPSpotifyProtoReader lyrics = {lyricsBytes, lyricsLength, 0};
            while (lyrics.offset < lyrics.length) {
                uint64_t lyricsTag = 0;
                if (!NNPSpotifyProtoReadVarint(&lyrics, &lyricsTag) || lyricsTag == 0) return nil;
                uint32_t lyricsField = (uint32_t)(lyricsTag >> 3);
                uint32_t lyricsWire = (uint32_t)(lyricsTag & 7);
                if (lyricsField == 1 && lyricsWire == 0) {
                    uint64_t enumValue = 0;
                    if (!NNPSpotifyProtoReadVarint(&lyrics, &enumValue)) return nil;
                    syncType = enumValue == 1 ? @"LINE_SYNCED" : enumValue == 2 ? @"SYLLABLE_SYNCED" : @"UNSYNCED";
                } else if (lyricsField == 2 && lyricsWire == 2) {
                    const uint8_t *lineBytes = NULL;
                    NSUInteger lineLength = 0;
                    if (!NNPSpotifyProtoReadBytes(&lyrics, &lineBytes, &lineLength)) return nil;
                    NSDictionary *line = NNPSpotifyParseColorLyricsLine(lineBytes, lineLength);
                    if (line) [lines addObject:line];
                    if (lines.count > 2000) return nil;
                } else if (!NNPSpotifyProtoSkipField(&lyrics, lyricsWire)) {
                    return nil;
                }
            }
        } else if (!NNPSpotifyProtoSkipField(&response, wireType)) {
            return nil;
        }
    }
    if (syncTypeOut) *syncTypeOut = syncType;
    return foundLyricsMessage && lines.count ? [lines copy] : nil;
}

static void NNPSpotifyPublishTimedLyrics(NSArray<NSDictionary *> *lines, NSString *syncType, NSURLRequest *request) {
    NSDictionary *nowPlaying = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo ?: @{};
    NSDictionary *requestContext = NNPSpotifyTrackContextForLyricsRequest(request);
    NSString *currentTrackTitle = [nowPlaying[MPMediaItemPropertyTitle] isKindOfClass:NSString.class]
        ? nowPlaying[MPMediaItemPropertyTitle] : @"";
    NSString *currentTrackArtist = [nowPlaying[MPMediaItemPropertyArtist] isKindOfClass:NSString.class]
        ? nowPlaying[MPMediaItemPropertyArtist] : @"";
    NSString *requestedTrackTitle = [requestContext[@"title"] isKindOfClass:NSString.class]
        ? requestContext[@"title"] : @"";
    NSString *requestedTrackArtist = [requestContext[@"artist"] isKindOfClass:NSString.class]
        ? requestContext[@"artist"] : @"";
    NSString *requestedTrackIdentifier = [requestContext[@"identifier"] isKindOfClass:NSString.class]
        ? requestContext[@"identifier"] : @"";
    NSString *currentTrackIdentifier = NNPSpotifyTrackIdentifierFromMetadata(nowPlaying);
    BOOL identityMatches = NO;
    NSString *identitySource = @"metadata";
    if (requestedTrackIdentifier.length && currentTrackIdentifier.length) {
        identityMatches = [requestedTrackIdentifier isEqualToString:currentTrackIdentifier];
        identitySource = @"spotify-id";
    } else if (requestedTrackTitle.length && currentTrackTitle.length) {
        identityMatches = NNPSpotifyTrackMetadataMatches(requestedTrackTitle, requestedTrackArtist,
                                                         currentTrackTitle, currentTrackArtist);
    }
    if (!requestContext || !identityMatches) {
        NNPSpotifyProbeAppend([NSString stringWithFormat:
                               @"NETWORK-PARSE dropped unverified response id=%@ currentID=%@ request=%@/%@ current=%@/%@",
                               requestedTrackIdentifier, currentTrackIdentifier,
                               requestedTrackTitle, requestedTrackArtist, currentTrackTitle, currentTrackArtist]);
        return;
    }
    id elapsedValue = nowPlaying[MPNowPlayingInfoPropertyElapsedPlaybackTime];
    NSTimeInterval elapsed = [elapsedValue respondsToSelector:@selector(doubleValue)] ? [elapsedValue doubleValue] : 0.0;
    NSUInteger currentIndex = 0;
    for (NSUInteger index = 1; index < lines.count; index++) {
        if ([lines[index][@"startTimeMs"] doubleValue] > elapsed * 1000.0) break;
        currentIndex = index;
    }
    NSString *current = lines[currentIndex][@"words"] ?: @"";
    NSString *next = currentIndex + 1 < lines.count ? (lines[currentIndex + 1][@"words"] ?: @"") : @"";
    NSString *trackTitle = currentTrackTitle.length ? currentTrackTitle : requestedTrackTitle;
    NSString *trackArtist = currentTrackArtist.length ? currentTrackArtist : requestedTrackArtist;
    NSString *trackIdentifier = requestedTrackIdentifier;
    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsTimedLines"), (__bridge CFArrayRef)lines, NNPSpotifySharedPreferences);
    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsSyncType"), (__bridge CFStringRef)(syncType ?: @"UNSYNCED"), NNPSpotifySharedPreferences);
    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsText"), (__bridge CFStringRef)current, NNPSpotifySharedPreferences);
    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsNextLine"), (__bridge CFStringRef)next, NNPSpotifySharedPreferences);
    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsTrackTitle"), (__bridge CFStringRef)trackTitle, NNPSpotifySharedPreferences);
    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsTrackArtist"), (__bridge CFStringRef)trackArtist, NNPSpotifySharedPreferences);
    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsTrackIdentifier"), (__bridge CFStringRef)trackIdentifier, NNPSpotifySharedPreferences);
    CFPreferencesSetAppValue(CFSTR("SpotifyLyricsUpdatedAt"), (__bridge CFDateRef)NSDate.date, NNPSpotifySharedPreferences);
    Boolean synchronized = CFPreferencesAppSynchronize(NNPSpotifySharedPreferences);
    if (synchronized) NNPSpotifySetVerifiedLyricsTrack(trackTitle, trackArtist, trackIdentifier);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         NNPSpotifyLyricsChangedNotification, NULL, NULL, true);
    NSString *trackID = request.URL.lastPathComponent ?: @"";
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"NETWORK-PARSED lines=%lu sync=%@ track=%@ identity=%@ source=%@ firstStartMs=%@ shared=%@",
                           (unsigned long)lines.count, syncType ?: @"UNSYNCED", trackID,
                           trackIdentifier, identitySource,
                           lines.firstObject[@"startTimeMs"] ?: @"?", synchronized ? @"YES" : @"NO"]);
}

BOOL NNPSpotifyLyricsProbeShouldTraceNetworkRequest(NSURLRequest *request) {
    NSString *url = request.URL.absoluteString.lowercaseString ?: @"";
    return [url containsString:@"lyrics"] || [url containsString:@"spclient.wg.spotify.com"];
}

void NNPSpotifyLyricsProbeCaptureNetworkResponse(NSURLRequest *request, NSData *data, NSURLResponse *response, NSError *error) {
    NSString *url = request.URL.absoluteString ?: @"";
    NSString *lowercase = url.lowercaseString;
    if (!NNPSpotifyLyricsProbeShouldTraceNetworkRequest(request)) return;
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    if (![lowercase containsString:@"lyrics"]) {
        NNPSpotifyProbeAppend([NSString stringWithFormat:@"NETWORK request status=%ld bytes=%lu url=%@", (long)status, (unsigned long)data.length, url]);
        return;
    }
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"NETWORK-LYRICS status=%ld bytes=%lu mime=%@ error=%@ url=%@ body=redacted",
                           (long)status, (unsigned long)data.length, response.MIMEType ?: @"", error.localizedDescription ?: @"", url]);
    if (status == 200 && !error && [response.MIMEType.lowercaseString containsString:@"protobuf"]) {
        NSString *syncType = nil;
        NSArray<NSDictionary *> *lines = NNPSpotifyParseColorLyricsResponse(data, &syncType);
        if (lines.count) NNPSpotifyPublishTimedLyrics(lines, syncType, request);
        else NNPSpotifyProbeAppend([NSString stringWithFormat:@"NETWORK-PARSE failed bytes=%lu mime=%@", (unsigned long)data.length, response.MIMEType ?: @""]);
    }
}

void NNPSpotifyLyricsProbeCaptureNetworkTask(NSURLSession *session, NSURLRequest *request) {
    if (!NNPSpotifyLyricsProbeShouldTraceNetworkRequest(request)) return;
    NNPSpotifyRememberTrackForLyricsRequest(request);
    if ([request.URL.absoluteString.lowercaseString containsString:@"lyrics"]) {
        @synchronized (NNPSpotifyTrackContextLock) {
            if (session) NNPSpotifyLyricsRequestSession = session;
            NNPSpotifyLyricsRequestTemplate = [request copy];
        }
    }
    NSURLComponents *components = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    NSMutableArray<NSString *> *queryKeys = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        if (item.name.length) [queryKeys addObject:item.name];
    }
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"NETWORK-TASK method=%@ host=%@ path=%@ queryKeys=%@",
                           request.HTTPMethod ?: @"GET", components.host ?: @"", components.path ?: @"/",
                           [queryKeys componentsJoinedByString:@","]]);
}

void NNPSpotifyLyricsProbeCaptureNetworkData(NSURLSessionTask *task, NSData *data) {
    if (!task || !data.length) return;
    NSURLRequest *request = task.originalRequest ?: task.currentRequest;
    if (!request || ![request.URL.absoluteString.lowercaseString containsString:@"lyrics"]) return;

    NSMutableData *body = objc_getAssociatedObject(task, &NNPSpotifyNetworkBodyAssociationKey);
    if (!body) {
        body = [NSMutableData data];
        objc_setAssociatedObject(task, &NNPSpotifyNetworkBodyAssociationKey, body, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    const NSUInteger maximumBytes = 256 * 1024;
    NSUInteger remaining = body.length < maximumBytes ? maximumBytes - body.length : 0;
    NSUInteger bytesToAppend = MIN(data.length, remaining);
    if (bytesToAppend) {
        NSData *chunk = bytesToAppend == data.length ? data : [data subdataWithRange:NSMakeRange(0, bytesToAppend)];
        [body appendData:chunk];
    }
    if (bytesToAppend < data.length)
        objc_setAssociatedObject(task, &NNPSpotifyNetworkBodyTruncatedAssociationKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void NNPSpotifyLyricsProbeCompleteNetworkTask(NSURLSessionTask *task, NSError *error) {
    if (!task) return;
    NSURLRequest *request = task.originalRequest ?: task.currentRequest;
    NSMutableData *body = objc_getAssociatedObject(task, &NNPSpotifyNetworkBodyAssociationKey);
    NSNumber *truncated = objc_getAssociatedObject(task, &NNPSpotifyNetworkBodyTruncatedAssociationKey);
    if (request && NNPSpotifyLyricsProbeShouldTraceNetworkRequest(request)) {
        if ([request.URL.absoluteString.lowercaseString containsString:@"lyrics"] && body.length) {
            NNPSpotifyLyricsProbeCaptureNetworkResponse(request, body, task.response, error);
            if (truncated.boolValue)
                NNPSpotifyProbeAppend([NSString stringWithFormat:@"NETWORK-LYRICS body-truncated task=%p cap=%lu", task, (unsigned long)body.length]);
        } else {
            NSInteger status = [task.response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)task.response).statusCode : 0;
            NNPSpotifyProbeAppend([NSString stringWithFormat:@"NETWORK-DONE method=%@ status=%ld bytes=%lld error=%@ url=%@",
                                   request.HTTPMethod ?: @"GET", (long)status, task.countOfBytesReceived,
                                   error.localizedDescription ?: @"", request.URL.absoluteString ?: @""]);
        }
    }
    objc_setAssociatedObject(task, &NNPSpotifyNetworkBodyAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(task, &NNPSpotifyNetworkBodyTruncatedAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL NNPSpotifyIsRelevantModelClass(Class cls) {
    NSString *name = NSStringFromClass(cls) ?: @"";
    return NNPSpotifyStringContainsAny(name, @[@"lyrics", @"line", @"progress", @"position", @"provider", @"model", @"event"]);
}

static BOOL NNPSpotifyIvarStoresKnownObject(NSString *name, NSString *type) {
    if ([type hasPrefix:@"@"] || [type hasPrefix:@"^{"]) return YES;
    NSString *lowercase = name.lowercaseString;
    // Swift's Objective-C runtime metadata deliberately omits the type
    // encoding for many stored properties. Limit raw object reads to fields
    // Spotify exposes as references in its lyrics view-model graph.
    static NSArray<NSString *> *knownNames;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        knownNames = @[@"lyricsmodel", @"selectedlines", @"progresseventsource",
                       @"lyricslinemodels", @"lyricslines", @"lineprovider",
                       @"viewmodel", @"datasource", @"eventsource", @"binder",
                       @"listener", @"delegate", @"element", @"translation"];
    });
    for (NSString *knownName in knownNames) if ([lowercase containsString:knownName]) return YES;
    return NO;
}

static NSString *NNPSpotifyScalarIvarValue(id object, Ivar ivar) {
    const char *encoding = ivar_getTypeEncoding(ivar);
    if (!encoding || !encoding[0] || encoding[0] == '@' || encoding[0] == '^' || encoding[0] == '{' || encoding[0] == '(') return nil;
    ptrdiff_t offset = ivar_getOffset(ivar);
    if (offset < 0) return nil;
    NSUInteger instanceSize = class_getInstanceSize(object_getClass(object));
    const uint8_t *bytes = (const uint8_t *)(__bridge const void *)object;
    switch (encoding[0]) {
        case 'c': case 'C': case 'B': {
            int8_t value = 0; if ((NSUInteger)offset + sizeof(value) > instanceSize) return nil;
            memcpy(&value, bytes + offset, sizeof(value)); return [NSString stringWithFormat:@"%d", value];
        }
        case 's': case 'S': {
            int16_t value = 0; if ((NSUInteger)offset + sizeof(value) > instanceSize) return nil;
            memcpy(&value, bytes + offset, sizeof(value)); return [NSString stringWithFormat:@"%d", value];
        }
        case 'i': case 'I': {
            int32_t value = 0; if ((NSUInteger)offset + sizeof(value) > instanceSize) return nil;
            memcpy(&value, bytes + offset, sizeof(value)); return [NSString stringWithFormat:@"%d", value];
        }
        case 'l': case 'L': case 'q': case 'Q': {
            int64_t value = 0; if ((NSUInteger)offset + sizeof(value) > instanceSize) return nil;
            memcpy(&value, bytes + offset, sizeof(value)); return [NSString stringWithFormat:@"%lld", (long long)value];
        }
        case 'f': {
            float value = 0; if ((NSUInteger)offset + sizeof(value) > instanceSize) return nil;
            memcpy(&value, bytes + offset, sizeof(value)); return [NSString stringWithFormat:@"%.4f", value];
        }
        case 'd': {
            double value = 0; if ((NSUInteger)offset + sizeof(value) > instanceSize) return nil;
            memcpy(&value, bytes + offset, sizeof(value)); return [NSString stringWithFormat:@"%.4f", value];
        }
        default: return nil;
    }
}

static NSString *NNPSpotifyLyricsObjectSnapshot(id object, NSUInteger depth, NSMutableSet<NSString *> *visited) {
    if (!object || depth > 4) return @"";
    Class cls = object_getClass(object);
    NSString *className = NSStringFromClass(cls) ?: @"?";
    if ([object isKindOfClass:NSString.class]) {
        NSString *value = [(NSString *)object stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        return [NSString stringWithFormat:@"%@(%@)", className, [value substringToIndex:MIN(value.length, 100)]];
    }
    if ([object isKindOfClass:NSNumber.class]) return [NSString stringWithFormat:@"%@(%@)", className, object];
    if ([object isKindOfClass:NSArray.class]) {
        NSArray *array = (NSArray *)object;
        NSMutableArray *items = [NSMutableArray array];
        NSUInteger count = MIN(array.count, 6);
        for (NSUInteger index = 0; index < count; index++) {
            [items addObject:NNPSpotifyLyricsObjectSnapshot(array[index], depth + 1, visited) ?: @"?"];
        }
        return [NSString stringWithFormat:@"%@[%lu]{%@}", className, (unsigned long)array.count, [items componentsJoinedByString:@","]];
    }

    NSString *imagePath = [NSString stringWithUTF8String:class_getImageName(cls) ?: ""];
    if (![imagePath containsString:@"Spotify.app/Spotify"] || !NNPSpotifyIsRelevantModelClass(cls)) return [NSString stringWithFormat:@"%@", className];
    NSString *objectKey = [NSString stringWithFormat:@"%p", object];
    if ([visited containsObject:objectKey]) return [NSString stringWithFormat:@"%@@%@", className, objectKey];
    [visited addObject:objectKey];

    NSMutableArray<NSString *> *fields = [NSMutableArray array];
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        NSString *currentImage = [NSString stringWithUTF8String:class_getImageName(current) ?: ""];
        if (![currentImage containsString:@"Spotify.app/Spotify"]) break;
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(current, &count);
        for (unsigned int index = 0; index < count; index++) {
            Ivar ivar = ivars[index];
            const char *rawName = ivar_getName(ivar);
            const char *rawType = ivar_getTypeEncoding(ivar);
            NSString *name = rawName ? [NSString stringWithUTF8String:rawName] : @"?";
            NSString *type = rawType ? [NSString stringWithUTF8String:rawType] : @"?";
            if (NNPSpotifyIvarStoresKnownObject(name, type)) {
                id value = object_getIvar(object, ivar);
                if (!value) {
                    [fields addObject:[NSString stringWithFormat:@"%@:%@=nil", name, type]];
                } else {
                    NSString *valueName = NSStringFromClass(object_getClass(value)) ?: @"?";
                    NSString *valueSummary = [NSString stringWithFormat:@"%@@%p", valueName, value];
                    if (depth < 4 && NNPSpotifyIsRelevantModelClass(object_getClass(value))) {
                        valueSummary = NNPSpotifyLyricsObjectSnapshot(value, depth + 1, visited);
                    } else if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSArray.class]) {
                        valueSummary = NNPSpotifyLyricsObjectSnapshot(value, depth + 1, visited);
                    }
                    [fields addObject:[NSString stringWithFormat:@"%@:%@=%@", name, type, valueSummary ?: @"?"]];
                }
            } else {
                NSString *scalar = NNPSpotifyScalarIvarValue(object, ivar);
                [fields addObject:[NSString stringWithFormat:@"%@:%@=%@", name, type, scalar ?: @"?"]];
            }
        }
        free(ivars);
    }
    return [NSString stringWithFormat:@"%@@%p{%@}", className, object, [fields componentsJoinedByString:@","]];
}

static void NNPSpotifyDumpLyricsObjectGraph(id object) {
    static NSMutableDictionary<NSString *, NSString *> *lastSnapshots;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lastSnapshots = [NSMutableDictionary dictionary]; });
    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    NSString *snapshot = NNPSpotifyLyricsObjectSnapshot(object, 0, visited);
    NSString *key = [NSString stringWithFormat:@"%p", object];
    if (!snapshot.length || [lastSnapshots[key] isEqualToString:snapshot]) return;
    lastSnapshots[key] = snapshot;
    if (lastSnapshots.count > 512) [lastSnapshots removeAllObjects];
    NNPSpotifyProbeAppend([@"MODEL-SNAPSHOT " stringByAppendingString:snapshot]);
}

static void NNPSpotifyDumpLyricsResponderModels(UIView *view) {
    static NSMutableDictionary<NSString *, NSString *> *lastResponderChains;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lastResponderChains = [NSMutableDictionary dictionary]; });
    NSMutableArray<NSString *> *chain = [NSMutableArray array];
    for (UIResponder *responder = view; responder && chain.count < 18; responder = responder.nextResponder) {
        Class cls = object_getClass(responder);
        NSString *name = NSStringFromClass(cls) ?: @"?";
        [chain addObject:name];
        if (!NNPSpotifyStringContainsAny(name, @[@"lyricsviewcontroller", @"lyricselementviewprovider", @"lyricsviewbinder"])) continue;
        NSString *key = [NSString stringWithFormat:@"%p", responder];
        NSString *joined = [chain componentsJoinedByString:@"<"];
        if (![lastResponderChains[key] isEqualToString:joined]) {
            lastResponderChains[key] = joined;
            NNPSpotifyProbeAppend([NSString stringWithFormat:@"MODEL-RESPONDER chain=%@", joined]);
        }
        NNPSpotifyDumpLyricsObjectGraph(responder);
    }
    if (lastResponderChains.count > 256) [lastResponderChains removeAllObjects];
}

static NSString *NNPSpotifyNormalizeLyricsText(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (line.length) [parts addObject:line];
    }
    return [parts componentsJoinedByString:@" "];
}

static BOOL NNPSpotifyStringContainsAny(NSString *value, NSArray<NSString *> *needles) {
    NSString *lowercase = value.lowercaseString;
    for (NSString *needle in needles) if ([lowercase containsString:needle]) return YES;
    return NO;
}

static void NNPSpotifyDumpLyricsRuntime(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        int classCount = objc_getClassList(NULL, 0);
        if (classCount <= 0) return;
        __unsafe_unretained Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
        if (!classes) return;
        classCount = objc_getClassList(classes, classCount);
        NSArray<NSString *> *classTerms = @[@"lyric", @"encore", @"karaoke", @"musixmatch", @"timedtext"];
        NSArray<NSString *> *selectorTerms = @[@"lyric", @"line", @"time", @"progress", @"active", @"current", @"index", @"position", @"sync", @"playback"];
        NSUInteger emitted = 0;
        for (int index = 0; index < classCount && emitted < 160; index++) {
            Class cls = classes[index];
            NSString *name = NSStringFromClass(cls) ?: @"";
            if (!NNPSpotifyStringContainsAny(name, classTerms)) continue;
            Class superclass = class_getSuperclass(cls);
            NSMutableArray<NSString *> *properties = [NSMutableArray array];
            unsigned int propertyCount = 0;
            objc_property_t *propertyList = class_copyPropertyList(cls, &propertyCount);
            for (unsigned int propertyIndex = 0; propertyIndex < propertyCount; propertyIndex++) {
                const char *propertyName = property_getName(propertyList[propertyIndex]);
                const char *attributes = property_getAttributes(propertyList[propertyIndex]);
                if (propertyName) [properties addObject:[NSString stringWithFormat:@"%s:%s", propertyName, attributes ?: "?"]];
            }
            free(propertyList);
            NSMutableArray<NSString *> *ivars = [NSMutableArray array];
            unsigned int ivarCount = 0;
            Ivar *ivarList = class_copyIvarList(cls, &ivarCount);
            for (unsigned int ivarIndex = 0; ivarIndex < ivarCount; ivarIndex++) {
                const char *ivarName = ivar_getName(ivarList[ivarIndex]);
                const char *type = ivar_getTypeEncoding(ivarList[ivarIndex]);
                if (ivarName) [ivars addObject:[NSString stringWithFormat:@"%s:%s@%td", ivarName, type ?: "?", ivar_getOffset(ivarList[ivarIndex])]];
            }
            free(ivarList);
            NSMutableArray<NSString *> *selectors = [NSMutableArray array];
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                NSString *selector = NSStringFromSelector(method_getName(methods[methodIndex]));
                if (NNPSpotifyStringContainsAny(selector, selectorTerms)) [selectors addObject:selector];
            }
            free(methods);
            NNPSpotifyProbeAppend([NSString stringWithFormat:@"RUNTIME class=%@ super=%@ properties=%@ ivars=%@ selectors=%@",
                                   name, superclass ? NSStringFromClass(superclass) : @"none",
                                   [properties componentsJoinedByString:@","], [ivars componentsJoinedByString:@","],
                                   [selectors componentsJoinedByString:@","]]);
            emitted++;
        }
        NNPSpotifyProbeAppend([NSString stringWithFormat:@"RUNTIME summary classes=%d emitted=%lu", classCount, (unsigned long)emitted]);
        free(classes);
    });
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
        UITableViewCell *lyricsCell = nil;
        UITableView *lyricsTable = nil;
        for (UIView *candidate = view.superview; candidate; candidate = candidate.superview) {
            if (!lyricsCell && [candidate isKindOfClass:UITableViewCell.class]) lyricsCell = (UITableViewCell *)candidate;
            if ([candidate isKindOfClass:UITableView.class]) { lyricsTable = (UITableView *)candidate; break; }
        }
        NSIndexPath *visibleCellPath = lyricsCell && lyricsTable ? [lyricsTable indexPathForCell:lyricsCell] : nil;
        BOOL belongsToVisibleLyricsCell = visibleCellPath &&
            [[lyricsTable indexPathsForVisibleRows] containsObject:visibleCellPath];
        if (text.length >= 2 && !NNPSpotifyIsNonLyricLabel(text) &&
            frame.size.height >= 12.0 && frame.size.height <= 100.0 &&
            (CGRectIntersectsRect(frame, window.bounds) || belongsToVisibleLyricsCell)) {
            UILabel *label = (UILabel *)view;
            NSMutableArray<NSString *> *ancestors = [NSMutableArray array];
            UIView *ancestor = view.superview;
            NSUInteger ancestorDepth = 0;
            while (ancestor && ancestorDepth++ < 24) {
                NSString *ancestorName = NSStringFromClass(ancestor.class) ?: @"?";
                if ([ancestor isKindOfClass:UIScrollView.class]) {
                    CGPoint offset = ((UIScrollView *)ancestor).contentOffset;
                    ancestorName = [NSString stringWithFormat:@"%@{offset=%.1f,%.1f}", ancestorName, offset.x, offset.y];
                }
                [ancestors addObject:ancestorName];
                ancestor = ancestor.superview;
            }
            NSMutableArray<NSString *> *textAttributes = [NSMutableArray array];
            [label.attributedText enumerateAttributesInRange:NSMakeRange(0, label.attributedText.length)
                                                     options:0
                                                  usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attributes, NSRange range, BOOL *stop) {
                id foreground = attributes[NSForegroundColorAttributeName];
                id font = attributes[NSFontAttributeName];
                [textAttributes addObject:[NSString stringWithFormat:@"%lu:color=%@,font=%@", (unsigned long)range.length,
                                           foreground ?: @"default", font ?: @"default"]];
            }];
            NSString *cellState = @"none";
            NSInteger cellRow = -1;
            NSInteger centerRow = -1;
            CGFloat tableCenterY = CGRectGetMidY(window.bounds);
            NSUInteger visibleCellCount = 0;
            NSString *tableIdentity = @"none";
            NSString *lyricsSurface = @"unknown";
            NSString *ancestorPath = [ancestors componentsJoinedByString:@"<"];
            if ([ancestorPath containsString:@"Lyrics_CardElementImpl.CardView"]) lyricsSurface = @"now-playing-card";
            else if ([ancestorPath containsString:@"Lyrics_FullscreenElementPageImpl.FullscreenView"]) lyricsSurface = @"fullscreen";
            if (lyricsCell) {
                NNPSpotifyDumpLyricsObjectGraph(lyricsCell);
                NNPSpotifyDumpLyricsResponderModels(lyricsCell);
                NSIndexPath *indexPath = [lyricsTable indexPathForCell:lyricsCell];
                cellRow = indexPath ? (NSInteger)indexPath.row : -1;
                NSIndexPath *centerIndexPath = nil;
                NSString *tableState = @"no-table";
                if (lyricsTable) {
                    CGPoint center = CGPointMake(CGRectGetMidX(lyricsTable.bounds), CGRectGetMidY(lyricsTable.bounds));
                    centerIndexPath = [lyricsTable indexPathForRowAtPoint:center];
                    centerRow = centerIndexPath ? (NSInteger)centerIndexPath.row : -1;
                    visibleCellCount = lyricsTable.indexPathsForVisibleRows.count;
                    tableIdentity = [NSString stringWithFormat:@"%p", lyricsTable];
                    CGRect tableFrame = [lyricsTable convertRect:lyricsTable.bounds toView:window];
                    tableCenterY = CGRectGetMidY(tableFrame);
                    tableState = [NSString stringWithFormat:@"table=%p frame=%.1f,%.1f,%.1f,%.1f centerRow=%ld visible=%lu offset=%.1f",
                                  lyricsTable, tableFrame.origin.x, tableFrame.origin.y, tableFrame.size.width, tableFrame.size.height,
                                  centerIndexPath ? (long)centerIndexPath.row : -1L,
                                  (unsigned long)lyricsTable.indexPathsForVisibleRows.count,
                                  lyricsTable.contentOffset.y];
                }
                cellState = [NSString stringWithFormat:@"%@ row=%ld section=%ld selected=%@ highlighted=%@ reuse=%@",
                             NSStringFromClass(lyricsCell.class), (long)indexPath.row, (long)indexPath.section,
                             lyricsCell.selected ? @"YES" : @"NO", lyricsCell.highlighted ? @"YES" : @"NO",
                             lyricsCell.reuseIdentifier ?: @""];
                cellState = [cellState stringByAppendingFormat:@" %@", tableState];
            }
            [rows addObject:@{@"text": text, @"midY": @(CGRectGetMidY(frame)),
                              @"class": className,
                              @"alpha": @(label.alpha),
                              @"font": label.font.fontName ?: @"",
                              @"fontSize": @(label.font.pointSize),
                              @"color": label.textColor.description ?: @"",
                              @"identifier": label.accessibilityIdentifier ?: @"",
                              @"ancestors": [ancestors componentsJoinedByString:@"<"],
                              @"cellState": cellState,
                              @"cellRow": @(cellRow),
                              @"tableCenterRow": @(centerRow),
                              @"tableCenterY": @(tableCenterY),
                              @"tableVisibleCount": @(visibleCellCount),
                              @"tableIdentity": tableIdentity,
                              @"lyricsSurface": lyricsSurface,
                              @"z": @(label.layer.zPosition),
                              @"textAttributes": [textAttributes componentsJoinedByString:@"|"]}];
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
    NSString *trackIdentifier = NNPSpotifyTrackIdentifierFromMetadata(nowPlaying);
    if (!NNPSpotifyVisibleLyricsMatchVerifiedTrack(trackTitle, trackArtist, trackIdentifier)) {
        static NSString *lastRejectedTitle;
        static NSString *lastRejectedArtist;
        if (![lastRejectedTitle isEqualToString:trackTitle] || ![lastRejectedArtist isEqualToString:trackArtist]) {
            lastRejectedTitle = [trackTitle copy];
            lastRejectedArtist = [trackArtist copy];
            NNPSpotifyProbeAppend(@"LYRICS-SCREEN ignored until backend snapshot matches current track");
        }
        return NO;
    }
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
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"LYRICS publish lines=%lu sync=%@ track=%@ verifiedID=%@ current=%@", (unsigned long)visibleLines.count,
                           synchronized ? @"YES" : @"NO", trackTitle,
                           NNPSpotifyVerifiedLyricsTrackIdentifier(), current]);
    [NSUserDefaults.standardUserDefaults setBool:synchronized forKey:@"NNPSpotifyLyricsSharedWriteSucceeded"];
    [NSUserDefaults.standardUserDefaults synchronize];
    return YES;
}

static void NNPSpotifyLyricsProbeCapture(void) {
    NSDictionary *playbackInfo = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo ?: @{};
    id elapsedValue = playbackInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime];
    NSTimeInterval playbackTime = [elapsedValue respondsToSelector:@selector(doubleValue)]
        ? [elapsedValue doubleValue] : -1.0;

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
    NSMutableSet<NSString *> *seenRowKeys = [NSMutableSet set];
    for (NSDictionary *row in rows) {
        NSString *text = row[@"text"];
        if (!text.length) continue;
        NSInteger rowIndex = [row[@"cellRow"] integerValue];
        NSString *tableIdentity = row[@"tableIdentity"];
        NSString *rowKey = rowIndex >= 0 && ![tableIdentity isEqualToString:@"none"]
            ? [NSString stringWithFormat:@"%@|%ld", tableIdentity, (long)rowIndex]
            : [NSString stringWithFormat:@"%@|%@|%.0f", row[@"lyricsSurface"], text, [row[@"midY"] doubleValue]];
        if ([seenRowKeys containsObject:rowKey]) continue;
        [seenRowKeys addObject:rowKey];
        [uniqueRows addObject:row];
        if (![lines.lastObject isEqualToString:text]) [lines addObject:text];
    }
    if (lines.count == 0) {
        // Background Spotify can temporarily detach or hide its lyrics scene.
        // Preserve the most recent line instead of replacing it with an empty
        // value while playback continues.
        return;
    }

    NSDictionary *synchronizedRow = nil;
    NSInteger preferredSurfaceRank = -1;
    // The fullscreen lyrics page owns the live, auto-following list when it is
    // present. The compact Now Playing card can retain a separate stale offset.
    // Spotify's auto-follow anchor is the row under the table's viewport center;
    // do not compensate with a fixed row offset, which drifts across layouts.
    for (NSDictionary *row in uniqueRows) {
        if ([row[@"cellRow"] integerValue] < 0 ||
            [row[@"tableCenterRow"] integerValue] < 0 ||
            [row[@"tableIdentity"] isEqualToString:@"none"]) continue;
        NSString *surface = row[@"lyricsSurface"];
        NSInteger rank = [surface isEqualToString:@"fullscreen"] ? 2 :
                         [surface isEqualToString:@"now-playing-card"] ? 1 : 0;
        preferredSurfaceRank = MAX(preferredSurfaceRank, rank);
    }

    CGFloat nearestCenterDistance = CGFLOAT_MAX;
    NSUInteger selectedVisibleCount = 0;
    for (NSDictionary *row in uniqueRows) {
        if ([row[@"cellRow"] integerValue] < 0 ||
            [row[@"tableIdentity"] isEqualToString:@"none"]) continue;
        NSString *surface = row[@"lyricsSurface"];
        NSInteger rank = [surface isEqualToString:@"fullscreen"] ? 2 :
                         [surface isEqualToString:@"now-playing-card"] ? 1 : 0;
        if (rank != preferredSurfaceRank) continue;

        CGFloat distance = fabs([row[@"midY"] doubleValue] - [row[@"tableCenterY"] doubleValue]);
        NSUInteger visibleCount = [row[@"tableVisibleCount"] unsignedIntegerValue];
        NSInteger rowIndex = [row[@"cellRow"] integerValue];
        NSInteger centerIndex = [row[@"tableCenterRow"] integerValue];
        BOOL isCenterRow = rowIndex == centerIndex;
        BOOL selectedIsCenterRow = synchronizedRow &&
            [synchronizedRow[@"cellRow"] integerValue] == [synchronizedRow[@"tableCenterRow"] integerValue];
        if (!synchronizedRow ||
            (isCenterRow && !selectedIsCenterRow) ||
            (isCenterRow == selectedIsCenterRow && visibleCount > selectedVisibleCount) ||
            (isCenterRow == selectedIsCenterRow && visibleCount == selectedVisibleCount && distance < nearestCenterDistance)) {
            synchronizedRow = row;
            selectedVisibleCount = visibleCount;
            nearestCenterDistance = distance;
        }
    }

    NSString *current = nil;
    NSString *next = @"";
    if (synchronizedRow) {
        NSString *tableIdentity = synchronizedRow[@"tableIdentity"];
        NSInteger currentIndex = [synchronizedRow[@"cellRow"] integerValue];
        NSMutableArray<NSDictionary *> *activeTableRows = [NSMutableArray array];
        for (NSDictionary *row in uniqueRows) {
            if ([row[@"tableIdentity"] isEqualToString:tableIdentity] && [row[@"cellRow"] integerValue] >= 0)
                [activeTableRows addObject:row];
        }
        [activeTableRows sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [left[@"cellRow"] compare:right[@"cellRow"]];
        }];
        [lines removeAllObjects];
        NSInteger lastRow = -1;
        BOOL foundCurrent = NO;
        for (NSDictionary *row in activeTableRows) {
            NSInteger rowIndex = [row[@"cellRow"] integerValue];
            NSString *text = row[@"text"];
            if (rowIndex != lastRow && text.length) [lines addObject:text];
            if (!foundCurrent && rowIndex > currentIndex && text.length) {
                next = text;
                foundCurrent = YES;
            }
            lastRow = rowIndex;
        }
        current = synchronizedRow[@"text"];
    } else {
        CGFloat targetY = UIScreen.mainScreen.bounds.size.height * 0.31;
        NSUInteger activeIndex = 0;
        CGFloat nearestDistance = CGFLOAT_MAX;
        for (NSUInteger index = 0; index < uniqueRows.count; index++) {
            CGFloat distance = fabs([uniqueRows[index][@"midY"] doubleValue] - targetY);
            if (distance < nearestDistance) { nearestDistance = distance; activeIndex = index; }
        }
        current = lines[MIN(activeIndex, lines.count - 1)];
        next = activeIndex + 1 < lines.count ? lines[activeIndex + 1] : @"";
    }

    // Spotify freezes MPNowPlayingInfoPropertyElapsedPlaybackTime while its
    // lyrics surface is backgrounded. A monotonic row filter then turns every
    // legitimate new viewport into a permanent stale update. Publish changes
    // from the active lyrics surface and let its own auto-follow state decide.
    static NSString *lastSelectionSignature;
    static NSTimeInterval lastDiagnosticsTime;
    NSString *selectionSignature = [NSString stringWithFormat:@"%@|%@|%@", synchronizedRow[@"cellRow"] ?: @"fallback", current, next];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (![lastSelectionSignature isEqualToString:selectionSignature] || now - lastDiagnosticsTime >= 4.0) {
        lastSelectionSignature = selectionSignature;
        lastDiagnosticsTime = now;
        NSMutableArray<NSString *> *rowDetails = [NSMutableArray arrayWithCapacity:uniqueRows.count];
        for (NSDictionary *row in uniqueRows) {
            [rowDetails addObject:[NSString stringWithFormat:@"%@ y=%.1f a=%.2f z=%.1f font=%@/%.1f color=%@ id=%@ surface=%@ cell=%@ attrs=%@ class=%@",
                                   row[@"text"], [row[@"midY"] doubleValue], [row[@"alpha"] doubleValue],
                                   [row[@"z"] doubleValue], row[@"font"], [row[@"fontSize"] doubleValue], row[@"color"],
                                   row[@"identifier"], row[@"lyricsSurface"], row[@"cellState"],
                                   row[@"textAttributes"], row[@"class"]]];
        }
        NNPSpotifyProbeAppend([NSString stringWithFormat:@"RUNTIME rows=%@ source=%@ selectedRow=%ld centerRow=%ld playback=%.2f current=%@ next=%@",
                               [rowDetails componentsJoinedByString:@" | "],
                               synchronizedRow ? synchronizedRow[@"lyricsSurface"] : @"screen-center-fallback",
                               synchronizedRow ? [synchronizedRow[@"cellRow"] integerValue] : -1L,
                               synchronizedRow ? [synchronizedRow[@"tableCenterRow"] integerValue] : -1L,
                               playbackTime,
                               current, next]);
    }
    NNPSpotifyPublishLyrics(current, next, lines);
}

static void NNPSpotifyLyricsProbeEnsureCurrentTrackLyrics(void) {
    NSDictionary *nowPlaying = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo ?: @{};
    NSString *trackIdentifier = NNPSpotifyTrackIdentifierFromMetadata(nowPlaying);
    NSString *trackTitle = [nowPlaying[MPMediaItemPropertyTitle] isKindOfClass:NSString.class]
        ? nowPlaying[MPMediaItemPropertyTitle] : @"";
    NSString *trackArtist = [nowPlaying[MPMediaItemPropertyArtist] isKindOfClass:NSString.class]
        ? nowPlaying[MPMediaItemPropertyArtist] : @"";
    if (!trackIdentifier.length || !trackTitle.length) return;
    if ([trackIdentifier isEqualToString:NNPSpotifyVerifiedLyricsTrackIdentifier()]) return;

    NSURLSession *session = nil;
    NSURLRequest *template = nil;
    NSMutableURLRequest *lyricsRequest = nil;
    NSString *requestPath = nil;
    @synchronized (NNPSpotifyTrackContextLock) {
        session = NNPSpotifyLyricsRequestSession;
        template = NNPSpotifyLyricsRequestTemplate;
        if (!session || !template.URL) {
            static NSString *lastMissingTemplateTrack;
            if (![lastMissingTemplateTrack isEqualToString:trackIdentifier]) {
                lastMissingTemplateTrack = [trackIdentifier copy];
                NNPSpotifyProbeAppend([NSString stringWithFormat:@"LYRICS-PREFETCH waiting for Spotify request template track=%@", trackIdentifier]);
            }
            return;
        }

        NSURLComponents *components = [NSURLComponents componentsWithURL:template.URL resolvingAgainstBaseURL:NO];
        NSString *path = components.path ?: @"";
        NSString *marker = @"/color-lyrics/v2/track/";
        NSRange markerRange = [path rangeOfString:marker];
        if (markerRange.location == NSNotFound) return;
        components.path = [[path substringToIndex:NSMaxRange(markerRange)] stringByAppendingString:trackIdentifier];
        NSURL *targetURL = components.URL;
        if (!targetURL) return;
        requestPath = targetURL.path;

        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        NSDictionary *recentRequest = NNPSpotifyTrackContextByRequestPath[requestPath];
        if ([recentRequest[@"capturedAt"] respondsToSelector:@selector(doubleValue)] &&
            now - [recentRequest[@"capturedAt"] doubleValue] < 15.0) return;
        NSNumber *lastAttempt = NNPSpotifyLyricsFetchAttempts[trackIdentifier];
        if (lastAttempt && now - lastAttempt.doubleValue < 30.0) return;
        NNPSpotifyLyricsFetchAttempts[trackIdentifier] = @(now);
        for (NSString *key in NNPSpotifyLyricsFetchAttempts.allKeys.copy) {
            if (now - NNPSpotifyLyricsFetchAttempts[key].doubleValue > 300.0)
                [NNPSpotifyLyricsFetchAttempts removeObjectForKey:key];
        }

        lyricsRequest = [template mutableCopy];
        lyricsRequest.URL = targetURL;
        lyricsRequest.HTTPMethod = @"GET";
        lyricsRequest.HTTPBody = nil;
        [lyricsRequest setValue:nil forHTTPHeaderField:@"If-None-Match"];
        [lyricsRequest setValue:nil forHTTPHeaderField:@"If-Modified-Since"];
    }

    if (!lyricsRequest) return;
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"LYRICS-PREFETCH start id=%@ title=%@ artist=%@",
                           trackIdentifier, trackTitle, trackArtist]);
    NSURLSessionDataTask *task = [session dataTaskWithRequest:lyricsRequest completionHandler:^(__unused NSData *data,
                                                                                               NSURLResponse *response,
                                                                                               NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class]
            ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NNPSpotifyProbeAppend([NSString stringWithFormat:@"LYRICS-PREFETCH finished id=%@ status=%ld error=%@",
                               trackIdentifier, (long)status, error.localizedDescription ?: @""]);
    }];
    [task resume];
}

void NNPSpotifyLyricsProbeStart(void) {
    [NSUserDefaults.standardUserDefaults setObject:[NSDate date] forKey:@"NNPSpotifyLyricsProbeStartedAt"];
    [NSUserDefaults.standardUserDefaults setObject:@(getpid()) forKey:@"NNPSpotifyLyricsProbePID"];
    [NSUserDefaults.standardUserDefaults synchronize];
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"START pid=%d process=%@ bundle=%@", getpid(),
                           NSProcessInfo.processInfo.processName ?: @"?", NSBundle.mainBundle.bundleIdentifier ?: @"?"]);
    NNPSpotifyInitializeLyricsTrackAssociation();
    NNPSpotifyDumpLyricsRuntime();
    dispatch_async(dispatch_get_main_queue(), ^{
        NNPSpotifyLyricsProbeCapture();
        [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(__unused NSTimer *timer) {
            NNPSpotifyLyricsProbeCapture();
        }];
        [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(__unused NSTimer *timer) {
            NNPSpotifyLyricsProbeEnsureCurrentTrackLyrics();
        }];
    });
}
