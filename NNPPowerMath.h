#pragma once
#include <stdint.h>
#include <math.h>

static inline double NNPSignedCurrent(uint64_t bits) {
    if (bits > INT32_MAX && bits <= UINT32_MAX) return (double)((int64_t)bits - 4294967296LL);
    if (bits > INT64_MAX) return -(double)(UINT64_MAX - bits) - 1.0;
    return (double)bits;
}

static inline double NNPChargeRate(double i0, double i1) {
    return -(i0 + i1) / 7200.0; // mAh per second
}

static inline double NNPMeanPower(double i0, double v0, double i1, double v1) {
    return -(i0 * v0 + i1 * v1) / 2000.0; // mW
}

static inline double NNPNextHourBoundary(double start, double end) {
    return fmin(end, (floor(start / 3600.0) + 1) * 3600.0);
}
