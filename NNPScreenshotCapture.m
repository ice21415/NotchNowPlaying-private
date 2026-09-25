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
static CFStringRef const NNPScreenshotRequestIDPreference = CFSTR("SSHScreenshotRequestID");
static CFStringRef const NNPScreenshotPreferenceDomain = CFSTR("com.user.notchnowplaying");
static NSString * const NNPScreenshotImagePathBase = @"/var/mobile/Library/NotchNowPlaying/ssh-screenshot";
static NSString * const NNPScreenshotSSHPathBase = @"/tmp/notchnowplaying-ssh-screenshot";
static NSString * const NNPScreenshotResultPath = @"/var/mobile/Library/NotchNowPlaying/ssh-screenshot-result.plist";
static const NSUInteger NNPScreenshotPreferenceMaxBytes = 1024 * 1024;
static const NSUInteger NNPScreenshotPreviewMaxBytes = 512 * 1024;
static BOOL gNNPScreenshotCaptureRunning;
static NSUInteger gNNPScreenshotPollCount;

static NSString *NNPScreenshotSafeRequestID(NSString *requestID) {
    NSMutableString *safe = [NSMutableString string];
    for (NSUInteger index = 0; index < requestID.length; index++) {
        unichar character = [requestID characterAtIndex:index];
        if ((character >= 'a' && character <= 'z') ||
            (character >= 'A' && character <= 'Z') ||
            (character >= '0' && character <= '9') ||
            character == '-' || character == '_') {
            [safe appendFormat:@"%C", character];
        }
    }
    return safe.length ? safe : @"legacy";
}

static NSString *NNPScreenshotArtifactPath(NSString *base, NSString *requestID) {
    return [NSString stringWithFormat:@"%@-%@.png", base, NNPScreenshotSafeRequestID(requestID)];
}

static NSDictionary *NNPScreenshotImageStats(UIImage *image) {
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return @{ @"available": @NO };

    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    if (!width || !height) {
        return @{
            @"available": @YES,
            @"width": @(width),
            @"height": @(height),
        };
    }

    size_t sampleWidth = 64;
    size_t sampleHeight = 64;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
    CGContextRef context = CGBitmapContextCreate(NULL, sampleWidth, sampleHeight, 8, sampleWidth * 4, colorSpace, bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    if (!context) return @{ @"available": @YES, @"width": @(width), @"height": @(height), @"data": @NO };
    CGContextDrawImage(context, CGRectMake(0, 0, sampleWidth, sampleHeight), cgImage);
    const UInt8 *bytes = CGBitmapContextGetData(context);
    size_t bytesPerRow = CGBitmapContextGetBytesPerRow(context);
    if (!bytes) {
        CGContextRelease(context);
        return @{ @"available": @YES, @"width": @(width), @"height": @(height), @"data": @NO };
    }
    NSUInteger samples = 0;
    NSUInteger nonBlackSamples = 0;
    NSUInteger maxRGB = 0;
    for (size_t y = 0; y < sampleHeight; y++) {
        for (size_t x = 0; x < sampleWidth; x++) {
            size_t offset = y * bytesPerRow + x * 4;
            NSUInteger pixelMax = 0;
            for (size_t component = 0; component < 3; component++) {
                if (bytes[offset + component] > pixelMax) pixelMax = bytes[offset + component];
            }
            if (pixelMax) nonBlackSamples += 1;
            if (pixelMax > maxRGB) maxRGB = pixelMax;
            samples += 1;
        }
    }
    CGContextRelease(context);
    return @{
        @"available": @YES,
        @"data": @YES,
        @"width": @(width),
        @"height": @(height),
        @"sampleWidth": @(sampleWidth),
        @"sampleHeight": @(sampleHeight),
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

static NSData *NNPScreenshotPreviewPNG(UIImage *image) {
    if (!image || image.size.width <= 0 || image.size.height <= 0) return nil;
    CGSize previewSize = image.size;
    CGFloat longestEdge = MAX(previewSize.width, previewSize.height);
    if (longestEdge > 512.0) {
        CGFloat factor = 512.0 / longestEdge;
        previewSize = CGSizeMake(MAX(1.0, floor(previewSize.width * factor)), MAX(1.0, floor(previewSize.height * factor)));
    }
    UIGraphicsBeginImageContextWithOptions(previewSize, YES, 1.0);
    [image drawInRect:CGRectMake(0, 0, previewSize.width, previewSize.height)];
    UIImage *preview = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return preview ? UIImagePNGRepresentation(preview) : nil;
}

static void NNPScreenshotWriteResult(BOOL captureSucceeded, NSString *error, UIImage *image, NSData *png, NSDictionary *captureDiagnostics, NSString *requestID) {
    NSString *imagePath = NNPScreenshotArtifactPath(NNPScreenshotImagePathBase, requestID);
    NSString *sshPath = NNPScreenshotArtifactPath(NNPScreenshotSSHPathBase, requestID);
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"timestamp"] = [NSDate date];
    result[@"success"] = @(captureSucceeded);
    result[@"requestID"] = requestID ?: @"legacy";
    result[@"path"] = imagePath;
    if (error.length) result[@"error"] = error;
    if (captureDiagnostics) result[@"captureDiagnostics"] = captureDiagnostics;

    NNPDiagnosticLog(@"SCREENSHOT_CAPTURE pre-PNG stats begin");
    NSDictionary *prePNG = image ? NNPScreenshotImageStats(image) : nil;
    NNPDiagnosticLog(@"SCREENSHOT_CAPTURE pre-PNG stats complete");
    // Do not decode the full PNG inside SpringBoard. The previous controlled
    // run completed pre-PNG sampling and then stopped in UIImage imageWithData:
    // before publishing any result. The source image has already been sampled
    // above; full post-encode decoding is deferred to the host-side verifier.
    NSDictionary *postPNG = @{
        @"available": @NO,
        @"reason": @"host-side verification required; in-process full PNG decode skipped",
    };
    if (image) {
        result[@"width"] = @(image.size.width);
        result[@"height"] = @(image.size.height);
        result[@"scale"] = @(image.scale);
        if (prePNG) result[@"prePNGStats"] = prePNG;
    }
    if (postPNG) result[@"postPNGStats"] = postPNG;

    NSError *writeError = nil;
    BOOL directWrite = png.length && [png writeToFile:imagePath options:NSDataWritingAtomic error:&writeError];
    result[@"directPathWrite"] = @(directWrite);
    if (!directWrite && writeError.localizedDescription.length) result[@"directPathError"] = writeError.localizedDescription;
    NSError *sshWriteError = nil;
    BOOL sshPathWrite = png.length && [png writeToFile:sshPath options:NSDataWritingAtomic error:&sshWriteError];
    result[@"sshPath"] = sshPath;
    result[@"sshPathWrite"] = @(sshPathWrite);
    if (!sshPathWrite && sshWriteError.localizedDescription.length) result[@"sshPathError"] = sshWriteError.localizedDescription;

    NSData *previewPNG = image ? NNPScreenshotPreviewPNG(image) : nil;
    BOOL previewPreferencePublished = NO;
    if (previewPNG.length && previewPNG.length <= NNPScreenshotPreviewMaxBytes) {
        NNPDiagnosticSetValue(@"SSHScreenshotPreviewPNG", previewPNG);
        previewPreferencePublished = YES;
    }
    result[@"previewBytes"] = @(previewPNG.length);
    result[@"previewPreferencePublished"] = @(previewPreferencePublished);

    BOOL preferencePublished = NO;
    if (png.length && png.length <= NNPScreenshotPreferenceMaxBytes) {
        NNPDiagnosticSetValue(@"SSHScreenshotPNG", png);
        preferencePublished = YES;
        NNPDiagnosticLog(@"SCREENSHOT_CAPTURE diagnostic preference publication requested");
    } else if (png.length) {
        NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE diagnostic preference publication skipped bytes=%lu limit=%lu; use SSH path", (unsigned long)png.length, (unsigned long)NNPScreenshotPreferenceMaxBytes]);
    }
    NNPDiagnosticSetValue(@"SSHScreenshotCaptureDiagnostics", @{
        @"capture": captureDiagnostics ?: @{},
        @"prePNG": prePNG ?: @{},
        @"postPNG": postPNG ?: @{},
        @"encodedBytes": @(png.length),
        @"directPathWrite": @(directWrite),
        @"requestID": requestID ?: @"legacy",
        @"sshPath": sshPath,
        @"sshPathWrite": @(sshPathWrite),
        @"preferencePNGPublished": @(preferencePublished),
        @"previewBytes": @(previewPNG.length),
        @"previewPreferencePublished": @(previewPreferencePublished),
    });
    NNPDiagnosticSetValue(@"SSHScreenshotResult", result);
    [[NSFileManager defaultManager] createDirectoryAtPath:NNPDiagnosticDirectoryPath() withIntermediateDirectories:YES attributes:nil error:NULL];
    [result writeToFile:NNPScreenshotResultPath atomically:YES];
    NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE completed success=%@ bytes=%lu previewBytes=%lu preMaxRGB=%@ postStats=host-only preNonBlack=%@ directPathWrite=%@ sshPathWrite=%@ preferencePNG=%@ previewPreference=%@", captureSucceeded ? @"YES" : @"NO", (unsigned long)png.length, (unsigned long)previewPNG.length, prePNG[@"maxRGB"] ?: @"none", prePNG[@"nonBlackSamples"] ?: @"none", directWrite ? @"YES" : @"NO", sshPathWrite ? @"YES" : @"NO", preferencePublished ? @"YES" : @"NO", previewPreferencePublished ? @"YES" : @"NO"]);
}

static void NNPScreenshotCaptureOne(NSString *requestID) {
    NSDate *captureStart = [NSDate date];
    UIScreen *screen = UIScreen.mainScreen;
    NSDictionary *screenMetadata = NNPScreenshotScreenMetadata(screen);
    NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE capture begin provider=_SBMainScreenScreenshotProvider screen=%@ bounds=%@ nativeBounds=%@ scale=%@ nativeScale=%@ brightness=%@ captured=%@", screenMetadata[@"class"] ?: @"none", screenMetadata[@"bounds"] ?: @"none", screenMetadata[@"nativeBounds"] ?: @"none", screenMetadata[@"scale"] ?: @"none", screenMetadata[@"nativeScale"] ?: @"none", screenMetadata[@"brightness"] ?: @"none", screenMetadata[@"captured"] ?: @"none"]);

    Class providerClass = NSClassFromString(@"_SBMainScreenScreenshotProvider");
    SEL initSelector = NSSelectorFromString(@"initWithScreen:");
    SEL captureSelector = NSSelectorFromString(@"captureScreenshot");
    if (!providerClass || !class_getInstanceMethod(providerClass, initSelector) || !class_getInstanceMethod(providerClass, captureSelector)) {
        NSString *error = @"_SBMainScreenScreenshotProvider or selector unavailable";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NNPScreenshotWriteResult(NO, error, nil, nil, @{
                @"startTimestamp": captureStart,
                @"screen": screenMetadata ?: @{},
            }, requestID);
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
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NNPScreenshotWriteResult(NO, error, nil, nil, captureDiagnostics, requestID);
        });
        NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE failed error=%@", error]);
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
        NNPDiagnosticLog(@"SCREENSHOT_CAPTURE encode worker started");
        NSData *png = UIImagePNGRepresentation(image);
        NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE PNG encoding complete bytes=%lu", (unsigned long)png.length]);
        NNPScreenshotWriteResult(png.length > 0, png.length ? nil : @"PNG encoding returned no data", image, png, captureDiagnostics, requestID);
        }
    });
}

static void NNPScreenshotPoll(void) {
    if (!gNNPScreenshotCaptureRunning) return;
    gNNPScreenshotPollCount += 1;
    NSError *removeError = nil;
    NSString *requestPath = nil;
    NSString *requestID = nil;
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
    id preferenceRequestID = CFBridgingRelease(CFPreferencesCopyAppValue(NNPScreenshotRequestIDPreference, NNPScreenshotPreferenceDomain));
    if ([preferenceRequest respondsToSelector:@selector(boolValue)] && [preferenceRequest boolValue]) {
        CFPreferencesSetAppValue(NNPScreenshotRequestPreference, kCFBooleanFalse, NNPScreenshotPreferenceDomain);
        requestID = [preferenceRequestID isKindOfClass:NSString.class] ? [preferenceRequestID copy] : nil;
        CFPreferencesSetAppValue(NNPScreenshotRequestIDPreference, CFSTR(""), NNPScreenshotPreferenceDomain);
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
            if (!requestID.length) requestID = [NSUUID UUID].UUIDString;
            NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_CAPTURE request accepted id=%@ path=%@; no wake or unlock requested", requestID, requestPath]);
            NSString *capturedRequestID = [requestID copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                NNPScreenshotCaptureOne(capturedRequestID);
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
