# Power statistics audit

The previous estimator converted unsigned current through double (losing negative-current bits), averaged samples without duration weights, summed only downward capacity changes, charged intervals to the later hour, and omitted the final partial minute. It also used current battery capacity for historical percentages and mixed a rolling ten-day summary with calendar-day charts.

New electrical statistics use average-current endpoints (Amperage, falling back to InstantAmperage), trapezoidal integration, and contemporaneous raw full-charge capacity:

- Q(mAh) = -(I0 + I1) * dt / 7200
- E(mW*s) = -(I0*V0 + I1*V1) * dt / 2000
- Mean power(mW) = sum(E) / sum(valid dt)
- Percentage points = sum(Q / mean(endpoint full capacity) * 100)
- Percentage points/hour = percentage points / valid percentage hours

Intervals are accepted only with two readable, unplugged endpoints, nonpositive plausible current, valid voltage, advancing driver UpdateTime when available, at most 150 elapsed seconds, and agreement between continuous monotonic and calendar clocks. Unknown and charger-transition intervals are excluded. Zero current is valid. Failed reads break the baseline. Raw capacity jumps no longer add consumption. Usage, electrical totals and charging-event intervals split at hour boundaries. AOD end and mode changes sample boundaries. Calendar-day summary now matches its chart.

Legacy electrical keys remain stored but are excluded from the new reader. AOD duration and battery history remain available. Detailed views show valid electrical coverage; minimum durations apply to summary power and percentage estimates. Missing data must not be interpreted as zero drain. Charge presence is treated as external power, including plugged-in full batteries.

Limitations: these are whole-device battery-gauge estimates, not isolated plugin consumption or calibrated external measurements. Minute-scale endpoint integration cannot recover unseen load spikes; missing UpdateTime prevents stale-reading detection. Charging duration outside AOD is event-derived and can lag or omit gaps over three hours. Hour splitting assumes a constant interval mean. Zero/full-capacity calibration errors propagate into percentages. Local C math checks pass, but iOS SDK compilation and physical gauge accuracy validation remain pending.

References: https://github.com/apple-oss-distributions/PowerManagement/blob/main/AppleSmartBatteryManager/AppleSmartBattery.cpp and https://developer.apple.com/documentation/kernel/1646199-mach_continuous_time

Validation: `cc -Wall -Wextra -Werror research/tools/power_math_test.c -lm -o /tmp/nnp-power-math-test && /tmp/nnp-power-math-test`.

## Accumulator revision

The two-endpoint trapezoid still misses load changes between the minute samples. The gauge's PowerTelemetryData
exposes AccumulatedSystemLoad (sum of the load in mW) and SystemLoadAccumulatorCount (about one sample per
second), so the primary estimate is now:

- P(mW) = dAccumulatedSystemLoad / dSystemLoadAccumulatorCount
- E(mW*s) = P * dt, valid while charging too (it is the device load, not battery flow)
- Q(mAh) = P / mean(V0, V1) / 3.6 * dt, only for intervals unplugged at both ends
- The trapezoid is the fallback when the counters reset, stall or are missing.

In earlier SSH measurements the accumulator gave stable 620-730 mW means where single InstantAmperage reads
ranged from 30 to 2400 mW. The summary "used" percentage now applies the measured rate to all unplugged AOD time
instead of summing only valid intervals.
