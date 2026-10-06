#pragma once
#include "NNPAODPixelPolicy.h"
#include <stdbool.h>

typedef struct {
    float anchorNits;
    unsigned stableSamples;
    bool hasAnchor;
} NNPAODAmbientSamplingPolicy;

static inline bool NNPAODBrightnessNeedsUpdate(float current, float target) {
    // Switching between automatic override and fallback must never be filtered.
    if ((current > 0) != (target > 0)) return true;
    float tolerance = fmaxf(0.75f, fmaxf(current, target) * 0.015f);
    return fabsf(current - target) >= tolerance;
}

static inline double NNPAODAmbientNextSampleInterval(NNPAODAmbientSamplingPolicy *policy, double lux, bool valid) {
    float target = valid ? NNPAODAmbientTargetNits(lux) : 0;
    if (target <= 0) {
        *policy = (NNPAODAmbientSamplingPolicy){0};
        return 2;
    }
    float tolerance = fmaxf(0.75f, target * 0.015f);
    if (!policy->hasAnchor || fabsf(target - policy->anchorNits) > tolerance) {
        *policy = (NNPAODAmbientSamplingPolicy){target, 0, true};
        return 2;
    }
    if (policy->stableSamples < 5) policy->stableSamples++;
    return policy->stableSamples >= 5 ? 5 : policy->stableSamples >= 3 ? 3 : 2;
}

#define NNPTitleMarqueeInitialPause 1.4
#define NNPTitleMarqueeIdleSeconds 20.0

typedef struct {
    double lastReport;
    bool reported;
    bool valid;
} NNPAODAmbientDiagnosticPolicy;

// Telemetry cadence must never change the sensor or brightness cadence.
static inline bool NNPAODAmbientShouldReport(NNPAODAmbientDiagnosticPolicy *policy, double now, bool valid) {
    bool report = !policy->reported || valid != policy->valid ||
        now < policy->lastReport || now - policy->lastReport >= 30.0;
    if (report) *policy = (NNPAODAmbientDiagnosticPolicy){now, true, valid};
    return report;
}
