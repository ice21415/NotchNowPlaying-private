#import "NNPRecorder.h"
#import "NNPDiagnostics.h"
#import <UIKit/UIKit.h>

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
        static NSMutableArray<NSString *> *lines;
        static BOOL flushScheduled;
        if (!lines) lines = [NSMutableArray array];
        NSDateFormatter *unused = nil; (void)unused;
        [lines addObject:[NSString stringWithFormat:@"%.3f %@", now, message]];
        while (lines.count > 400) [lines removeObjectAtIndex:0];
        if (flushScheduled) return;
        flushScheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), NNPRecorderQueue(), ^{
            flushScheduled = NO;
            NNPDiagnosticSetString(@"RecorderLog", [lines componentsJoinedByString:@"\n"]);
        });
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
