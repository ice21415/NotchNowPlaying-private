#import <Foundation/Foundation.h>

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
