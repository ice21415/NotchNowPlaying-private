#import <Foundation/Foundation.h>

// Experimental iOS 17.1.2 CoreBrightness route. All service work happens off
// SpringBoard's main queue, and every accepted override has a paired restore.
FOUNDATION_EXPORT void NNPAODNitsBeginSession(NSString *sessionID, float multiplier);
FOUNDATION_EXPORT void NNPAODNitsEndSession(void);
