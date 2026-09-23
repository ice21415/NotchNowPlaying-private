#import "NNPScreenshotProbe.h"
#import "NNPDiagnostics.h"
#import <objc/runtime.h>
#import <dlfcn.h>

static void NNPProbeMethod(Class cls, NSString *className, NSString *selectorName, BOOL classMethod) {
    SEL selector = NSSelectorFromString(selectorName);
    Method method = classMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
    if (!method) {
        NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_PROBE class=%@ scope=%@ selector=%@ present=NO", className, classMethod ? @"class" : @"instance", selectorName]);
        return;
    }
    const char *encoding = method_getTypeEncoding(method);
    NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_PROBE class=%@ scope=%@ selector=%@ present=YES types=%@", className, classMethod ? @"class" : @"instance", selectorName, encoding ? [NSString stringWithUTF8String:encoding] : @"unknown"]);
}

void NNPScreenshotProbeInterfaces(void) {
    NNPDiagnosticLog(@"SCREENSHOT_PROBE begin read-only runtime inspection");
    NSArray<NSDictionary *> *candidates = @[
        @{ @"class": @"SBScreenshotManager", @"selectors": @[ @"saveScreenshots", @"saveScreenshotsWithCompletion:" ] },
        @{ @"class": @"_SBMainScreenScreenshotProvider", @"selectors": @[ @"initWithScreen:", @"captureScreenshot" ] },
        @{ @"class": @"_SBDefaultScreenshotProvider", @"selectors": @[ @"initWithScreen:", @"captureScreenshot" ] },
        @{ @"class": @"SBSystemNotesScreenshotter", @"selectors": @[ @"takeScreenshot", @"captureScreenshot" ] },
        @{ @"class": @"SSScreenCapturer", @"selectors": @[ @"captureScreenshot", @"captureScreenshotWithInterfaceOrientation:completion:" ] },
    ];
    for (NSDictionary *candidate in candidates) {
        NSString *className = candidate[@"class"];
        Class cls = NSClassFromString(className);
        NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_PROBE class=%@ available=%@", className, cls ? @"YES" : @"NO"]);
        if (!cls) continue;
        for (NSString *selectorName in candidate[@"selectors"]) {
            NNPProbeMethod(cls, className, selectorName, NO);
            NNPProbeMethod(cls, className, selectorName, YES);
        }
    }
    void *captureSymbol = dlsym(RTLD_DEFAULT, "BKDisplayCaptureImage");
    NNPDiagnosticLog([NSString stringWithFormat:@"SCREENSHOT_PROBE symbol=BKDisplayCaptureImage process_scope=%@", captureSymbol ? @"AVAILABLE" : @"UNAVAILABLE"]);
    NNPDiagnosticLog(@"SCREENSHOT_PROBE end no capture invoked");
}
