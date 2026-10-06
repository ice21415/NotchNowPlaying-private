#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NNPMengoCredentialStatus) {
    NNPMengoCredentialUnknown = 0,
    NNPMengoCredentialValid = 1,
    NNPMengoCredentialRejected = 2,
    NNPMengoCredentialMissing = 3,
};
// Classifies only a successful HTTP response from the official LoginCheck API.
NNPMengoCredentialStatus NNPMengoLoginCheckStatus(NSData *response);

// Pure parsing/form encoding shared by the runtime and host tests.
FOUNDATION_EXPORT NSData *NNPMengoFormBody(NSString *token);
FOUNDATION_EXPORT NSData *NNPMengoImageData(NSData *response, NSString **message);
