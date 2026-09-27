#import "NNPSpotifyLyricsProbe.h"

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!NNPSpotifyLyricsProbeShouldTraceNetworkRequest(request)) return %orig;
    return %orig(request, ^(NSData *data, NSURLResponse *response, NSError *error) {
        NNPSpotifyLyricsProbeCaptureNetworkResponse(request, data, response, error);
        if (completionHandler) completionHandler(data, response, error);
    });
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)URL completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
    if (!NNPSpotifyLyricsProbeShouldTraceNetworkRequest(request)) return %orig;
    return %orig(URL, ^(NSData *data, NSURLResponse *response, NSError *error) {
        NNPSpotifyLyricsProbeCaptureNetworkResponse(request, data, response, error);
        if (completionHandler) completionHandler(data, response, error);
    });
}

%end

%ctor {
    NNPSpotifyLyricsProbeStart();
}
