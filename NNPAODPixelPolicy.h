#pragma once
#include <stddef.h>
#include <math.h>

typedef struct { int x; int y; } NNPAODPixelOffset;
// Visit all 169 positions once, changing both axes on every step.
static inline NNPAODPixelOffset NNPAODOffsetForStep(size_t step) {
    size_t index = (step % 169) * 14 % 169;
    return (NNPAODPixelOffset){ (int)(index % 13) - 6, (int)(index / 13) - 6 };
}

static inline float NNPAODAmbientTargetNits(double lux) {
    if (!isfinite(lux) || lux < 0 || lux > 200000) return 0;
    if (lux <= 300) return (float)(6.0 + lux * 0.28);
    return (float)(90.0 + fmin(lux - 300.0, 2700.0) / 30.0);
}

static inline float NNPAODClampAutomaticNits(float nits) {
    return isfinite(nits) && nits > 0 ? fminf(180, fmaxf(6, nits)) : 0;
}

enum { NNPAODBrightnessRampSteps = 24 };
#define NNPAODBrightnessRampInterval 0.04
static inline float NNPAODInterpolateNits(float start, float target, unsigned step) {
    return start + (target - start) * (step > NNPAODBrightnessRampSteps ? NNPAODBrightnessRampSteps : step) / (float)NNPAODBrightnessRampSteps;
}
