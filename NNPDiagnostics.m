#import "NNPDiagnostics.h"
#import <CoreFoundation/CoreFoundation.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString * const NNPDiagDirectory = @"/var/mobile/Library/NotchNowPlaying";
static NSString * const NNPDiagLog = @"/var/mobile/Library/NotchNowPlaying/load-path-diagnostic.log";
static NSString * const NNPDiagFallbackLog = @"/var/mobile/Library/Logs/NotchNowPlaying-load-path-diagnostic.log";
static NSString * const NNPDiagArm = @"/var/mobile/Library/NotchNowPlaying/display-assertion-arm";
static CFStringRef const NNPDiagDomain = CFSTR("com.user.notchnowplaying.diagnostics");
static NSUInteger NNPDiagnosticTransitionSequence = 0;
static NSString *NNPDiagnosticCurrentTransition;
static dispatch_queue_t NNPDiagnosticWriteQueue;
static NSObject *NNPDiagnosticWriteLock;
static NSMutableArray *NNPDiagnosticPendingLogEntries;
static BOOL NNPDiagnosticFlushScheduled;

static void NNPDiagnosticEnsureWriteQueue(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NNPDiagnosticWriteQueue = dispatch_queue_create("com.user.notchnowplaying.diagnostics.write", DISPATCH_QUEUE_SERIAL);
        NNPDiagnosticWriteLock = [NSObject new];
        NNPDiagnosticPendingLogEntries = [NSMutableArray array];
    });
}

static void NNPDiagnosticSetValueSynchronously(NSString *key, id value) {
    if (!key.length || !value) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, NNPDiagDomain);
    CFPreferencesAppSynchronize(NNPDiagDomain);
}

static id NNPDiagnosticCopyValueSynchronously(NSString *key) {
    if (!key.length) return nil;
    CFPreferencesAppSynchronize(NNPDiagDomain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, NNPDiagDomain));
}

static void NNPDiagnosticFlushPendingLogEntries(void);

static void NNPDiagnosticScheduleFlush(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), NNPDiagnosticWriteQueue, ^{
        NNPDiagnosticFlushPendingLogEntries();
    });
}

static void NNPDiagnosticFlushPendingLogEntries(void) {
    NNPDiagnosticEnsureWriteQueue();
    NSArray *entries = nil;
    @synchronized (NNPDiagnosticWriteLock) {
        if (NNPDiagnosticPendingLogEntries.count) {
            entries = [NNPDiagnosticPendingLogEntries copy];
            [NNPDiagnosticPendingLogEntries removeAllObjects];
        }
    }

    if (entries.count) {
        mkdir(NNPDiagDirectory.UTF8String, 0755);
        NSMutableString *lines = [NSMutableString string];
        for (NSDictionary *entry in entries) {
            NSDate *timestamp = entry[@"timestamp"];
            NSString *line = [NSString stringWithFormat:@"[%@] pid=%@ process=%@ %@\n", timestamp ?: [NSDate date], entry[@"pid"] ?: @0, entry[@"process"] ?: @"unknown", entry[@"event"] ?: @"event"];
            [lines appendString:line];
        }
        NSData *data = [lines dataUsingEncoding:NSUTF8StringEncoding];
        for (NSString *path in @[NNPDiagLog, NNPDiagFallbackLog]) {
            int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_APPEND, 0644);
            if (fd < 0) continue;
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

        NSArray *existing = NNPDiagnosticCopyValueSynchronously(@"DiagnosticLogEvents");
        NSMutableArray *allEvents = existing.count ? [existing mutableCopy] : [NSMutableArray array];
        [allEvents addObjectsFromArray:entries];
        if (allEvents.count > 256) [allEvents removeObjectsInRange:NSMakeRange(0, allEvents.count - 256)];
        NNPDiagnosticSetValueSynchronously(@"DiagnosticLogEvents", allEvents);
    }

    BOOL scheduleAgain = NO;
    @synchronized (NNPDiagnosticWriteLock) {
        scheduleAgain = NNPDiagnosticPendingLogEntries.count > 0;
        if (!scheduleAgain) NNPDiagnosticFlushScheduled = NO;
    }
    if (scheduleAgain) NNPDiagnosticScheduleFlush();
}

NSString *NNPDiagnosticDirectoryPath(void) { return NNPDiagDirectory; }
NSString *NNPDiagnosticLogPath(void) { return NNPDiagLog; }
NSString *NNPDiagnosticArmPath(void) { return NNPDiagArm; }

void NNPDiagnosticLog(NSString *event) {
    if (!event.length) return;
    NNPDiagnosticEnsureWriteQueue();
    NSDictionary *entry = @{
        @"timestamp": [NSDate date],
        @"pid": @(getpid()),
        @"process": NSProcessInfo.processInfo.processName ?: @"unknown",
        @"event": event,
    };
    BOOL schedule = NO;
    @synchronized (NNPDiagnosticWriteLock) {
        if (NNPDiagnosticPendingLogEntries.count < 256) {
            [NNPDiagnosticPendingLogEntries addObject:entry];
        } else {
            [NNPDiagnosticPendingLogEntries removeObjectAtIndex:0];
            [NNPDiagnosticPendingLogEntries addObject:entry];
        }
        if (!NNPDiagnosticFlushScheduled) {
            NNPDiagnosticFlushScheduled = YES;
            schedule = YES;
        }
    }
    if (schedule) NNPDiagnosticScheduleFlush();
}

NSString *NNPDiagnosticBeginTransition(NSString *reason) {
    @synchronized ([NSProcessInfo processInfo]) {
        NNPDiagnosticTransitionSequence += 1;
        NNPDiagnosticCurrentTransition = [NSString stringWithFormat:@"T%lu", (unsigned long)NNPDiagnosticTransitionSequence];
        NSString *identifier = NNPDiagnosticCurrentTransition;
        NNPDiagnosticLog([NSString stringWithFormat:@"transition=%@ begin reason=%@", identifier, reason ?: @"unknown"]);
        return identifier;
    }
}

void NNPDiagnosticLogTransition(NSString *event) {
    @synchronized ([NSProcessInfo processInfo]) {
        NNPDiagnosticLog([NSString stringWithFormat:@"transition=%@ %@", NNPDiagnosticCurrentTransition ?: @"none", event ?: @"event"]);
    }
}

void NNPDiagnosticRecordStartup(NSString *detail) {
    if (!detail.length) detail = @"TWEAK_LOADED";
    NNPDiagnosticSetBool(@"TweakLoaded", YES);
    NNPDiagnosticSetInteger(@"SpringBoardPID", getpid());
    NNPDiagnosticSetString(@"StartupTimestamp", [[NSDate date] description]);
    NNPDiagnosticSetString(@"TWEAK_LOADED", detail);
}

void NNPDiagnosticSetValue(NSString *key, id value) {
    if (!key.length || !value) return;
    NNPDiagnosticEnsureWriteQueue();
    NSString *copiedKey = [key copy];
    id copiedValue = [value copy];
    dispatch_async(NNPDiagnosticWriteQueue, ^{
        NNPDiagnosticSetValueSynchronously(copiedKey, copiedValue);
    });
}

id NNPDiagnosticCopyValue(NSString *key) {
    return NNPDiagnosticCopyValueSynchronously(key);
}

void NNPDiagnosticSetBool(NSString *key, BOOL value) {
    NNPDiagnosticSetValue(key, @(value));
}

void NNPDiagnosticSetInteger(NSString *key, NSInteger value) {
    NNPDiagnosticSetValue(key, @(value));
}

void NNPDiagnosticSetString(NSString *key, NSString *value) {
    if (value.length) NNPDiagnosticSetValue(key, value);
}

void NNPDiagnosticAppendEvent(NSDictionary *event) {
    if (![event isKindOfClass:NSDictionary.class]) return;
    NNPDiagnosticEnsureWriteQueue();
    NSDictionary *copiedEvent = [event copy];
    dispatch_async(NNPDiagnosticWriteQueue, ^{
        NSArray *existing = NNPDiagnosticCopyValueSynchronously(@"BlankingObserverEvents");
        NSMutableArray *events = existing.count ? [existing mutableCopy] : [NSMutableArray array];
        [events addObject:copiedEvent];
        if (events.count > 64) [events removeObjectsInRange:NSMakeRange(0, events.count - 64)];
        NNPDiagnosticSetValueSynchronously(@"BlankingObserverEvents", events);
    });
}

BOOL NNPDiagnosticArmExists(BOOL *readable) {
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:NNPDiagArm];
    if (readable) *readable = exists && access(NNPDiagArm.UTF8String, R_OK) == 0;
    return exists;
}

BOOL NNPDiagnosticConsumeArm(void) {
    return [[NSFileManager defaultManager] removeItemAtPath:NNPDiagArm error:NULL];
}
