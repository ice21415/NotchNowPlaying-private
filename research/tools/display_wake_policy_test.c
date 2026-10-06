#include "../../NNPDisplayWakePolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(NNPDisplayWakeShouldReveal(true, true, true, false, false));
    assert(NNPDisplayWakeShouldReveal(true, true, false, true, false));
    assert(!NNPDisplayWakeShouldReveal(true, true, false, false, false));
    assert(!NNPDisplayWakeShouldReveal(true, true, true, true, true));
    assert(!NNPDisplayWakeShouldReveal(false, true, true, true, false));
    assert(!NNPDisplayWakeShouldReveal(true, false, true, true, false));
    puts("AOD wake cleanup without pending flag and covered/inactive exclusions passed");
}
