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

// The gauge adds the instantaneous system load (mW) to an accumulator about once a second, so the difference
// of two readings divided by the difference of the sample counts is the true mean load over the interval.
// Returns -1 when the counters reset, did not advance, or give an implausible value.
static inline double NNPAccumulatorMeanPower(double acc0, double count0, double acc1, double count1) {
    if (!isfinite(acc0) || !isfinite(count0) || !isfinite(acc1) || !isfinite(count1)) return -1;
    if (count1 <= count0 || acc1 < acc0) return -1;
    double power = (acc1 - acc0) / (count1 - count0);
    return power >= 0 && power <= 20000 ? power : -1;
}

// Battery discharge rate (mAh per second) for a mean power (mW) at a mean voltage (mV): mW / mV = A.
static inline double NNPChargeRateFromPower(double power, double v0, double v1) {
    return power / ((v0 + v1) / 2.0) / 3.6;
}
