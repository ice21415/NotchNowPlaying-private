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
