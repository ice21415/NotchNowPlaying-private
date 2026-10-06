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
static inline bool NNPMengoWakeConvertPosition(double x, double y, bool pixels,
    double width, double height, double scale, double *nx, double *ny) {
    if (!pixels && NNPMengoWakePositionValid(x, y)) { *nx = x; *ny = y; return true; }
    if (!isfinite(width) || !isfinite(height) || width <= 1 || height <= 1) return false;
    if (pixels) {
        if (!isfinite(scale) || scale < 1 || scale > 4) return false;
        width *= scale; height *= scale;
    }
    double xx = x / width, yy = y / height;
    if (!NNPMengoWakePositionValid(xx, yy)) return false;
    *nx = xx; *ny = yy;
    return true;
}
