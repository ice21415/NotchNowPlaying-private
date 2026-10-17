#import <Foundation/Foundation.h>

// Research probe (enabled by the ResearchWakeGestureProbe preference): reports whether CoreMotion's
// wake-gesture engine is usable from SpringBoard and whether it delivers lift events while the
// system "Raise to Wake" setting is off. It records diagnostics only and changes no behavior.
FOUNDATION_EXPORT void NNPWakeGestureProbeStartIfEnabled(void);
