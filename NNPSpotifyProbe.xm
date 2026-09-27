#import "NNPSpotifyLyricsProbe.h"
#import <objc/runtime.h>

%group NNPSpotifyDataLoaderServiceHooks

%hook SPTDataLoaderService

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    NNPSpotifyLyricsProbeCaptureNetworkData(dataTask, data);
    %orig(session, dataTask, data);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NNPSpotifyLyricsProbeCompleteNetworkTask(task, error);
    %orig(session, task, error);
}

%end

%end

%group NNPSpotifyNetworkHooks

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NNPSpotifyLyricsProbeCaptureNetworkTask(request);
    return %orig(request);
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!NNPSpotifyLyricsProbeShouldTraceNetworkRequest(request)) return %orig(request, completionHandler);
    void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NNPSpotifyLyricsProbeCaptureNetworkResponse(request, data, response, error);
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, wrappedHandler);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)URL completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
    if (!NNPSpotifyLyricsProbeShouldTraceNetworkRequest(request)) return %orig(URL, completionHandler);
    void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NNPSpotifyLyricsProbeCaptureNetworkResponse(request, data, response, error);
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(URL, wrappedHandler);
}

%end

%end

%ctor {
    %init(NNPSpotifyNetworkHooks);
    NNPSpotifyLyricsProbeStart();
    Class dataLoaderService = objc_lookUpClass("SPTDataLoaderService");
    SEL receiveData = sel_registerName("URLSession:dataTask:didReceiveData:");
    SEL completeTask = sel_registerName("URLSession:task:didCompleteWithError:");
    if (dataLoaderService && class_getInstanceMethod(dataLoaderService, receiveData) && class_getInstanceMethod(dataLoaderService, completeTask)) {
        %init(NNPSpotifyDataLoaderServiceHooks, SPTDataLoaderService=dataLoaderService);
        NNPSpotifyLyricsProbeAppendDiagnostic(@"NETWORK-HOOK SPTDataLoaderService=active");
    } else {
        NNPSpotifyLyricsProbeAppendDiagnostic([NSString stringWithFormat:@"NETWORK-HOOK SPTDataLoaderService=missing class=%@ receive=%@ complete=%@",
                                               dataLoaderService ? @"yes" : @"no",
                                               dataLoaderService && class_getInstanceMethod(dataLoaderService, receiveData) ? @"yes" : @"no",
                                               dataLoaderService && class_getInstanceMethod(dataLoaderService, completeTask) ? @"yes" : @"no"]);
    }
}
