# AOD power optimizations (0.1.111)

User selected diagnostic writes, adaptive ambient sampling and intermittent title
marquee. Progress/lyrics update intervals remain unchanged. Pixel shifting and
brief pixel-rest blanking remain enabled on all plugin presentation roots.

## Diagnostics

State values are coalesced for 0.5 seconds on the existing serial queue, with the
latest value winning per key. Equal values are discarded. A burst performs one
CFPreferences synchronization instead of one per individual value. Batch/PID and
duplicate counters are published in that same synchronization for verification.
Basic hook, presentation and brightness state remains available; detailed transition
logs, call stacks, observer events and per-sample timing are disabled by default.
Use `NNP_ENABLE_VERBOSE_DIAGNOSTICS=1` or the workflow's verbose input for debugging.
Existing historical diagnostic keys/logs are not deleted and must not be mistaken
for fresh data after respring. The Foundation CI test checks coalescing, latest-value
semantics, unchanged-value suppression and disabled detailed logging.

## Ambient light

One-shot timer starts at five seconds and changes to 15 after three stable samples,
then 30 after five. Stability compares brightness against an anchored target,
allowing max(0.75 nits, 1.5% of target); cumulative drift beyond that range resets
the interval to five seconds. Invalid samples also reset the policy. A sudden
lighting change is detected at the next scheduled sample, so stable-mode response
can take about 30 seconds plus timer tolerance; this is the explicit tradeoff.
The existing continuous 6–180 nits curve and 24-step fade are unchanged.
Exit invalidates the timer and releases the client/service. Generation checks
discard old callbacks and restart an interrupted activation sample safely.
The shared C policy tests exercise stability, cumulative drift, darkness and invalid
data alongside charging/AOD eligibility and all pixel-shift positions.

## Title marquee

Overflowing titles retain the same linear 30 points/second scrolling and duplicated
text for a seamless full pass. Each pass removes itself on completion, followed
by a 20-second one-shot idle timer. No CA render animation remains during idle.
A weak delegate proxy and generation checks prevent retain cycles and stale
completions after track/width changes, playback hiding or removal from a window.
The idle timer is invalidated on cancellation/deallocation. Reduced-motion support
continues to show a static title. Short titles never create the cycle.

These changes reduce redundant work by design; battery savings have not yet been
quantified. Previous comparisons measured automatic versus manual brightness and
cannot establish the savings from this revision.

## Build and deployment verification

GitHub Actions run 36973718703 passed both normal and AOD Apple arm64e builds,
the shared C policy tests, and the Foundation batching test. Installed the AOD
0.1.111 package (SHA-256 33215ac5af452d954d3d904de1b6e434f85db3ae262b47094a8c3a84b42451ee).
SpringBoard PID 12363 reported two startup batches for 48 changed values and 15
skipped duplicates, with verbose diagnostics disabled. At the post-install check
the AOD pixel-shift timer was inactive and the new sample-interval/marquee keys had
not yet been created; old ambient-active/lux keys were retained historical data.
Do not treat those as proof of a new sensor session. User visual and active-AOD
adaptive-interval checks are pending.

## 0.1.139 first reduction pass (2026-10-06)

Baseline is functional 0.1.138. Backup directory outside the repository:
`backups/NotchNowPlaying-0.1.138-before-power-20261006`, containing all-ref bundle,
tracked source, installed AOD package and phone preferences. Package hash matches
`98e585138e5c2c1f31531b48d33cf6583b70537f3c6da0aa869a238ad90a06b5`.

Audit found these ongoing sources: progress/lyrics at the configured interval,
ALS reads at 2/3/5 seconds, cover accelerometer at 2 Hz, 30-second OLED rest,
Spotify recovery at 1 Hz, and ordinary digitizer sensor mode for the QR button.
QR preflight is only every 30 minutes while AOD is active; QR image renewal and
1 Hz countdown only run while its panel is open. The status-bar player mirror is
clipped to the top 40 points but contains visible notch metadata, so it cannot
be deleted as an entirely invisible duplicate without changing presentation.

First pass keeps all feature and brightness timing unchanged:

- Disabled verbose log calls no longer evaluate message formatting or stack
  arguments at their call sites. Exported implementations remain available and
  verbose builds retain the calls. CI exercises argument side effects in both
  release and verbose modes.
- ALS diagnostic lux/target timestamps are reported every 30 seconds, immediately
  on validity changes and on each activation; actual sensor processing and the
  continuous brightness ramp still run on every sample. Diagnostic target values
  are snapshots, not live readings; consult AODAmbientDiagnosticTimestamp for age.
  Pure C tests cover cadence, invalid/recovery transitions and clock rollback.

Do not infer a battery percentage improvement from these changes. The most
important unmeasured suspect is ordinary digitizer mode; removing it would break
working AOD QR interaction. Cover detection, pixel rest, brightness response and
Spotify track recovery must be preserved until alternatives are verified.

User was asked whether an uninterrupted unplugged 15-minute baseline is possible.
No controlled measurement has started without that physical-state confirmation.

Before installing 0.1.139, additionally filter tiny brightness target changes.
Previously any >=0.5-nit change could schedule the 24-step ramp plus readbacks.
Use max(0.75 nits, 1.5% of current/target) against the last accepted target;
zero-to-positive and positive-to-zero mode changes bypass this filter. The
sampling intervals, lux curve, brightness limits and linear ramp remain unchanged.
C tests verify cumulative drift, both mode transitions, large lighting changes
and a synthetic +/-0.8-nit jitter sequence (60 old ramp requests versus zero new).
That simulation demonstrates reduced requests for this input, not measured power.
