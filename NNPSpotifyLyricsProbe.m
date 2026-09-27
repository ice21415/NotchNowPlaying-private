#import "NNPSpotifyLyricsProbe.h"
#import <objc/runtime.h>
#import <fcntl.h>
#import <stdlib.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString * const NNPSpotifyLyricsProbePath = @"/var/mobile/Library/NotchNowPlaying/spotify-lyrics-runtime.log";

static void NNPSpotifyProbeAppend(NSString *line) {
    if (!line.length) return;
    NSString *entry = [line stringByAppendingString:@"\n"];
    NSString *directory = NNPSpotifyLyricsProbePath.stringByDeletingLastPathComponent;
    mkdir(directory.UTF8String, 0755);
    int fd = open(NNPSpotifyLyricsProbePath.UTF8String, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
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

static NSString *NNPSpotifyProbeMethods(Class cls) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int index = 0; index < count; index++) {
        SEL selector = method_getName(methods[index]);
        const char *name = selector ? sel_getName(selector) : NULL;
        if (name) [names addObject:[NSString stringWithUTF8String:name]];
    }
    free(methods);
    [names sortUsingSelector:@selector(compare:)];
    return [names componentsJoinedByString:@","];
}

static NSString *NNPSpotifyProbeProperties(Class cls) {
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &count);
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int index = 0; index < count; index++) {
        const char *name = property_getName(properties[index]);
        if (name) [names addObject:[NSString stringWithUTF8String:name]];
    }
    free(properties);
    [names sortUsingSelector:@selector(compare:)];
    return [names componentsJoinedByString:@","];
}

static void NNPSpotifyLyricsProbeScan(NSUInteger pass) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) {
        NNPSpotifyProbeAppend([NSString stringWithFormat:@"pass=%lu class_count=0", (unsigned long)pass]);
        return;
    }
    Class *classes = (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
    int actualCount = objc_getClassList(classes, count);
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"pass=%lu timestamp=%@ class_count=%d", (unsigned long)pass, [NSDate date], actualCount]);
    NSUInteger matched = 0;
    for (int index = 0; index < actualCount; index++) {
        Class cls = classes[index];
        const char *rawName = class_getName(cls);
        if (!rawName) continue;
        NSString *name = [NSString stringWithUTF8String:rawName];
        if ([name rangeOfString:@"lyric" options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        matched++;
        const char *image = class_getImageName(cls);
        Class meta = object_getClass(cls);
        NNPSpotifyProbeAppend([NSString stringWithFormat:@"CLASS %@ image=%@ properties=[%@] methods=[%@] classMethods=[%@]", name,
                               image ? [NSString stringWithUTF8String:image] : @"?",
                               NNPSpotifyProbeProperties(cls), NNPSpotifyProbeMethods(cls),
                               meta ? NNPSpotifyProbeMethods(meta) : @""]);
    }
    free(classes);
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"pass=%lu matched_classes=%lu", (unsigned long)pass, (unsigned long)matched]);
}

void NNPSpotifyLyricsProbeStart(void) {
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"START pid=%d process=%@ bundle=%@", getpid(), NSProcessInfo.processInfo.processName ?: @"?", NSBundle.mainBundle.bundleIdentifier ?: @"?"]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NNPSpotifyLyricsProbeScan(1);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NNPSpotifyLyricsProbeScan(2);
    });
}
