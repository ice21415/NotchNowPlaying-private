#pragma once
#include "NNPAODPixelPolicy.h"
#include <stdbool.h>

typedef struct {
    float anchorNits;
    unsigned stableSamples;
    bool hasAnchor;
} NNPAODAmbientSamplingPolicy;

static inline double NNPAODAmbientNextSampleInterval(NNPAODAmbientSamplingPolicy *policy, double lux, bool valid) {
    float target = valid ? NNPAODAmbientTargetNits(lux) : 0;
    if (target <= 0) {
        *policy = (NNPAODAmbientSamplingPolicy){0};
        return 5;
    }
    float tolerance = fmaxf(0.75f, target * 0.015f);
    if (!policy->hasAnchor || fabsf(target - policy->anchorNits) > tolerance) {
        *policy = (NNPAODAmbientSamplingPolicy){target, 0, true};
        return 5;
    }
    if (policy->stableSamples < 5) policy->stableSamples++;
    return policy->stableSamples >= 5 ? 30 : policy->stableSamples >= 3 ? 15 : 5;
}

#define NNPTitleMarqueeInitialPause 1.4
#define NNPTitleMarqueeIdleSeconds 20.0
