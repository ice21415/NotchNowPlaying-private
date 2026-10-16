#pragma once
#include <stddef.h>
#include <math.h>

typedef struct { int x; int y; } NNPAODPixelOffset;
// Visit all 169 positions once, changing both axes on every step.
static inline NNPAODPixelOffset NNPAODOffsetForStep(size_t step) {
    size_t index = (step % 169) * 14 % 169;
    return (NNPAODPixelOffset){ (int)(index % 13) - 6, (int)(index / 13) - 6 };
}

// Default AOD luminance curve read from CoreBrightness (CBAODState init): lux -> nits, piecewise linear.
static inline float NNPAODAmbientTargetNits(double lux) {
    if (!isfinite(lux) || lux < 0 || lux > 200000) return 0;
    static const double xs[5] = {0.0, 50.0, 530.0, 3780.0, 10000.0};
    static const double ys[5] = {2.0, 30.0, 98.0, 500.0, 500.0};
    for (int i = 1; i < 5; i++) {
        if (lux <= xs[i]) return (float)(ys[i - 1] + (ys[i] - ys[i - 1]) * (lux - xs[i - 1]) / (xs[i] - xs[i - 1]));
    }
    return 500.0f;
}

static inline float NNPAODClampAutomaticNits(float nits) {
    return isfinite(nits) && nits > 0 ? fminf(250, fmaxf(2, nits)) : 0;
}

enum { NNPAODBrightnessRampSteps = 24 };
#define NNPAODBrightnessRampInterval 0.04
static inline float NNPAODInterpolateNits(float start, float target, unsigned step) {
    return start + (target - start) * (step > NNPAODBrightnessRampSteps ? NNPAODBrightnessRampSteps : step) / (float)NNPAODBrightnessRampSteps;
}
