#include "../../NNPChargingPolicy.h"
#include "../../NNPAODPixelPolicy.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    assert(NNPAODAmbientBrightnessMultiplier(0, 1) == 1);
    assert(NNPAODAmbientBrightnessMultiplier(14.99, 1) == 1);
    assert(NNPAODAmbientBrightnessMultiplier(15, 1) == 1.5f);
    assert(NNPAODAmbientBrightnessMultiplier(10, 1.5f) == 1.5f);
    assert(NNPAODAmbientBrightnessMultiplier(8, 1.5f) == 1);
    assert(NNPAODAmbientBrightnessMultiplier(150, 1.5f) == 2);
    assert(NNPAODAmbientBrightnessMultiplier(100, 2) == 2);
    assert(NNPAODAmbientBrightnessMultiplier(79.99, 2) == 1.5f);
    assert(NNPAODAmbientBrightnessMultiplier(200000, 2) == 2);
    assert(NNPAODAmbientBrightnessMultiplier(NAN, 2) == 1);
    assert(NNPAODAmbientBrightnessMultiplier(-1, 2) == 1);
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
