#include "../../NNPMengoWakePolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(NNPMengoWakeSampleFresh(20, 20));
    assert(NNPMengoWakeSampleFresh(20, 20.5));
    assert(!NNPMengoWakeSampleFresh(20, 20.501));
    assert(!NNPMengoWakeSampleFresh(21, 20));
    assert(!NNPMengoWakeSampleFresh(NAN, 20));
    assert(!NNPMengoWakeSampleFresh(20, INFINITY));
    assert(NNPMengoWakePositionValid(0.84, 0.87));
    assert(NNPMengoWakePositionValid(0, 1));
    assert(!NNPMengoWakePositionValid(0, 0));
    assert(!NNPMengoWakePositionValid(-0.01, 0.8));
    assert(!NNPMengoWakePositionValid(320, 680));
    assert(!NNPMengoWakePositionValid(NAN, 0.5));
    assert(!NNPMengoWakePositionValid(0.5, INFINITY));
    puts("MeN Go native gesture stale/missing/malformed coordinate checks passed");
    return 0;
}
