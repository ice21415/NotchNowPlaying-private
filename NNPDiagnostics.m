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

NSString *NNPDiagnosticDirectoryPath(void) { return NNPDiagDirectory; }
NSString *NNPDiagnosticLogPath(void) { return NNPDiagLog; }
NSString *NNPDiagnosticArmPath(void) { return NNPDiagArm; }

void NNPDiagnosticLog(NSString *event) {
    if (!event.length) return;
    mkdir(NNPDiagDirectory.UTF8String, 0755);
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"[%@] pid=%d process=%@ %@\n", [formatter stringFromDate:[NSDate date]], getpid(), NSProcessInfo.processInfo.processName ?: @"unknown", event];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    for (NSString *path in @[NNPDiagLog, NNPDiagFallbackLog]) {
        int fd = open(path.UTF8String, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd < 0) continue;
        write(fd, data.bytes, data.length);
        close(fd);
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
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, NNPDiagDomain);
    CFPreferencesAppSynchronize(NNPDiagDomain);
}

id NNPDiagnosticCopyValue(NSString *key) {
    if (!key.length) return nil;
    CFPreferencesAppSynchronize(NNPDiagDomain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, NNPDiagDomain));
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
    NSArray *existing = NNPDiagnosticCopyValue(@"BlankingObserverEvents");
    NSMutableArray *events = existing.count ? [existing mutableCopy] : [NSMutableArray array];
    [events addObject:event];
    if (events.count > 64) [events removeObjectsInRange:NSMakeRange(0, events.count - 64)];
    NNPDiagnosticSetValue(@"BlankingObserverEvents", events);
}

BOOL NNPDiagnosticArmExists(BOOL *readable) {
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:NNPDiagArm];
    if (readable) *readable = exists && access(NNPDiagArm.UTF8String, R_OK) == 0;
    return exists;
}

BOOL NNPDiagnosticConsumeArm(void) {
    return [[NSFileManager defaultManager] removeItemAtPath:NNPDiagArm error:NULL];
}
