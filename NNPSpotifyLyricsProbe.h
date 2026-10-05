#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void NNPSpotifyLyricsProbeStart(void);
void NNPSpotifyLyricsProbeTrackChanged(NSString *uri, NSString *title, NSString *artist);
void NNPSpotifyLyricsProbeResetLog(void);
void NNPSpotifyLyricsProbeCaptureNetworkResponse(NSURLRequest *request, NSData *data, NSURLResponse *response, NSError *error);
BOOL NNPSpotifyLyricsProbeShouldTraceNetworkRequest(NSURLRequest *request);
void NNPSpotifyLyricsProbeCaptureNetworkTask(NSURLSession *session, NSURLRequest *request);
void NNPSpotifyLyricsProbeCaptureNetworkData(NSURLSessionTask *task, NSData *data);
void NNPSpotifyLyricsProbeCompleteNetworkTask(NSURLSessionTask *task, NSError *error);
void NNPSpotifyLyricsProbeAppendDiagnostic(NSString *line);

#ifdef __cplusplus
}
#endif
