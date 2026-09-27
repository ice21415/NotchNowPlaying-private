#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void NNPSpotifyLyricsProbeStart(void);
void NNPSpotifyLyricsProbeResetLog(void);
void NNPSpotifyLyricsProbeCaptureNetworkResponse(NSURLRequest *request, NSData *data, NSURLResponse *response, NSError *error);
BOOL NNPSpotifyLyricsProbeShouldTraceNetworkRequest(NSURLRequest *request);
void NNPSpotifyLyricsProbeCaptureNetworkTask(NSURLRequest *request);
void NNPSpotifyLyricsProbeCaptureNetworkData(NSURLSessionTask *task, NSData *data);
void NNPSpotifyLyricsProbeCompleteNetworkTask(NSURLSessionTask *task, NSError *error);
void NNPSpotifyLyricsProbeAppendDiagnostic(NSString *line);

#ifdef __cplusplus
}
#endif
