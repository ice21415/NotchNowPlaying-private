#pragma once
#include <stddef.h>
#include <math.h>

typedef struct { int x; int y; } NNPAODPixelOffset;
// Visit all 169 positions once, changing both axes on every step.
static inline NNPAODPixelOffset NNPAODOffsetForStep(size_t step) {
    size_t index = (step % 169) * 14 % 169;
    return (NNPAODPixelOffset){ (int)(index % 13) - 6, (int)(index / 13) - 6 };
}

static inline float NNPAODAmbientBrightnessMultiplier(double lux, float current) {
    if (!isfinite(lux) || lux < 0 || lux > 200000) return 1.0f;
    if (current <= 1.25f) return lux < 15 ? 1.0f : (lux < 150 ? 1.5f : 2.0f);
    if (current < 1.75f) return lux <= 8 ? 1.0f : (lux >= 150 ? 2.0f : 1.5f);
    return lux <= 8 ? 1.0f : (lux < 80 ? 1.5f : 2.0f);
}
