#include "../../NNPChargingPolicy.h"
#include "../../NNPAODPixelPolicy.h"
#include "../../NNPAODPowerPolicy.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    for (unsigned flags = 0; flags < 64; flags++) {
        bool enabled = flags & 1, locked = flags & 2, active = flags & 4;
        bool ticket = flags & 8, covered = flags & 16, pocket = flags & 32;
        bool expected = enabled && locked && active && !ticket && (covered || pocket);
        assert(NNPAODCoverShouldSuspend(enabled, locked, active, ticket, covered, pocket) == expected);
    }
    assert(!NNPAODCoverShouldSuspend(true, true, true, true, true, true));
    assert(NNPAODCoverShouldSuspend(true, true, true, false, true, false));
    assert(NNPAODCoverShouldSuspend(true, true, true, false, false, true));
    assert(!NNPAODBrightnessNeedsUpdate(0, 0));
    assert(NNPAODBrightnessNeedsUpdate(0, 6));
    assert(NNPAODBrightnessNeedsUpdate(90, 0));
    assert(!NNPAODBrightnessNeedsUpdate(6, 6.6f));
    assert(NNPAODBrightnessNeedsUpdate(6, 6.8f));
    assert(!NNPAODBrightnessNeedsUpdate(100, 100.8f));
    assert(!NNPAODBrightnessNeedsUpdate(100, 99.2f));
    assert(NNPAODBrightnessNeedsUpdate(100, 101.6f));
    assert(NNPAODBrightnessNeedsUpdate(100, 98.4f));
    assert(NNPAODBrightnessNeedsUpdate(6, 180));
    assert(NNPAODBrightnessNeedsUpdate(180, 6));
    // Compare against the last accepted target, so slow cumulative drift wins.
    float accepted = 100;
    unsigned updates = 0;
    for (unsigned i = 1; i <= 10; i++) {
        float target = 100 + i * 0.2f;
        if (NNPAODBrightnessNeedsUpdate(accepted, target)) { accepted = target; updates++; }
    }
    assert(updates == 1 && accepted > 101.5f);
    // Alternating sensor noise used to restart every ramp; it now causes none.
    unsigned oldUpdates = 0, newUpdates = 0;
    float oldTarget = 100, newTarget = 100;
    for (unsigned i = 0; i < 60; i++) {
        float target = i % 2 ? 100.8f : 99.2f;
        if (fabsf(oldTarget - target) >= 0.5f) { oldTarget = target; oldUpdates++; }
        if (NNPAODBrightnessNeedsUpdate(newTarget, target)) { newTarget = target; newUpdates++; }
    }
    assert(oldUpdates == 60 && newUpdates == 0);
    NNPAODAmbientDiagnosticPolicy telemetry = {0};
    assert(NNPAODAmbientShouldReport(&telemetry, 100, true));
    for (unsigned i = 1; i < 30; i++) assert(!NNPAODAmbientShouldReport(&telemetry, 100 + i, true));
    assert(NNPAODAmbientShouldReport(&telemetry, 130, true));
    assert(NNPAODAmbientShouldReport(&telemetry, 131, false));
    assert(!NNPAODAmbientShouldReport(&telemetry, 132, false));
    assert(NNPAODAmbientShouldReport(&telemetry, 133, true));
    assert(NNPAODAmbientShouldReport(&telemetry, 1, true));
    telemetry = (NNPAODAmbientDiagnosticPolicy){0};
    assert(NNPAODAmbientShouldReport(&telemetry, 1, true));
    NNPAODAmbientSamplingPolicy sampling = {0};
    assert(NNPAODAmbientNextSampleInterval(&sampling, 600, true) == 2);
    assert(NNPAODAmbientNextSampleInterval(&sampling, 600, true) == 2);
    assert(NNPAODAmbientNextSampleInterval(&sampling, 599, true) == 2);
    assert(NNPAODAmbientNextSampleInterval(&sampling, 601, true) == 3);
    assert(NNPAODAmbientNextSampleInterval(&sampling, 600, true) == 3);
    assert(NNPAODAmbientNextSampleInterval(&sampling, 600, true) == 5);
    assert(NNPAODAmbientNextSampleInterval(&sampling, 625, true) == 5);
    // Cumulative drift relative to the anchor must exit slow sampling.
    assert(NNPAODAmbientNextSampleInterval(&sampling, 650, true) == 2);
    assert(sampling.stableSamples == 0);
    assert(NNPAODAmbientNextSampleInterval(&sampling, 0, false) == 2);
    assert(!sampling.hasAnchor);
    assert(NNPAODAmbientNextSampleInterval(&sampling, NAN, true) == 2);
    assert(NNPAODAmbientNextSampleInterval(&sampling, 0, true) == 2);
    for (unsigned i = 0; i < 10; i++) NNPAODAmbientNextSampleInterval(&sampling, 0, true);
    assert(NNPAODAmbientNextSampleInterval(&sampling, 0, true) == 5);
    assert(NNPAODAmbientNextSampleInterval(&sampling, 3, true) == 2);
    assert(NNPAODAmbientTargetNits(0) == 6);
    assert(NNPAODAmbientTargetNits(150) == 48);
    assert(NNPAODAmbientTargetNits(300) == 90);
    assert(NNPAODAmbientTargetNits(1200) == 120);
    assert(NNPAODAmbientTargetNits(2100) == 150);
    assert(NNPAODAmbientTargetNits(3000) == 180);
    assert(NNPAODAmbientTargetNits(200000) == 180);
    assert(NNPAODClampAutomaticNits(180) == 180);
    assert(NNPAODClampAutomaticNits(500) == 180);
    assert(NNPAODClampAutomaticNits(1) == 6);
    assert(NNPAODClampAutomaticNits(NAN) == 0);
    assert(NNPAODAmbientTargetNits(200001) == 0);
    assert(NNPAODAmbientTargetNits(NAN) == 0);
    assert(NNPAODAmbientTargetNits(-1) == 0);
    for (int lux = 1; lux <= 300; lux++) {
        float delta = NNPAODAmbientTargetNits(lux) - NNPAODAmbientTargetNits(lux - 1);
        assert(fabsf(delta - 0.28f) < 0.00002f);
    }
    for (int lux = 301; lux <= 3000; lux++) {
        float delta = NNPAODAmbientTargetNits(lux) - NNPAODAmbientTargetNits(lux - 1);
        assert(fabsf(delta - 1.0f / 30.0f) < 0.00002f);
    }
    for (unsigned step = 0; step <= NNPAODBrightnessRampSteps; step++) {
        float up = NNPAODInterpolateNits(6, 90, step);
        float down = NNPAODInterpolateNits(90, 6, step);
        assert(up >= 6 && up <= 90 && down >= 6 && down <= 90);
        assert(fabsf(up - (6 + 84.0f * step / NNPAODBrightnessRampSteps)) < 0.00001f);
        if (step) {
            assert(up > NNPAODInterpolateNits(6, 90, step - 1));
            assert(down < NNPAODInterpolateNits(90, 6, step - 1));
        }
    }
    assert(NNPAODInterpolateNits(6, 90, NNPAODBrightnessRampSteps) == 90);
    assert(NNPAODInterpolateNits(90, 6, NNPAODBrightnessRampSteps) == 6);
    assert(NNPAODInterpolateNits(6, 90, NNPAODBrightnessRampSteps + 1) == 90);
    assert(NNPAODInterpolateNits(90, 180, NNPAODBrightnessRampSteps) == 180);
    bool visited[13][13] = {{false}};
    for (size_t step = 0; step < 169; step++) {
        NNPAODPixelOffset p = NNPAODOffsetForStep(step);
        NNPAODPixelOffset next = NNPAODOffsetForStep(step + 1);
        assert(p.x >= -6 && p.x <= 6 && p.y >= -6 && p.y <= 6);
        assert(p.x != next.x && p.y != next.y);
        assert(!visited[p.y + 6][p.x + 6]);
        visited[p.y + 6][p.x + 6] = true;
    }
    NNPAODPixelOffset initial = NNPAODOffsetForStep(0);
    NNPAODPixelOffset repeated = NNPAODOffsetForStep(169);
    assert(initial.x == repeated.x && initial.y == repeated.y);
    // Only a phone AC-power event in the fully active, locked AOD session qualifies.
    for (long source = 0; source < 40; source++) {
        for (unsigned state = 0; state < 32; state++) {
            bool armed = state & 1, locked = state & 2, aod = state & 4;
            bool enabled = state & 8, chargingEnabled = state & 16;
            bool actual = NNPChargingSuppressesPowerWake(source, armed, locked, aod, enabled, chargingEnabled);
            if (actual) assert(source == 21 && state == 31);
            if (source != 21 || state != 31) assert(!actual);
        }
    }
    assert(NNPChargingSuppressesPowerWake(21, true, true, true, true, true));
    // An illuminated pseudo-AOD panel can legitimately report screenOn=false.
    assert(NNPChargingPresentsFlow(true, true, false, true, true, 0.45f));
    assert(!NNPChargingPresentsFlow(true, true, true, false, true, 0.45f));
    assert(NNPChargingPresentsFlow(true, true, true, true, true, 0.45f));
    assert(!NNPChargingPresentsFlow(true, true, false, false, true, 0.45f));
    assert(!NNPChargingPresentsFlow(true, true, false, true, false, 0.45f));
    assert(!NNPChargingPresentsFlow(false, true, false, true, true, 0.45f));
    assert(!NNPChargingPresentsFlow(true, false, false, true, true, 0.45f));
    assert(!NNPChargingPresentsFlow(true, true, false, true, true, 1.0f));
    assert(!NNPChargingPresentsFlow(true, true, false, true, true, -1.0f));
    assert(!NNPChargingPresentsFlow(true, true, false, true, true, NAN));
    puts("Charging wake exclusions and AOD presentation checks passed");
    return 0;
}
