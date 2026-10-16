#pragma once
#include <stdbool.h>

static inline bool NNPDisplayWakeCanRestoreBrightness(long backlightState, bool aodActive, bool covered) {
    return backlightState == 1 && !aodActive && !covered;
}
static inline bool NNPDisplayWakeShouldReveal(bool armed, bool locked, bool aod, bool pending, bool covered) {
    return armed && locked && !covered && (aod || pending);
}

// Backlight requests from the proximity policy (source 13) restore the panel after the sensor clears;
// they are not user wakes, so they must not tear down the AOD cover. A pending tap wake still reveals.
#define NNPBacklightSourceProximity 13
static inline bool NNPDisplayWakeShouldRevealForSource(bool armed, bool locked, bool aod, bool pending, bool covered, long source) {
    bool userWakeAOD = aod && source != NNPBacklightSourceProximity;
    return NNPDisplayWakeShouldReveal(armed, locked, userWakeAOD, pending, covered);
}
