#import "NNPScreenshotCapture.h"
#import "NNPDiagnostics.h"
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString * const NNPScreenshotRequestPath = @"/var/mobile/Library/NotchNowPlaying/ssh-screenshot-request";
static NSString * const NNPScreenshotPreferencesRequestPath = @"/var/mobile/Library/Preferences/com.user.notchnowplaying.ssh-screenshot-request";
static CFStringRef const NNPScreenshotRequestPreference = CFSTR("SSHScreenshotRequest");
static CFStringRef const NNPScreenshotPreferenceDomain = CFSTR("com.user.notchnowplaying");
static NSString * const NNPScreenshotImagePath = @"/var/mobile/Library/NotchNowPlaying/ssh-screenshot.png";
static NSString * const NNPScreenshotResultPath = @"/var/mobile/Library/NotchNowPlaying/ssh-screenshot-result.plist";
static BOOL gNNPScreenshotCaptureRunning;
static NSUInteger gNNPScreenshotPollCount;

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

static void NNPScreenshotPoll(void) {
    if (!gNNPScreenshotCaptureRunning) return;
    gNNPScreenshotPollCount += 1;
    NSError *removeError = nil;
    NSString *requestPath = nil;
    for (NSString *candidate in @[NNPScreenshotRequestPath, NNPScreenshotPreferencesRequestPath]) {
        if (access(candidate.UTF8String, F_OK) == 0) {
            requestPath = candidate;
            break;
        }
    }
    id preferenceRequest = CFBridgingRelease(CFPreferencesCopyAppValue(NNPScreenshotRequestPreference, NNPScreenshotPreferenceDomain));
    if ([preferenceRequest respondsToSelector:@selector(boolValue)] && [preferenceRequest boolValue]) {
        CFPreferencesSetAppValue(NNPScreenshotRequestPreference, kCFBooleanFalse, NNPScreenshotPreferenceDomain);
        CFPreferencesAppSynchronize(NNPScreenshotPreferenceDomain);
        requestPath = @"preference:SSHScreenshotRequest";
    }
    if (gNNPScreenshotPollCount % 20 == 0) {
        NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE poll count=%lu request=%@ pathVisible=%@ preference=%@", (unsigned long)gNNPScreenshotPollCount, requestPath ?: @"none", requestPath && ![requestPath hasPrefix:@"preference:"] ? @"YES" : @"NO", preferenceRequest ?: @"none"]);
    }
    if (requestPath.length) {
        BOOL removed = [requestPath hasPrefix:@"preference:"] || [[NSFileManager defaultManager] removeItemAtPath:requestPath error:&removeError];
        if (!removed) {
            NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE request removal failed error=%@", removeError.localizedDescription ?: @"unknown"]);
        } else {
            NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE request accepted path=%@; no wake or unlock requested", requestPath]);
            dispatch_async(dispatch_get_main_queue(), ^{
                NNPScreenshotCaptureOne();
            });
            return;
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NNPScreenshotPoll();
    });
}

void NNPScreenshotCaptureStart(void) {
    if (gNNPScreenshotCaptureRunning) return;
    gNNPScreenshotCaptureRunning = YES;
    NNPDiagnosticLog(@"SCREENSHOT_CAPTURE helper armed requestPaths=NotchNowPlaying/ssh-screenshot-request,Preferences/com.user.notchnowplaying.ssh-screenshot-request");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NNPDiagnosticLog(@"SCREENSHOT_CAPTURE poll worker started");
        NNPScreenshotPoll();
    });
}
