#import "NNPScreenshotCapture.h"
#import "NNPDiagnostics.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString * const NNPScreenshotRequestPath = @"/var/mobile/Library/NotchNowPlaying/ssh-screenshot-request";
static NSString * const NNPScreenshotImagePath = @"/var/mobile/Library/NotchNowPlaying/ssh-screenshot.png";
static NSString * const NNPScreenshotResultPath = @"/var/mobile/Library/NotchNowPlaying/ssh-screenshot-result.plist";
static BOOL gNNPScreenshotCaptureRunning;
static dispatch_source_t gNNPScreenshotPollTimer;

static void NNPScreenshotWriteResult(BOOL success, NSString *error, UIImage *image) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"timestamp"] = [NSDate date];
    result[@"success"] = @(success);
    result[@"path"] = NNPScreenshotImagePath;
    if (error.length) result[@"error"] = error;
    if (image) {
        result[@"width"] = @(image.size.width);
        result[@"height"] = @(image.size.height);
        result[@"scale"] = @(image.scale);
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:NNPDiagnosticDirectoryPath() withIntermediateDirectories:YES attributes:nil error:NULL];
    [result writeToFile:NNPScreenshotResultPath atomically:YES];
}

static void NNPScreenshotCaptureOne(void) {
    NNPDiagnosticLog(@"SCREENSHOT_CAPTURE request accepted; no wake or unlock requested");

    Class providerClass = NSClassFromString(@"_SBMainScreenScreenshotProvider");
    SEL initSelector = NSSelectorFromString(@"initWithScreen:");
    SEL captureSelector = NSSelectorFromString(@"captureScreenshot");
    if (!providerClass || !class_getInstanceMethod(providerClass, initSelector) || !class_getInstanceMethod(providerClass, captureSelector)) {
        NSString *error = @"_SBMainScreenScreenshotProvider or selector unavailable";
        NNPScreenshotWriteResult(NO, error, nil);
        NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE failed error=%@", error]);
        return;
    }

    id provider = ((id (*)(id, SEL, id))objc_msgSend)([providerClass alloc], initSelector, UIScreen.mainScreen);
    UIImage *image = provider ? ((id (*)(id, SEL))objc_msgSend)(provider, captureSelector) : nil;
    if (![image isKindOfClass:UIImage.class]) {
        NSString *error = @"captureScreenshot returned no UIImage";
        NNPScreenshotWriteResult(NO, error, nil);
        NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE failed error=%@", error]);
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSData *png = UIImagePNGRepresentation(image);
        NSError *writeError = nil;
        BOOL wrote = png.length && [png writeToFile:NNPScreenshotImagePath options:NSDataWritingAtomic error:&writeError];
        NNPScreenshotWriteResult(wrote, wrote ? nil : (writeError.localizedDescription ?: @"PNG write failed"), image);
        NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE completed success=%@ bytes=%lu width=%.0f height=%.0f", wrote ? @"YES" : @"NO", (unsigned long)png.length, image.size.width, image.size.height]);
    });
}

void NNPScreenshotCaptureStart(void) {
    if (gNNPScreenshotCaptureRunning) return;
    gNNPScreenshotCaptureRunning = YES;
    NNPDiagnosticLog(@"SCREENSHOT_CAPTURE helper armed requestPath=/var/mobile/Library/NotchNowPlaying/ssh-screenshot-request");
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    gNNPScreenshotPollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(gNNPScreenshotPollTimer, dispatch_time(DISPATCH_TIME_NOW, 0), (uint64_t)(0.25 * NSEC_PER_SEC), (uint64_t)(0.05 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(gNNPScreenshotPollTimer, ^{
        NSError *removeError = nil;
        BOOL requestExists = [[NSFileManager defaultManager] fileExistsAtPath:NNPScreenshotRequestPath];
        if (!requestExists) return;
        BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:NNPScreenshotRequestPath error:&removeError];
        if (!removed) {
            NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE request removal failed error=%@", removeError.localizedDescription ?: @"unknown"]);
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NNPScreenshotCaptureOne();
        });
    });
    dispatch_resume(gNNPScreenshotPollTimer);
}
