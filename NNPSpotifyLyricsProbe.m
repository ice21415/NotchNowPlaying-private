#import "NNPSpotifyLyricsProbe.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import <fcntl.h>
#import <stdlib.h>
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
                if (ivarName) [ivars addObject:[NSString stringWithFormat:@"%s:%s", ivarName, type ?: "?"]];
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
        NNPSpotifyProbeAppend([NSString stringWithFormat:@"RUNTIME rows=%@ source=%@ current=%@ next=%@",
                               [rowDetails componentsJoinedByString:@" | "],
                               synchronizedRow ? synchronizedRow[@"lyricsSurface"] : @"screen-center-fallback",
                               current, next]);
    }
    NNPSpotifyPublishLyrics(current, next, lines);
}

void NNPSpotifyLyricsProbeStart(void) {
    [NSUserDefaults.standardUserDefaults setObject:[NSDate date] forKey:@"NNPSpotifyLyricsProbeStartedAt"];
    [NSUserDefaults.standardUserDefaults setObject:@(getpid()) forKey:@"NNPSpotifyLyricsProbePID"];
    [NSUserDefaults.standardUserDefaults synchronize];
    NNPSpotifyProbeAppend([NSString stringWithFormat:@"START pid=%d process=%@ bundle=%@", getpid(),
                           NSProcessInfo.processInfo.processName ?: @"?", NSBundle.mainBundle.bundleIdentifier ?: @"?"]);
    NNPSpotifyDumpLyricsRuntime();
    dispatch_async(dispatch_get_main_queue(), ^{
        NNPSpotifyLyricsProbeCapture();
        [NSTimer scheduledTimerWithTimeInterval:0.8 repeats:YES block:^(__unused NSTimer *timer) {
            NNPSpotifyLyricsProbeCapture();
        }];
    });
}
