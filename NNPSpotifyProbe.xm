#import "NNPSpotifyLyricsProbe.h"

%hook NSURLSession

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

%ctor {
    NNPSpotifyLyricsProbeStart();
}
