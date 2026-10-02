#pragma once
#include <stdbool.h>
#include <math.h>

// iOS 17.1.2 SBUIController ACPowerChanged passes unlock source 21.
// This is an unlock source, not an SBBacklightController source (which differs).
static inline bool NNPChargingSuppressesPowerWake(long source, bool armed,
                                                bool locked, bool activeAOD,
                                                bool enabled, bool chargingEnabled) {
    return source == 21 && armed && locked && activeAOD && enabled && chargingEnabled;
}

static inline bool NNPChargingPresentsFlow(bool enabled, bool chargingEnabled,
                                         bool screenOn, bool activeAOD,
                                         bool charging, float level) {
    return enabled && chargingEnabled && (screenOn || activeAOD) && charging &&
        isfinite(level) && level >= 0 && level < 1;
}
