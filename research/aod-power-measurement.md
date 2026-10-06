# AOD power measurement

The standalone `research/tools/aod_power_probe.m` is built with Apple Clang by
`.github/workflows/build-power-probe.yml`. It only reads battery registry
properties; it does not activate ALS, modify battery settings, or install a daemon.
The sampler also has explicit `--get-brightness` / `--brightness` test controls
using the mobile preference service. They change only plugin brightness preferences;
sampling itself remains read-only. Direct plist edits did not reliably update the
running preference cache. Measurements and device identifiers must remain in
ignored `build-packages/`.

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

For the user's requested 15-minute test, shorten phases to 225 seconds each and
sample every ten seconds. Still exclude the first minute of each phase. Include
driver `UpdateTime` and deduplicate identical gauge updates in analysis; ten-second
polling does not imply ten-second independent gauge updates. The local orchestration
script restores the original absent automatic preference and 400% manual preference
on exit, including interrupted exit. Confirm restored settings and live diagnostics.
`research/tools/analyze_aod_power.py` summarizes downloaded private JSONL and phase
metadata. Boundary diagnostics may lag a preference notification; only settled end
states are used to verify phases, and early transitions are excluded.

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

## Comparing 0.1.138 and 0.1.139

The previous analyzer compares automatic/manual brightness, not app revisions.
Use `research/tools/aod_version_power_capture.sh` and
`research/tools/analyze_aod_versions.py` for the revision comparison. The capture
script is uploaded as `/tmp/nnp-version-power-capture.sh`, and its native shell
syntax is checked. It refuses to start unless locked AOD, an accepted brightness
override, uncovered UI and a closed QR panel are already reported. Start it only
after the user confirms uninterrupted unplugged playback/AOD with stable light,
volume and connectivity. Never infer that physical confirmation from a single
state read. No automatic capture or version rollback has been started yet.

Each phase is 15 minutes: 91 battery samples at ten-second intervals and matching
condition checks. Exclude the initial two minutes from analysis. The condition
checks also invoke command-line plist readers and have measurement overhead;
use the same collector in both phases. Sampling observes whole-device power.
Use unique tags, for example `old138-20261006-1` and `new139-20261006-1`:

```sh
sh /tmp/nnp-version-power-capture.sh old138-20261006-1
```

The script produces samples/checks/error files under `/tmp/nnp-version-power-*`.
Keep downloaded logs in ignored `build-packages/power-measurement/`. Exit or
signals stop the finite battery sampler; existing logs are never overwritten.
Install the backup 0.1.138 for the old phase and return to 0.1.139 afterward;
respring ends AOD, so the user must re-establish it and allow thermal settling
before each phase. Do not start a sampler while waiting for user confirmation.

```sh
python research/tools/analyze_aod_versions.py OLD-samples.jsonl OLD-checks.jsonl NEW-samples.jsonl NEW-checks.jsonl
python research/tools/test_aod_versions.py
```

Eight tests verify a matched descriptive comparison, rejection of version/PID/
AOD/cover/ticket state mismatches, charging/unknown state, stale gauge updates,
condition gaps, short captures, nonfinite values, warmup exclusion, cross-phase
mismatches and within-phase thermal drift. Conditions are rejected if brightness
varies more than 2 nits, temperature varies more than 1 C within a phase, mean
brightness differs more than 2 nits or mean temperature differs more than 1 C
between phases. Require >=60 usable polls, >=10 distinct gauge update times and
>=600 seconds of sampled span after warmup. Any rejected post-warmup interval
invalidates the overall comparison instead of selectively claiming a saving.

Matched phases yield only an observed difference, not a causal savings percentage.
Human confirmation is still needed for audio/playlist/network interruptions;
short changes between ten-second condition checks can be missed. Repeated
alternating old/new phases are necessary before claiming a reproducible benefit.
Current authoritative state remains 0.1.139 installed, no active AOD and no
controlled baseline/new-version battery comparison completed.
