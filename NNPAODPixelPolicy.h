#pragma once
#include <stddef.h>

typedef struct { int x; int y; } NNPAODPixelOffset;
// Visit all 169 positions once, changing both axes on every step.
static inline NNPAODPixelOffset NNPAODOffsetForStep(size_t step) {
    size_t index = (step % 169) * 14 % 169;
    return (NNPAODPixelOffset){ (int)(index % 13) - 6, (int)(index / 13) - 6 };
}
