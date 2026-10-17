#import "NNPRecorder.h"
#import <UIKit/UIKit.h>

static NSString *const NNPRecorderPath = @"/var/mobile/Library/Caches/nnp-recorder.log";
static dispatch_queue_t NNPRecorderQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.user.notchnowplaying.recorder", DISPATCH_QUEUE_SERIAL); });
    return queue;
}
BOOL NNPRecorderEnabled(void) {
    static BOOL enabled;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id flag = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("ResearchRecorder"), CFSTR("com.user.notchnowplaying")));
        enabled = [flag respondsToSelector:@selector(boolValue)] && [flag boolValue];
    });
    return enabled;
}
void NNPRecorderLog(NSString *message) {
    if (!NNPRecorderEnabled()) return;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    dispatch_async(NNPRecorderQueue(), ^{
        static FILE *file;
        if (!file) file = fopen(NNPRecorderPath.fileSystemRepresentation, "a");
        if (!file) return;
        long size = ftell(file);
        if (size > 2 * 1024 * 1024) { freopen(NNPRecorderPath.fileSystemRepresentation, "w", file); }
        fprintf(file, "%.3f %s\n", now, message.UTF8String);
        fflush(file);
    });
}
void NNPRecorderStart(NSString *(^snapshot)(void)) {
    if (!NNPRecorderEnabled()) return;
    NNPRecorderLog(@"=== recorder started ===");
    static NSString *last;
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(__unused NSTimer *t) {
        NSString *text = snapshot();
        if (text && ![text isEqualToString:last]) { last = [text copy]; NNPRecorderLog([@"SNAP " stringByAppendingString:text]); }
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}
