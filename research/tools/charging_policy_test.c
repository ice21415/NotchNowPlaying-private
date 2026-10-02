#include "../../NNPChargingPolicy.h"
#include "../../NNPAODPixelPolicy.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
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
