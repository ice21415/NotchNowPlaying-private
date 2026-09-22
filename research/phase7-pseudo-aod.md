# Phase 7 — Experimental Pseudo-AOD for NotchNowPlaying

Date: 2026-09-22  
Target: iPhone 12 mini / iPhone13,1, iOS 17.1.2, RootHide  
Baseline: `main` commit `a9d7f1e`

## Final status

```text
Milestone A — display-path feasibility: UNSUPPORTED
Milestone B — minimal visibility prototype: NOT TESTED
Milestone C — Now Playing integration: NOT TESTED
Milestone D — reliability: NOT TESTED
Overall pseudo-AOD objective: UNSUPPORTED
```

The Phase 5 awake-screen implementation remains the stable result. No Phase 7
runtime display modification was deployed because no candidate had all of the
required properties: identifiable ownership, understood input contract,
reversible lifecycle, and evidence that it preserves actual OLED visibility
after the normal lock-side blanking transition.

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

Result: `INSUFFICIENT EVIDENCE` → `UNSUPPORTED` for implementation.

Phase 4B identified this selector on the platform-provider side and treated it
as brightness-policy work. The existing passive trace recorded the provider
and selector metadata, but did not establish a lock-side runtime call with a
known input/output effect. Even if called, a brightness curve does not prove
panel power or compositing after blanking.

No hook or synthetic invocation was added.

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

## Milestones B–D decision

No candidate passed Milestone A. Consequently:

- no minimal visible test element was implemented;
- no media integration changes were made;
- no repeated lock/unlock or notification reliability experiment was run;
- no private display hook was enabled in a package;
- `NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE` remains `0`;
- `NNPDisplayController -isLockedVisibleSupported` remains `NO`.

This is an intentional stop at the evidence boundary, not a compilation-based
claim of success.

## Build and deployment

The existing `.github/workflows/build-phase5.yml` remains the production
baseline workflow and explicitly builds with:

```text
NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE=0
```

No experimental Phase 7 package was built or installed because no experimental
controller implementation was justified. The previously validated baseline
run `35723934048` remains the package/injection reference. Any future
candidate must receive a separate workflow and artifact identity before device
deployment.

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

No Phase 7 display modification was deployed, so there is no new low-level
rollback state. The stable recovery path is to keep the experimental flag at
`0`, disable the tweak through preferences, or remove the Phase 5 package and
respring. No thermal protection, panel-power policy, authentication state or
system file was changed.

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
