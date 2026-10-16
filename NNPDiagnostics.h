#import <Foundation/Foundation.h>
#ifndef NNP_ENABLE_VERBOSE_DIAGNOSTICS
#define NNP_ENABLE_VERBOSE_DIAGNOSTICS 0
#endif

FOUNDATION_EXPORT NSString *NNPDiagnosticDirectoryPath(void);
FOUNDATION_EXPORT NSString *NNPDiagnosticLogPath(void);
FOUNDATION_EXPORT NSString *NNPDiagnosticArmPath(void);
FOUNDATION_EXPORT void NNPDiagnosticLog(NSString *event);
FOUNDATION_EXPORT void NNPDiagnosticRecordStartup(NSString *detail);
FOUNDATION_EXPORT void NNPDiagnosticSetValue(NSString *key, id value);
FOUNDATION_EXPORT id NNPDiagnosticCopyValue(NSString *key);
FOUNDATION_EXPORT void NNPDiagnosticSetBool(NSString *key, BOOL value);
FOUNDATION_EXPORT void NNPDiagnosticSetInteger(NSString *key, NSInteger value);
FOUNDATION_EXPORT void NNPDiagnosticSetDouble(NSString *key, double value);
FOUNDATION_EXPORT void NNPDiagnosticSetString(NSString *key, NSString *value);
FOUNDATION_EXPORT void NNPDiagnosticAppendEvent(NSDictionary *event);
FOUNDATION_EXPORT BOOL NNPDiagnosticArmExists(BOOL *readable);
FOUNDATION_EXPORT BOOL NNPDiagnosticConsumeArm(void);
FOUNDATION_EXPORT NSString *NNPDiagnosticBeginTransition(NSString *reason);
FOUNDATION_EXPORT void NNPDiagnosticLogTransition(NSString *event);
FOUNDATION_EXPORT void NNPDiagnosticLogCallStack(NSString *event, NSUInteger maximumFrames);

// Avoid constructing messages and collecting arguments when detailed logging
// is disabled. Keep the real symbols available for the implementation.
#if !defined(NNP_DIAGNOSTICS_IMPLEMENTATION)
#define NNPDiagnosticLog(...) do { if (NNP_ENABLE_VERBOSE_DIAGNOSTICS) NNPDiagnosticLog(__VA_ARGS__); } while (0)
// Transitions are rare, and the recent-transition ring is always kept, so this call is never compiled out.
#define NNPDiagnosticLogCallStack(...) do { if (NNP_ENABLE_VERBOSE_DIAGNOSTICS) NNPDiagnosticLogCallStack(__VA_ARGS__); } while (0)
#endif
