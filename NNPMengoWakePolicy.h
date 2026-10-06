#pragma once
#include <stdbool.h>
#include <math.h>
static inline bool NNPMengoWakeSampleFresh(double timestamp, double now) {
    double age = now - timestamp;
    return isfinite(timestamp) && isfinite(now) && age >= 0 && age <= 0.5;
}
static inline bool NNPMengoWakePositionValid(double x, double y) {
    return isfinite(x) && isfinite(y) && x >= 0 && x <= 1 && y >= 0 && y <= 1 && (x > 0 || y > 0);
}
