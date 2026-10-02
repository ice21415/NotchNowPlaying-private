# AOD power measurement

The standalone `research/tools/aod_power_probe.m` is built with Apple Clang by
`.github/workflows/build-power-probe.yml`. It only reads battery registry
properties; it does not activate ALS, modify battery settings, or install a daemon.
Measurements and device identifiers must remain in ignored `build-packages/`.

## Device validation

On iPhone13,1 / iOS 17.1.2 the sampler successfully reads AppleSmartBattery.
The device reports signed `InstantAmperage`, `Amperage`, `Voltage`, temperature,
charging state, raw capacity and `PowerTelemetryData`. A single reading is not a
comparison and cannot attribute consumption to the plugin or its sensor polling.

RootHide may redirect paths opened by the executable. Redirect stdout using the
SSH shell to store logs in the same filesystem view as SFTP:

```
/tmp/nnp-power-probe 61 30 > /tmp/nnp-power-session.jsonl
```

## Controlled comparison

User must confirm an uninterrupted, unplugged AOD test with steady ambient light
and identical playback, audio volume, wireless connectivity and UI content.
No respring between measurement phases. Check charging state, AOD state, accepted
fixed-nits override and ambient lux at phase boundaries. Exclude time after a
notification, unlock, charging connection or other state change.

Use four alternating five-minute phases (A/B/B/A), excluding the first minute
after each setting change. A is automatic ambient adjustment; B is manual fixed
brightness matching A's accepted nits, where its 30–120 nits range allows this.
Reject the comparison if auto brightness drifts materially during the phases.
Save original preference values before changes and restore them afterward.
Native dimming settings also differ between automatic and manual modes; this
test compares the two complete modes rather than isolated sensor hardware power.

For each phase report average and median discharge current, voltage, estimated
battery power `-InstantAmperage * Voltage / 1e6` watts, sample dispersion, valid
sample count and temperature range. Preserve driver update timestamps to identify
repeated/stale measurements. Signed negative current indicates discharge on this
device; charging samples are invalid for this comparison. Battery-gauge readings
are whole-device estimates, not external calibrated power measurements.

Small differences within variation are inconclusive. Do not report that ALS
polling is free or that the feature saves a particular percentage without adequate
repeatable comparisons. A second comparison against the previous fixed high
brightness can evaluate practical savings from dimming, but does not isolate ALS
overhead. Matching equal brightness comes first.
