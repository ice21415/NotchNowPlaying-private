#import "NNPDiagnostics.h"
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString * const NNPDiagDirectory = @"/var/mobile/Library/NotchNowPlaying";
static NSString * const NNPDiagLog = @"/var/mobile/Library/NotchNowPlaying/load-path-diagnostic.log";
static NSString * const NNPDiagFallbackLog = @"/var/mobile/Library/Logs/NotchNowPlaying-load-path-diagnostic.log";
static NSString * const NNPDiagArm = @"/var/mobile/Library/NotchNowPlaying/display-assertion-arm";

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

BOOL NNPDiagnosticArmExists(BOOL *readable) {
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:NNPDiagArm];
    if (readable) *readable = exists && access(NNPDiagArm.UTF8String, R_OK) == 0;
    return exists;
}

BOOL NNPDiagnosticConsumeArm(void) {
    return [[NSFileManager defaultManager] removeItemAtPath:NNPDiagArm error:NULL];
}
