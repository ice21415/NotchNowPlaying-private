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
    double nx, ny;
    assert(NNPMengoWakeConvertPosition(975, 2118, true, 375, 812, 3, &nx, &ny));
    assert(fabs(nx - 325.0 / 375.0) < 0.00001 && fabs(ny - 706.0 / 812.0) < 0.00001);
    assert(NNPMengoWakeConvertPosition(325, 706, false, 375, 812, 3, &nx, &ny));
    assert(fabs(nx - 325.0 / 375.0) < 0.00001);
    assert(NNPMengoWakeConvertPosition(0.86, 0.87, false, 375, 812, 3, &nx, &ny));
    assert(nx == 0.86 && ny == 0.87);
    assert(!NNPMengoWakeConvertPosition(1126, 2436, true, 375, 812, 3, &nx, &ny));
    assert(!NNPMengoWakeConvertPosition(1125, 1346, false, 375, 812, 3, &nx, &ny));
    assert(!NNPMengoWakeConvertPosition(975, 2118, true, 375, 812, NAN, &nx, &ny));
    puts("MeN Go native gesture stale/missing/malformed coordinate checks passed");
    return 0;
}
