#import "../../NNPDiagnostics.h"
#include <assert.h>

static unsigned messages, calls;
static NSString *Message(void) { messages++; return @"detail"; }
// Parentheses leave the underlying exported functions independent of macros.
void (NNPDiagnosticLog)(NSString *event) { (void)event; calls++; }
void (NNPDiagnosticLogTransition)(NSString *event) { (void)event; calls++; }
void (NNPDiagnosticLogCallStack)(NSString *event, NSUInteger frames) { (void)event; (void)frames; calls++; }
int main(void) {
    @autoreleasepool {
        NNPDiagnosticLog(Message());
        NNPDiagnosticLogTransition(Message());
        if (YES) NNPDiagnosticLogCallStack(Message(), 4); else assert(0);
        assert(messages == (NNP_ENABLE_VERBOSE_DIAGNOSTICS ? 3 : 0));
        assert(calls == (NNP_ENABLE_VERBOSE_DIAGNOSTICS ? 3 : 0));
        puts("Diagnostic argument evaluation policy passed");
    }
    return 0;
}
