#pragma once
#include <stdbool.h>

static inline bool NNPDisplayWakeCanRestoreBrightness(long backlightState, bool aodActive, bool covered) {
    return backlightState == 1 && !aodActive && !covered;
}
static inline bool NNPDisplayWakeShouldReveal(bool armed, bool locked, bool aod, bool pending, bool covered) {
    return armed && locked && !covered && (aod || pending);
}
