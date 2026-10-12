#include "../../NNPDisplayWakePolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    for (long state = -1; state <= 5; state++) {
        for (unsigned flags = 0; flags < 4; flags++) {
            bool aod = flags & 1, covered = flags & 2;
            assert(NNPDisplayWakeCanRestoreBrightness(state, aod, covered) == (state == 1 && !aod && !covered));
        }
    }
    assert(NNPDisplayWakeShouldReveal(true, true, true, false, false));
    assert(NNPDisplayWakeShouldReveal(true, true, false, true, false));
    assert(!NNPDisplayWakeShouldReveal(true, true, false, false, false));
    assert(!NNPDisplayWakeShouldReveal(true, true, true, true, true));
    assert(!NNPDisplayWakeShouldReveal(false, true, true, true, false));
    assert(!NNPDisplayWakeShouldReveal(true, false, true, true, false));
    puts("AOD wake cleanup without pending flag and covered/inactive exclusions passed");
}
