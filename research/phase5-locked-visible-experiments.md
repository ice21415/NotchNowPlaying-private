# Phase 5 — Locked-Visible Experiments

Date: 2026-09-22  
Target: iPhone 12 mini, iOS 17.1.2, RootHide

## Safety boundary

The production default remains:

```text
NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE 0
```

No passcode, Face ID, authentication, lock-state enforcement, BackBoard
display setter, backlight-factor call, panel-power policy, wake assertion, or
unrelated daemon injection is used by Phase 5.

Phase 4B established the active built-in display path as:

```text
BLS state 2/0
  → target displayMode 4/0
  → BLSHPendingUpdateDisplayMode
  → BLSHBacklightDisplayStateMachine
  → BLSHBacklightOSInterfaceProvider
  → _BKSHIDServicesSetBacklightFactorWithFadeDurationAsync
  → com.apple.backboard.hid.services / backboardd
```

The observed lock-side input is factor `0.0`. This identifies the first
external display-service boundary, but does not prove whether panel power is
retained. Phase 5 therefore stops at a read-only feasibility conclusion.

## Milestone 1 — Safe awake-screen prototype

### Implementation and files changed

- `NNPController.m`: retains the existing lock-state and MediaRemote
  observation flow; presents the existing `NNPView` with an OLED-black window
  background while logically locked; cleans up the overlay and progress timer
  when the feature is no longer eligible.
- `NNPDisplayController.h/.m`: adds explicit lifecycle states:
  `Disabled`, `Idle`, `Preparing`, `Active`, `Stopping`, `Unsupported`, and
  `Failed`. Start/stop operations are idempotent and do not touch display
  services.
- `Makefile`: adds `NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE`, default `0`.

The repository's `NNPView` and `NNPMediaController` are the current names of
the components referred to as `NNPNowPlayingView` and
`NNPMediaRemoteController` in the phase request.

### Expected behavior

With the display already awake and the device on the lock screen, active
allowed playback presents artwork, title, artist, and progress on an OLED
black background. MediaRemote track changes update the existing view. Stopping
playback or disabling the feature hides it and invalidates its timer. Unlock
and SpringBoard reload restore ordinary control flow. This is an awake-screen
prototype only; it is not Always-On Display and makes no claim about manual
side-button blanking.

### Actual runtime observations

Not run on the target device in this workspace. Source-level inspection shows
the existing observers and cleanup path remain intact. Device validation must
separately record compilation, SpringBoard injection, UI rendering, logical
lock-state correctness, and physical display visibility.

### Result

`PASS` for the safe, awake-screen architecture by inspection.  `NOT VERIFIED`
for target-device UI behavior until the existing RootHide deployment workflow
is run.

### Known limitations

The UI is hosted by a SpringBoard `UIWindow`; the OS may hide it when the
physical display blanks. It is not a panel-power or Always-On mechanism.

### Rollback

Build with the default flag (`NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE=0`),
disable the preference, or remove the package and reload SpringBoard. No
display state is changed by this milestone.

### Next evidence-backed step

Run the existing known-good RootHide build/deploy workflow while the display is
awake, then verify track changes, progress updates, playback-stop cleanup,
unlock cleanup, and SpringBoard reload recovery. Do not treat that result as
proof of post-blanking visibility.

## Milestone 2 — Locked-visible feasibility

### Implementation

`NNPDisplayController` returns `NO` from `isLockedVisibleSupported` and records
`Unsupported` when asked to start. The experimental controller calls are
compile-time gated and default off. Unsupported start and repeated stop are
safe no-ops; no BLS/BKS/BackBoard display operation is invoked.

### Expected behavior

The normal awake-screen prototype remains available. Enabling the experimental
flag cannot claim success or alter display/panel-power policy. An unsupported
experiment leaves normal lock behavior untouched.

### Actual observations and result

`UNSUPPORTED`: Phase 4B found no sufficiently understood, supported and
reversible SpringBoard-local mechanism that can keep the built-in panel
visible after the system's lock-side zero-factor handoff. The exact missing
capability is a safe presentation/display-power contract below the confirmed
`com.apple.backboard.hid.services` boundary. The research explicitly does not
replace that call, forge BLS transitions, call BKS setters, force wake, or
modify panel-power policy.

### Rollback

Leave `NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE=0`. If a diagnostic build was
made with the flag enabled, unload it or rebuild with the default and reload
SpringBoard. The implementation performs no persistent display mutation.

### Next evidence-backed step

Only a separately scoped, passive observation below the BackBoard HID service
boundary could resolve the remaining panel-power question. Until such
evidence exists, preserve this awake-screen prototype and do not pursue the
already-ruled-out display-mode or zero-factor override paths.
