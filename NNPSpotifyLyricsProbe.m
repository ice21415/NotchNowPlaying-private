#import "NNPSpotifyLyricsProbe.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <fcntl.h>
#import <stdlib.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString *NNPSpotifyLyricsProbePath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"nnp-spotify-lyrics-runtime.log"];
}
static NSMutableString *NNPSpotifyLyricsProbeBuffer;

static void NNPSpotifyProbePersistSnapshot(void) {
    NSString *snapshot = [NNPSpotifyLyricsProbeBuffer copy] ?: @"";
    [NSUserDefaults.standardUserDefaults setObject:snapshot forKey:@"NNPSpotifyLyricsProbeSnapshot"];
    [NSUserDefaults.standardUserDefaults synchronize];
}

static void NNPSpotifyProbeAppend(NSString *line) {
    if (!line.length) return;
    NSString *entry = [line stringByAppendingString:@"\n"];
    if (!NNPSpotifyLyricsProbeBuffer) NNPSpotifyLyricsProbeBuffer = [NSMutableString string];
    [NNPSpotifyLyricsProbeBuffer appendString:entry];
    NSString *path = NNPSpotifyLyricsProbePath();
    int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_APPEND, 0644);
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
    NNPSpotifyProbePersistSnapshot();
}

static void NNPSpotifyLyricsProbeDumpView(UIView *view, NSUInteger depth, NSUInteger *logged) {
    if (!view || depth > 40 || *logged >= 500) return;
    if (view.hidden || view.alpha < 0.01 || view.bounds.size.width < 1 || view.bounds.size.height < 1) return;

    NSMutableArray<NSString *> *values = [NSMutableArray array];
    if (view.accessibilityLabel.length) [values addObject:[NSString stringWithFormat:@"a11y=%@", view.accessibilityLabel]];
    if (view.accessibilityValue.length) [values addObject:[NSString stringWithFormat:@"value=%@", view.accessibilityValue]];
    if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length)
        [values addObject:[NSString stringWithFormat:@"text=%@", ((UILabel *)view).text]];
    if ([view isKindOfClass:UITextView.class] && ((UITextView *)view).text.length)
        [values addObject:[NSString stringWithFormat:@"text=%@", ((UITextView *)view).text]];
    if ([view isKindOfClass:UIButton.class]) {
        NSString *title = [(UIButton *)view titleForState:UIControlStateNormal];
        if (title.length) [values addObject:[NSString stringWithFormat:@"title=%@", title]];
    }
    if (values.count) {
        NNPSpotifyProbeAppend([NSString stringWithFormat:@"VIEW depth=%lu class=%@ frame=%@ %@", (unsigned long)depth,
                               NSStringFromClass(view.class) ?: @"?", NSStringFromCGRect(view.frame), [values componentsJoinedByString:@" "]]);
        (*logged)++;
    }
    for (UIView *child in view.subviews) NNPSpotifyLyricsProbeDumpView(child, depth + 1, logged);
}

static void NNPSpotifyLyricsProbeDumpVisibleText(NSUInteger pass) {
    NSUInteger logged = 0;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha < 0.01) continue;
            NNPSpotifyProbeAppend([NSString stringWithFormat:@"VIEWTREE pass=%lu window=%@ key=%d", (unsigned long)pass,
                                   NSStringFromClass(window.class), window.isKeyWindow]);
            NNPSpotifyLyricsProbeDumpView(window, 0, &logged);
        }
    }
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"VIEWTREE_END pass=%lu text_nodes=%lu", (unsigned long)pass, (unsigned long)logged]);
    NNPSpotifyProbePersistSnapshot();
}

void NNPSpotifyLyricsProbeStart(void) {
    [NSUserDefaults.standardUserDefaults setObject:[NSDate date] forKey:@"NNPSpotifyLyricsProbeStartedAt"];
    [NSUserDefaults.standardUserDefaults setObject:@(getpid()) forKey:@"NNPSpotifyLyricsProbePID"];
    [NSUserDefaults.standardUserDefaults synchronize];
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"START pid=%d process=%@ bundle=%@", getpid(), NSProcessInfo.processInfo.processName ?: @"?", NSBundle.mainBundle.bundleIdentifier ?: @"?"]);
    NNPSpotifyProbePersistSnapshot();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NNPSpotifyLyricsProbeScan(1);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NNPSpotifyLyricsProbeScan(2);
    });
    for (NSUInteger pass = 1; pass <= 4; pass++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((10.0 + 5.0 * (pass - 1)) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NNPSpotifyLyricsProbeDumpVisibleText(pass);
        });
    }
}
