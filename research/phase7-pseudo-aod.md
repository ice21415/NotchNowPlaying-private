# Phase 7 — Experimental Pseudo-AOD for NotchNowPlaying

Date: 2026-09-22  
Target: iPhone 12 mini / iPhone13,1, iOS 17.1.2, RootHide  
Baseline: `main` commit `a9d7f1e`

> **Latest status (user-reported device test, 2026-09-22):** The Phase 7 experimental build compiled and installed successfully. On a normal side-button press, the phone remained logically locked while the display stayed visible; album artwork and song information continued updating on track changes, and the progress bar continued moving. Unlock/recovery was normal. The display retained the pre-lock screen content rather than transitioning to an AOD-only black scene. The configured 30-second timeout was **NOT TESTED**. See [Phase 7 device-test addendum](#phase-7-device-test-addendum--user-reported-results-2026-09-22). Earlier `NOT TESTED` / `UNSUPPORTED` statements below describe the state **before** this device test and are superseded for observed visibility, not for timeout, privacy, or panel-power details.

## Current status

```text
Milestone A — display-path feasibility: EXPERIMENTAL CANDIDATE
Milestone B — minimal visibility prototype: NOT TESTED
Milestone C — Now Playing integration: NOT TESTED
Milestone D — reliability: NOT TESTED
Overall pseudo-AOD objective: NOT TESTED
```

The Phase 5 awake-screen implementation remains the stable result. Phase 7
now contains an isolated, opt-in candidate for device testing; it has not yet
been installed or validated on the target. It is intentionally not claimed as
pseudo-AOD until the manual side-button test produces evidence.

The device remains securely locked throughout the existing validation. No
passcode, Face ID, authentication, or lock-state enforcement behavior was
changed.

## Existing confirmed boundary

Phase 4B and Phase 6 already established the relevant path; it is not
repeated here:

```text
BLS state 2 → target displayMode 4
BLS state 0 → target displayMode 0
  → BLSHPendingUpdateDisplayMode
  → BLSHBacklightDisplayStateMachine
  → BLSHBacklightOSInterfaceProvider
  → _BKSHIDServicesSetBacklightFactorWithFadeDurationAsync
  → com.apple.backboard.hid.services
  → backboardd
```

The observed lock-side factor is `0.0`. A nonzero factor would only be a
brightness input; it is not evidence that the panel remains powered or that a
SpringBoard `UIWindow` will be composited after blanking. No factor was
rewritten.

## Milestone A — candidate mechanisms

### SpringBoard UIWindow / lock-screen overlay

Result: `PASS` while awake, `FAIL` after physical lock blanking.

The existing `NNPController` creates a noninteractive SpringBoard window and
the existing `NNPView` renders artwork, title, artist and progress. Phase 5
device validation showed correct rendering and media updates while the panel
was awake. The same test showed that a normal side-button lock blanks the
display and the overlay is no longer visible.

Ownership: SpringBoard content/window layer.  It does not own the display
blanking or panel-power decision. A higher `UIWindow` level would not create a
display-power lease and was not treated as a pseudo-AOD mechanism.

### `SBLockScreenManager` / `isUILocked`

Result: `PASS` for observation; `UNSUPPORTED` for retention.

`NNPLockStateController` reads the logical lock state and reconciles UI state.
This preserves authentication and lock enforcement. It provides no documented
or evidence-backed visible-after-blanking lease, so no override was added.

### `PreventUserIdleDisplaySleep` and ordinary display assertions

Result: `FAIL` on the target.

Phase 2E successfully created and released a normal idle-display assertion,
but the iPhone 12 mini still blanked the panel after explicit physical lock.
This mechanism prevents idle sleep, not the lock-triggered display transition.
Repeating it would not be new evidence.

### `SBScreenSleepCoordinator` ambient/AOD path

Result: `UNSUPPORTED` as a third-party mechanism.

Existing static evidence identifies `_shouldPresentAmbientOnSleepAndLock`,
`SBAlwaysOnSettings`, `SBBacklightPlatformProvider` capability/policy state,
and an ambient presentation controller. These are native AOD policy surfaces,
not a general client API. The target is iPhone13,1 and existing research found
no native LTPO/AOD capability path for it. The exact ambient request and its
panel-power policy were not recovered as a safe opt-in contract.

The existence of names containing “AlwaysOn” does not establish that this
tweak can enable them. No ambient controller or AOD assertion was acquired.

### `useAlwaysOnBrightnessCurve:withRampDuration:`

Result: `INSUFFICIENT EVIDENCE` as a general mechanism; `EXPERIMENTAL CANDIDATE`
for a bounded proof-of-concept only.

Phase 4B identified this selector on the platform-provider side and treated it
as brightness-policy work. The existing passive trace recorded the provider
and selector metadata, but did not establish a lock-side runtime call with a
known input/output effect. Even if called, a brightness curve does not prove
panel power or compositing after blanking.

The Phase 7 candidate does not invoke the brightness-curve selector. It uses
the already receiver-proven BLS provider method as a bounded mode-substitution
experiment described below. This does not establish panel power in advance.

### BLS assertions (`currentDisplayStateAssertion`, `disableAODAssertion`)

Result: `UNSUPPORTED`.

The objects and lifecycle names are known, but their attributes, entitlements,
factory contract, lifetime, and physical display effect are unresolved.
`disableAODAssertion` is not evidence of a positive keep-visible lease. Creating
one would be a private system-policy change without a predictable rollback
contract, so it was not attempted.

### Scene state and `bls_setBlanked:`

Result: `FAIL` as a visibility mechanism.

Phase 4B identified `FBSMutableSceneSettings bls_setBlanked:` as scene-state
propagation. It is not a proven panel-power control and does not establish
that content survives physical blanking. No scene settings were changed.

### BackBoard HID factor / BKS display services

Result: `REJECTED` for this implementation.

The direct HID service is the first confirmed external boundary, but replacing
the zero factor, suppressing the request, calling BKS display setters, or
changing blanking/power policy would modify the system display transition.
It would also lack proof that the panel remains powered and would complicate
recovery on failure. These operations were not called or hooked.

### External-display cover-sheet path

Result: `FAIL` / not applicable.

The recovered BKS callers are owned by `SBExternalDisplayCoverSheetController`.
That path is for external displays and is not a built-in iPhone pseudo-AOD
mechanism.

## Milestone B — minimal visibility prototype

Implementation: `NNPPhase7PseudoAOD.xm` is compiled only when
`NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE=1`. It passively records the live
`BLSHBacklightOSInterfaceProvider` receiver and, only while the user preference
`ExperimentalLockedVisible` is enabled, substitutes a lock-side
`transitionToDisplayMode:0` call with mode `4`. Mode `4` is the previously
observed awake-side target mode; this is a test input, not a semantic claim
that mode `4` means “panel on”.

The controller arms while eligible playback is active so the hook is armed
before the physical side-button transition. It has a 5–60 second configurable
maximum duration (default 30 seconds). On stop, unlock, playback stop,
preference disable or timeout it disarms and requests the normal mode `0`
transition when the device is logically locked. All calls are diagnostic and
fail closed when the provider/selector is unavailable.

Status: `NOT TESTED` on device.

Known risk: mode `4` may represent a normal brightness/policy state rather
than an ambient state. Battery, heat and OLED retention may increase during
the bounded experiment. Do not leave the experiment enabled unattended.

## Milestones C–D decision

The minimal candidate is not yet validated. Consequently:

- no minimal visible test element was implemented;
- no media integration changes were made;
- no repeated lock/unlock or notification reliability experiment was run;
- the experimental package is separate from production and is not installed;
- production `NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE` remains `0`;
- `NNPDisplayController -isLockedVisibleSupported` remains `NO`.

This is an intentional stop at the evidence boundary, not a compilation-based
claim of success.

## Build and deployment

The existing `.github/workflows/build-phase5.yml` remains the production
baseline workflow and explicitly builds with:

```text
NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE=0
```

The production baseline rebuild completed successfully in GitHub Actions run
`35726881401` (34 seconds), with the experimental flag disabled. The separate
`.github/workflows/build-phase7-experimental.yml` workflow is the only allowed
build path for the candidate. It must produce a distinct artifact before any
device deployment. No experimental package has yet been built or installed.

Validation separation:

| Property | Phase 5 baseline | Phase 7 |
|---|---|---|
| Compilation | `PASS` | `NOT TESTED` — no code change |
| Installation | `PASS` | `NOT TESTED` |
| SpringBoard stability | `PASS` | `NOT TESTED` |
| Logical lock state | `PASS` / preserved | `NOT TESTED` |
| Awake UI visibility | `PASS` | `NOT TESTED` |
| Post-lock physical visibility | `FAIL` for objective | `UNSUPPORTED` |
| Genuine pseudo-AOD | `UNSUPPORTED` | `UNSUPPORTED` |

## Risks and recovery

The experimental package has not yet been deployed. After deployment, the
recovery path is: disable `Experimental Locked Visible`, stop playback, unlock
the device, wait for the configured maximum duration if needed, and respring
if the display does not return to normal. Reinstall the production artifact
with the flag at `0` as the final rollback. No thermal protection,
authentication state or system file is intentionally changed.

A future experiment would require, at minimum, a bounded duration, an explicit
user setting, conservative brightness, lock/unlock and SpringBoard-reload
cleanup, and evidence that the mechanism is not merely a nonzero brightness
request. Until those are available, battery, heat and OLED retention risks
make an unverified pseudo-AOD hook unsuitable for deployment.

## Remaining blocker

The missing capability is an evidence-backed, target-compatible presentation
and panel-visibility contract that can survive the normal lock-side transition
while leaving the device securely locked. Finding that contract would require
new evidence below or within the BackBoard display-policy boundary. Generic
driver or panel-power reverse engineering is outside this phase's scope.

## Phase 7 device-test addendum — user-reported results (2026-09-22)

This section records the tester's direct report after the earlier research snapshot. It is **user-reported runtime evidence**, not a fresh CI log, device diagnostic capture, or independent verification of panel power. Historical statuses earlier in the report reflect the pre-deployment state; this addendum supersedes them where directly tested.

### Test environment and observations

Target as defined by this report: iPhone 12 mini (iPhone13,1), iOS 17.1.2, RootHide. The user reported the following for the Phase 7 experimental build:

| Test | Result | User observation / limitation |
| --- | --- | --- |
| Experimental build and installation | `PASS (USER REPORTED)` | Compiled and installed successfully; workflow/run ID not supplied. |
| Ordinary side-button lock | `PASS (USER REPORTED)` | Phone remained logically locked while the display stayed visibly on. |
| Album artwork and song information visible | `PASS (USER REPORTED)` | Artwork and song details remained visible after locking. |
| Track change while locked | `PASS (USER REPORTED)` | Artwork and title updated to the new track. |
| Playback progress while locked | `PASS (USER REPORTED)` | Progress bar continued moving. |
| Return to normal behavior | `PASS (USER REPORTED)` | User reported normal recovery. Pressing again brought up the normal lock screen. |
| Configured 30-second timeout | `NOT TESTED` | User has not yet checked whether the display blanks and normal mode is restored at timeout. |
| Privacy-safe AOD-only scene | `FAIL / NOT IMPLEMENTED` | Immediately after locking, the display retained the pre-lock screen content instead of switching to a dedicated black-background AOD scene. |
| Panel power-rail state, thermal behavior, long-run reliability | `NOT VERIFIED` | No measurement or prolonged test was supplied. |

### Interpretation

This is **not merely a frozen final frame**: track metadata/artwork and the playback progress continued updating while the phone was reported locked. It is evidence of a working *experimental locked-visible, live-updating presentation* on the tested device. It does **not** establish genuine native AOD, panel-power behavior, or safe all-day operation.

The principal functional/privacy gap is that normal pre-lock screen content remains visible after the first side-button press. A subsequent press shows the ordinary lock screen according to the user. Treat this as a privacy concern rather than a completed AOD presentation: do not enable it over sensitive content while this behavior remains.

### Updated milestone status

```text
Milestone A — display-path feasibility:  PASS for experimental visibility on target (user report)
Milestone B — visible, live-updating prototype: PASS (user report)
Milestone C — Now Playing rendering/updates: PASS with existing UI (user report)
Milestone D — privacy-safe scene, timeout and reliability: INCOMPLETE
Overall pseudo-AOD experiment: PARTIAL PASS; not production-ready
```

### Next bounded validation

1. Verify the configured 30-second timeout and normal display restoration, without leaving the display unattended.
2. Resolve the retained pre-lock content before treating this as a privacy-safe AOD-like interface. The desired post-lock scene contains only the black background and NotchNowPlaying elements.
3. Separately verify normal lock-screen access, playback-stop cleanup, repeated lock/unlock, and crash/recovery behavior. Record build/run identity and device diagnostics with future results.

Do not relabel this result as native AOD or claim that the physical OLED panel's power state is known.
