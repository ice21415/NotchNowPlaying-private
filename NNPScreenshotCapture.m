#import "NNPScreenshotCapture.h"
#import "NNPDiagnostics.h"
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdint.h>
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

static NSDictionary *NNPScreenshotImageStats(UIImage *image) {
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return @{ @"available": @NO };

    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    size_t bitsPerPixel = CGImageGetBitsPerPixel(cgImage);
    size_t bytesPerRow = CGImageGetBytesPerRow(cgImage);
    size_t channels = bitsPerPixel / 8;
    if (!channels || !bytesPerRow || !width || !height) {
        return @{
            @"available": @YES,
            @"width": @(width),
            @"height": @(height),
            @"bitsPerPixel": @(bitsPerPixel),
            @"bytesPerRow": @(bytesPerRow),
        };
    }

    CFDataRef dataRef = CGDataProviderCopyData(CGImageGetDataProvider(cgImage));
    if (!dataRef) return @{ @"available": @YES, @"width": @(width), @"height": @(height), @"data": @NO };
    const UInt8 *bytes = CFDataGetBytePtr(dataRef);
    CFIndex dataLength = CFDataGetLength(dataRef);
    NSUInteger targetSamples = 4096;
    NSUInteger totalPixels = width > (SIZE_MAX / height) ? 0 : width * height;
    NSUInteger step = totalPixels > targetSamples ? (totalPixels / targetSamples) : 1;
    NSUInteger samples = 0;
    NSUInteger nonBlackSamples = 0;
    NSUInteger maxRGB = 0;
    for (NSUInteger pixel = 0; pixel < totalPixels && samples < targetSamples; pixel += step) {
        size_t x = pixel % width;
        size_t y = pixel / width;
        size_t offset = y * bytesPerRow + x * channels;
        if (offset >= (size_t)dataLength) break;
        size_t available = (size_t)dataLength - offset;
        size_t componentCount = channels < 3 ? channels : 3;
        if (available < componentCount) break;
        NSUInteger pixelMax = 0;
        for (size_t component = 0; component < componentCount; component++) {
            if (bytes[offset + component] > pixelMax) pixelMax = bytes[offset + component];
        }
        if (pixelMax) nonBlackSamples += 1;
        if (pixelMax > maxRGB) maxRGB = pixelMax;
        samples += 1;
    }
    CFRelease(dataRef);
    return @{
        @"available": @YES,
        @"data": @YES,
        @"width": @(width),
        @"height": @(height),
        @"bitsPerPixel": @(bitsPerPixel),
        @"bytesPerRow": @(bytesPerRow),
        @"samples": @(samples),
        @"nonBlackSamples": @(nonBlackSamples),
        @"maxRGB": @(maxRGB),
    };
}

static NSDictionary *NNPScreenshotScreenMetadata(UIScreen *screen) {
    if (!screen) return @{ @"available": @NO };
    return @{
        @"available": @YES,
        @"class": NSStringFromClass(screen.class),
        @"bounds": NSStringFromCGRect(screen.bounds),
        @"nativeBounds": NSStringFromCGRect(screen.nativeBounds),
        @"scale": @(screen.scale),
        @"nativeScale": @(screen.nativeScale),
        @"brightness": @(screen.brightness),
        @"captured": @(screen.isCaptured),
    };
}

static void NNPScreenshotWriteResult(BOOL captureSucceeded, NSString *error, UIImage *image, NSData *png, NSDictionary *captureDiagnostics) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"timestamp"] = [NSDate date];
        result[@"success"] = @(captureSucceeded);
        result[@"path"] = NNPScreenshotImagePath;
        if (error.length) result[@"error"] = error;
        if (captureDiagnostics) result[@"captureDiagnostics"] = captureDiagnostics;

        NSDictionary *prePNG = image ? NNPScreenshotImageStats(image) : nil;
        UIImage *decodedPNG = png.length ? [UIImage imageWithData:png] : nil;
        NSDictionary *postPNG = decodedPNG ? NNPScreenshotImageStats(decodedPNG) : nil;
        if (image) {
            result[@"width"] = @(image.size.width);
            result[@"height"] = @(image.size.height);
            result[@"scale"] = @(image.scale);
            if (prePNG) result[@"prePNGStats"] = prePNG;
        }
        if (postPNG) result[@"postPNGStats"] = postPNG;

        NSError *writeError = nil;
        BOOL directWrite = png.length && [png writeToFile:NNPScreenshotImagePath options:NSDataWritingAtomic error:&writeError];
        result[@"directPathWrite"] = @(directWrite);
        if (!directWrite && writeError.localizedDescription.length) result[@"directPathError"] = writeError.localizedDescription;
        if (png.length) {
            NNPDiagnosticSetValue(@"SSHScreenshotPNG", png);
            NNPDiagnosticLog(@"SCREENSHOT_CAPTURE diagnostic preference publication requested");
        }
        NNPDiagnosticSetValue(@"SSHScreenshotCaptureDiagnostics", @{
            @"capture": captureDiagnostics ?: @{},
            @"prePNG": prePNG ?: @{},
            @"postPNG": postPNG ?: @{},
            @"encodedBytes": @(png.length),
            @"directPathWrite": @(directWrite),
        });
        NNPDiagnosticSetValue(@"SSHScreenshotResult", result);
        [[NSFileManager defaultManager] createDirectoryAtPath:NNPDiagnosticDirectoryPath() withIntermediateDirectories:YES attributes:nil error:NULL];
        [result writeToFile:NNPScreenshotResultPath atomically:YES];
        NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE completed success=%@ bytes=%lu preMaxRGB=%@ postMaxRGB=%@ preNonBlack=%@ postNonBlack=%@ directPathWrite=%@", captureSucceeded ? @"YES" : @"NO", (unsigned long)png.length, prePNG[@"maxRGB"] ?: @"none", postPNG[@"maxRGB"] ?: @"none", prePNG[@"nonBlackSamples"] ?: @"none", postPNG[@"nonBlackSamples"] ?: @"none", directWrite ? @"YES" : @"NO"]);
    });
}

static void NNPScreenshotCaptureOne(void) {
    NSDate *captureStart = [NSDate date];
    UIScreen *screen = UIScreen.mainScreen;
    NSDictionary *screenMetadata = NNPScreenshotScreenMetadata(screen);
    NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE capture begin provider=_SBMainScreenScreenshotProvider screen=%@ bounds=%@ nativeBounds=%@ scale=%@ nativeScale=%@ brightness=%@ captured=%@", screenMetadata[@"class"] ?: @"none", screenMetadata[@"bounds"] ?: @"none", screenMetadata[@"nativeBounds"] ?: @"none", screenMetadata[@"scale"] ?: @"none", screenMetadata[@"nativeScale"] ?: @"none", screenMetadata[@"brightness"] ?: @"none", screenMetadata[@"captured"] ?: @"none"]);

    Class providerClass = NSClassFromString(@"_SBMainScreenScreenshotProvider");
    SEL initSelector = NSSelectorFromString(@"initWithScreen:");
    SEL captureSelector = NSSelectorFromString(@"captureScreenshot");
    if (!providerClass || !class_getInstanceMethod(providerClass, initSelector) || !class_getInstanceMethod(providerClass, captureSelector)) {
        NSString *error = @"_SBMainScreenScreenshotProvider or selector unavailable";
        NNPScreenshotWriteResult(NO, error, nil, nil, @{
            @"startTimestamp": captureStart,
            @"screen": screenMetadata ?: @{},
        });
        NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE failed error=%@", error]);
        return;
    }

    id provider = ((id (*)(id, SEL, id))objc_msgSend)([providerClass alloc], initSelector, screen);
    UIImage *image = provider ? ((id (*)(id, SEL))objc_msgSend)(provider, captureSelector) : nil;
    NSDate *captureComplete = [NSDate date];
    NSDictionary *captureDiagnostics = @{
        @"startTimestamp": captureStart,
        @"completeTimestamp": captureComplete,
        @"screen": screenMetadata ?: @{},
        @"providerClass": provider ? NSStringFromClass([provider class]) : @"nil",
        @"imageClass": image ? NSStringFromClass([image class]) : @"nil",
        @"imageSize": image ? NSStringFromCGSize(image.size) : @"none",
        @"imageScale": image ? @(image.scale) : @0,
        @"cgImageAvailable": @(image.CGImage != NULL),
        @"cgImageWidth": image.CGImage ? @(CGImageGetWidth(image.CGImage)) : @0,
        @"cgImageHeight": image.CGImage ? @(CGImageGetHeight(image.CGImage)) : @0,
    };
    NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE capture complete provider=%@ image=%@ size=%@ scale=%@ cgImage=%@ cgSize=%@x%@", captureDiagnostics[@"providerClass"], captureDiagnostics[@"imageClass"], captureDiagnostics[@"imageSize"], captureDiagnostics[@"imageScale"], captureDiagnostics[@"cgImageAvailable"], captureDiagnostics[@"cgImageWidth"], captureDiagnostics[@"cgImageHeight"]]);
    if (![image isKindOfClass:UIImage.class]) {
        NSString *error = @"captureScreenshot returned no UIImage";
        NNPScreenshotWriteResult(NO, error, nil, nil, captureDiagnostics);
        NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE failed error=%@", error]);
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSData *png = UIImagePNGRepresentation(image);
        NNPScreenshotWriteResult(png.length > 0, png.length ? nil : @"PNG encoding returned no data", image, png, captureDiagnostics);
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
    // Refresh only on the helper's background queue; this code is never run
    // from a display or lock transition hook.
    if (gNNPScreenshotPollCount % 4 == 0) CFPreferencesAppSynchronize(NNPScreenshotPreferenceDomain);
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
