#import <Foundation/Foundation.h>

// Pure parsing/form encoding shared by the runtime and host tests.
FOUNDATION_EXPORT NSData *NNPMengoFormBody(NSString *token);
FOUNDATION_EXPORT NSData *NNPMengoImageData(NSData *response, NSString **message);

