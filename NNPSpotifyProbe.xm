#import "NNPSpotifyLyricsProbe.h"
#import <objc/runtime.h>
#import <stdlib.h>

%group NNPSpotifyNetworkHooks

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NNPSpotifyLyricsProbeCaptureNetworkTask(self, request);
    return %orig(request);
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!NNPSpotifyLyricsProbeShouldTraceNetworkRequest(request)) return %orig(request, completionHandler);
    NNPSpotifyLyricsProbeCaptureNetworkTask(self, request);
    void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NNPSpotifyLyricsProbeCaptureNetworkResponse(request, data, response, error);
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, wrappedHandler);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)URL completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
    if (!NNPSpotifyLyricsProbeShouldTraceNetworkRequest(request)) return %orig(URL, completionHandler);
    NNPSpotifyLyricsProbeCaptureNetworkTask(self, request);
    void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NNPSpotifyLyricsProbeCaptureNetworkResponse(request, data, response, error);
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(URL, wrappedHandler);
}

%end

%end

static NSMutableDictionary<NSValue *, NSValue *> *NNPSpotifyReceiveOriginals;
static NSMutableDictionary<NSValue *, NSValue *> *NNPSpotifyCompleteOriginals;
static NSObject *NNPSpotifyOriginalsLock;

static NSValue *NNPSpotifyClassKey(Class cls) {
    return [NSValue valueWithPointer:(const void *)cls];
}

static IMP NNPSpotifyOriginalIMP(NSMutableDictionary<NSValue *, NSValue *> *originals, id object) {
    if (!originals || !object) return NULL;
    @synchronized (NNPSpotifyOriginalsLock) {
        for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
            NSValue *value = originals[NNPSpotifyClassKey(cls)];
            if (value) return (IMP)value.pointerValue;
        }
    }
    return NULL;
}

static void NNPSpotifyURLSessionDidReceiveData(id self, SEL selector, NSURLSession *session,
                                               NSURLSessionDataTask *dataTask, NSData *data) {
    NSURLRequest *request = dataTask.originalRequest ?: dataTask.currentRequest;
    if ([request.URL.absoluteString.lowercaseString containsString:@"lyrics"]) {
        NSString *url = [NSString stringWithFormat:@"%@%@", request.URL.host ?: @"", request.URL.path ?: @""];
        NNPSpotifyLyricsProbeAppendDiagnostic([NSString stringWithFormat:@"NETWORK-CALLBACK receive class=%@ bytes=%lu url=%@",
                                               NSStringFromClass(object_getClass(self)) ?: @"?",
                                               (unsigned long)data.length, url]);
        NNPSpotifyLyricsProbeCaptureNetworkData(dataTask, data);
    }
    IMP original = NNPSpotifyOriginalIMP(NNPSpotifyReceiveOriginals, self);
    if (original) ((void (*)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *))original)(self, selector, session, dataTask, data);
}

static void NNPSpotifyURLSessionTaskDidComplete(id self, SEL selector, NSURLSession *session,
                                                NSURLSessionTask *task, NSError *error) {
    NSURLRequest *request = task.originalRequest ?: task.currentRequest;
    if ([request.URL.absoluteString.lowercaseString containsString:@"lyrics"]) {
        NSInteger status = [task.response isKindOfClass:NSHTTPURLResponse.class]
            ? ((NSHTTPURLResponse *)task.response).statusCode : 0;
        NNPSpotifyLyricsProbeAppendDiagnostic([NSString stringWithFormat:@"NETWORK-CALLBACK complete class=%@ status=%ld bytes=%lld error=%@",
                                               NSStringFromClass(object_getClass(self)) ?: @"?",
                                               (long)status, task.countOfBytesReceived,
                                               error.localizedDescription ?: @""]);
    }
    NNPSpotifyLyricsProbeCompleteNetworkTask(task, error);
    IMP original = NNPSpotifyOriginalIMP(NNPSpotifyCompleteOriginals, self);
    if (original) ((void (*)(id, SEL, NSURLSession *, NSURLSessionTask *, NSError *))original)(self, selector, session, task, error);
}

static BOOL NNPSpotifyClassBelongsToMainBundle(Class cls, NSString *bundlePath) {
    const char *imageName = class_getImageName(cls);
    if (!imageName || !bundlePath.length) return NO;
    NSString *imagePath = [NSString stringWithUTF8String:imageName];
    return [imagePath hasPrefix:bundlePath];
}

static void NNPSpotifyInstallDataDelegateHooks(void) {
    SEL receiveSelector = sel_registerName("URLSession:dataTask:didReceiveData:");
    SEL completeSelector = sel_registerName("URLSession:task:didCompleteWithError:");
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    NNPSpotifyReceiveOriginals = [NSMutableDictionary dictionary];
    NNPSpotifyCompleteOriginals = [NSMutableDictionary dictionary];
    NNPSpotifyOriginalsLock = [NSObject new];

    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) {
        NNPSpotifyLyricsProbeAppendDiagnostic(@"NETWORK-HOOK delegate-classes=0");
        return;
    }
    __unsafe_unretained Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    if (!classes) {
        NNPSpotifyLyricsProbeAppendDiagnostic(@"NETWORK-HOOK delegate-class-list=allocation-failed");
        return;
    }
    classCount = objc_getClassList(classes, classCount);
    NSUInteger receiveCount = 0;
    NSUInteger completeCount = 0;
    NSMutableArray<NSString *> *hookedNames = [NSMutableArray array];

    for (int index = 0; index < classCount; index++) {
        Class cls = classes[index];
        if (!NNPSpotifyClassBelongsToMainBundle(cls, bundlePath)) continue;
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
            Method method = methods[methodIndex];
            SEL selector = method_getName(method);
            BOOL isReceive = selector == receiveSelector;
            BOOL isComplete = selector == completeSelector;
            if (!isReceive && !isComplete) continue;

            NSValue *key = NNPSpotifyClassKey(cls);
            IMP original = method_getImplementation(method);
            @synchronized (NNPSpotifyOriginalsLock) {
                if (isReceive) NNPSpotifyReceiveOriginals[key] = [NSValue valueWithPointer:(const void *)original];
                else NNPSpotifyCompleteOriginals[key] = [NSValue valueWithPointer:(const void *)original];
            }
            IMP replacement = isReceive ? (IMP)NNPSpotifyURLSessionDidReceiveData : (IMP)NNPSpotifyURLSessionTaskDidComplete;
            method_setImplementation(method, replacement);
            if (isReceive) receiveCount++; else completeCount++;
            NSString *name = NSStringFromClass(cls) ?: @"?";
            if (hookedNames.count < 24 && ![hookedNames containsObject:name]) [hookedNames addObject:name];
        }
        free(methods);
    }
    free(classes);
    NNPSpotifyLyricsProbeAppendDiagnostic([NSString stringWithFormat:@"NETWORK-HOOK receive=%lu complete=%lu classes=%@",
                                           (unsigned long)receiveCount, (unsigned long)completeCount,
                                           [hookedNames componentsJoinedByString:@","]]);
}

%ctor {
    %init(NNPSpotifyNetworkHooks);
    NNPSpotifyLyricsProbeResetLog();
    NNPSpotifyLyricsProbeStart();
    NNPSpotifyInstallDataDelegateHooks();
}
