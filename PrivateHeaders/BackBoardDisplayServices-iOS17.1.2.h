// Research-only declarations from iOS 17.1.2.
// Not imported or called by the production build.
#import <Foundation/Foundation.h>
@protocol BSInvalidatable;
FOUNDATION_EXPORT BOOL BKSDisplayServicesStart(void);
FOUNDATION_EXPORT BOOL BKSDisplayServicesIsScreenDisabled(id displayIdentifier);
FOUNDATION_EXPORT void BKSDisplayServicesSetScreenDisabled(id displayIdentifier, BOOL disabled);
FOUNDATION_EXPORT void BKSDisplayServicesSetScreenBlanked(BOOL blanked);
FOUNDATION_EXPORT void BKSDisplayServicesSetDisplayBlanked(id display, BOOL blanked);
FOUNDATION_EXPORT BOOL BKSDisplayServicesGetBlankingRemovesPower(id display);
FOUNDATION_EXPORT void BKSDisplayServicesSetBlankingRemovesPower(id display, BOOL removesPower);
FOUNDATION_EXPORT id<BSInvalidatable> BKSDisplayServicesAcquireDisplayDisabledAssertion(id firstArgument, id secondArgument);
FOUNDATION_EXPORT void BKSDisplayServicesWillUnblank(void);
FOUNDATION_EXPORT void BKSDisplayServicesWillUnblankDisplay(id display);
