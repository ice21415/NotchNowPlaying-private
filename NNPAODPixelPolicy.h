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
    return (float)(6.0 + fmin(lux, 300.0) * 0.28);
}

enum { NNPAODBrightnessRampSteps = 24 };
#define NNPAODBrightnessRampInterval 0.04
static inline float NNPAODInterpolateNits(float start, float target, unsigned step) {
    return start + (target - start) * (step > NNPAODBrightnessRampSteps ? NNPAODBrightnessRampSteps : step) / (float)NNPAODBrightnessRampSteps;
}
