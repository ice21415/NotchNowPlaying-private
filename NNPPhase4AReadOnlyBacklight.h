#import <Foundation/Foundation.h>

// Compiled only for the one-read-per-condition Phase 4A experiment.
#ifdef __cplusplus
extern "C" {
#endif

NSString *NNPPhase4ABuildIdentity(void);
void NNPPhase4ASetDiagnosticValue(NSString *key, id value);
void NNPPhase4ASetDiagnosticBoolean(NSString *key, BOOL value);
void NNPPhase4ASetDiagnosticInteger(NSString *key, long long value);
void NNPPhase4ATrace(NSString *marker);
void NNPPhase4AStartReadOnlyBacklightObservation(void);
BOOL NNPPhase4AReadBacklightState(long long *state);
void NNPPhase4ASetUIState(BOOL succeeded, long long state);
NSString *NNPPhase4AUIStateMarker(void);
void NNPPhase4ANoop(void);
int NNPPhase4AConstant(void);

#ifdef __cplusplus
}
#endif
