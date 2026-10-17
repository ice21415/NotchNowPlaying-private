#include "../../NNPPowerMath.h"
#include <assert.h>
#include <stdio.h>
static void near(double a, double b) { assert(fabs(a-b) < 1e-8); }
int main(void) {
    near(NNPSignedCurrent(UINT64_MAX - 99), -100);
    near(NNPSignedCurrent(UINT32_MAX - 99), -100);
    near(NNPSignedCurrent(0), 0);
    near(NNPSignedCurrent(100), 100);
    near(NNPChargeRate(-100, -100) * 3600, 100);
    near(NNPMeanPower(-100, 4000, -100, 4000), 400);
    near(NNPChargeRate(-100, -300) * 60, 10.0/3);
    near(NNPMeanPower(-100, 4000, -300, 4000), 800);
    // Unequal 30/90-second windows must have time-weighted mean 700 mW.
    near((400.0*30 + 800.0*90)/120, 700);
    near(NNPNextHourBoundary(3590, 3650), 3600);
    near(NNPNextHourBoundary(3600, 3650), 3650);
    near(NNPNextHourBoundary(3590, 3599), 3599);
    near(NNPChargeRate(0, 0), 0);
    puts("power math: 12 checks passed");
}
