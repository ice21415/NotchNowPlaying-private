#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void NNPSpotifyLyricsProbeStart(void);
void NNPSpotifyLyricsProbeCaptureNetworkResponse(NSURLRequest *request, NSData *data, NSURLResponse *response, NSError *error);
BOOL NNPSpotifyLyricsProbeShouldTraceNetworkRequest(NSURLRequest *request);

#ifdef __cplusplus
}
#endif
