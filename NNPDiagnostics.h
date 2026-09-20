#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *NNPDiagnosticDirectoryPath(void);
FOUNDATION_EXPORT NSString *NNPDiagnosticLogPath(void);
FOUNDATION_EXPORT NSString *NNPDiagnosticArmPath(void);
FOUNDATION_EXPORT void NNPDiagnosticLog(NSString *event);
FOUNDATION_EXPORT void NNPDiagnosticRecordStartup(NSString *detail);
FOUNDATION_EXPORT BOOL NNPDiagnosticArmExists(BOOL *readable);
FOUNDATION_EXPORT BOOL NNPDiagnosticConsumeArm(void);
