#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

// Experimental iOS 17.1.2 CoreBrightness route. All service work happens off
// SpringBoard's main queue, and every accepted override has a paired restore.
FOUNDATION_EXPORT void NNPAODNitsBeginSession(NSString *sessionID, float multiplier);
FOUNDATION_EXPORT void NNPAODNitsSetTargetNits(NSString *sessionID, float nits);
FOUNDATION_EXPORT void NNPAODNitsEndSession(void);
// Runs on main only after the override is cleared; cancelled by a new session.
FOUNDATION_EXPORT void NNPAODNitsEndSessionWithCompletion(dispatch_block_t completion);
