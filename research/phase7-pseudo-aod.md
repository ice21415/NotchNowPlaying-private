# Phase 7 — Experimental Pseudo-AOD for NotchNowPlaying

Date: 2026-09-22  
Target: iPhone 12 mini / iPhone13,1, iOS 17.1.2, RootHide  
Baseline: `main` commit `a9d7f1e`

> **Latest status (user-reported device test, 2026-09-22):** The Phase 7 experimental build compiled and installed successfully. On a normal side-button press, the phone remained logically locked while the display stayed visible; album artwork and song information continued updating on track changes, and the progress bar continued moving. Unlock/recovery was normal. The display retained the pre-lock screen content rather than transitioning to an AOD-only black scene. The configured 30-second timeout was **NOT TESTED**. See [Phase 7 device-test addendum](#phase-7-device-test-addendum--user-reported-results-2026-09-22). Earlier `NOT TESTED` / `UNSUPPORTED` statements below describe the state **before** this device test and are superseded for observed visibility, not for timeout, privacy, or panel-power details.

> **Follow-up observation (user-reported, 2026-09-23; terminology corrected in Phase 7.5):** After the first side-button lock, the *entire* retained screen, including the NotchNowPlaying UI, becomes extremely dim, resembling the lowest possible brightness, and cannot be interacted with. The native volume HUD still appears when using the hardware volume buttons, but it is also extremely dim. A second side-button press immediately shows the normal iOS lock screen. Media artwork/title and progress continue updating. Earlier references to a “gray screen” describe this same low-brightness physical appearance, not a confirmed gray overlay or color transform. The owner and implementation are **NOT IDENTIFIED**. The physical panel sleep/power state remains **UNVERIFIED**. The 30-second timeout is still **NOT TESTED**. See [follow-up observation addendum](#follow-up-observation-addendum--2026-09-23).

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

## Phase 7.1 checkpoint — gray-screen investigation baseline

Checkpoint: the latest Phase 7 implementation before Phase 7.1 changes is
preserved at commit `2ccf5be` (`phase7.1-baseline-before-gray-diagnosis`). The
existing opt-in display-mode substitution and the Traditional Chinese
PreferenceLoader settings are unchanged at this checkpoint.

The user subsequently reported these attended device observations while the
experimental setting was enabled: after the first physical side-button press,
the device behaved as logically locked and did not accept normal interaction,
but the entire visible display became gray, including NotchNowPlaying. Artwork,
metadata and playback progress continued updating. The native volume HUD also
appeared with the same gray appearance. A second side-button press immediately
showed the normal iOS lock screen. The configured 30-second timeout was not
observed in that test.

These observations establish a display-wide symptom but do not identify its
owner. In particular, they do not distinguish SpringBoard composition from a
system-managed presentation layer or downstream display processing. No
security-critical component was changed in response to the observation.
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

## Phase 7 follow-up observation addendum — 2026-09-23

This section records a second round of **user-reported device observations**. The tester has not supplied a screenshot pair, compositor trace, brightness telemetry, or a confirmed timeout result. This addendum refines the earlier Phase 7 device-test interpretation rather than replacing the original observations.

### Exact observed sequence

1. Phase 7 experimental build was previously reported compiled and installed successfully.
2. With the existing Now Playing UI active, pressing the physical side button leaves the device apparently logically locked and the screen visibly updating, but **the entire pre-lock screen becomes gray and touch interaction is unavailable**. The gray appearance affects the plugin as well as the rest of the screen.
3. Using the hardware volume buttons produces the native system volume HUD. **The HUD is also gray, appearing beneath the same apparent gray effect**. This is evidence of ongoing system UI rendering, not proof of an overlay window's identity or z-order.
4. Artwork and song title update after a track change and playback progress continues to move. Therefore this is not a frozen last frame.
5. Pressing the side button a second time **immediately** displays the ordinary iOS lock screen (no reported intervening black frame).
6. The configurable **30-second timeout is NOT TESTED**. No physical panel power or thermal measurement has been reported.

### Revised evidence matrix

| Question | Result | Evidence limit |
| --- | --- | --- |
| Live rendering after first side-button press | `PASS (USER REPORTED)` | Track information and progress update; volume HUD renders. |
| Logical lock and input behavior | `USER REPORTED` | Screen cannot be tapped; second press shows lock screen. These observations alone do not independently prove all authentication invariants. |
| Whole-screen gray appearance | `CONFIRMED (USER REPORTED)` | Plugin, background and system volume HUD are all affected. |
| Gray effect caused by a top-level overlay | `HYPOTHESIS — UNVERIFIED` | Could be composited dimming, a presentation layer or a display-wide brightness/color process. No owner, window identity or stacking order is proven. |
| Display-wide brightness/color processing | `HYPOTHESIS — UNVERIFIED` | Consistent with native volume HUD also turning gray, but no brightness/color telemetry or screenshot comparison yet. |
| Dedicated black AOD scene | `FAIL / NOT IMPLEMENTED` | Previous app/screen content remains visible and gray, creating a privacy concern. |
| Normal lock screen on second side-button press | `PASS (USER REPORTED)` | Appears immediately. |
| Timeout / failsafe / thermal / panel-power state | `NOT TESTED / NOT VERIFIED` | Do not infer hardware state from visible UI. |

### Revised interpretation and next experiment

Treat Phase 7 as a **live-rendering locked-visible experiment with unexplained global gray appearance**, not as a finished pseudo-AOD presentation. A single alleged topmost gray `UIWindow` is only one candidate; the report does not establish whether the native volume HUD is under an overlay or whether the entire display output is transformed.

The next milestone should be **read-only diagnosis before any additional display-mode changes**. On a non-sensitive test screen and during a short attended test, compare normal-awake and experimental gray-mode screenshots and their on-device visual appearance. If captured screenshots show normal colors while the panel appears gray, prioritize downstream display/color/brightness hypotheses; if the captured screenshot itself is gray, prioritize compositor/window/scene or screen-capture-path color transforms. Either result is narrowing evidence, not proof of exact ownership. Examine existing SpringBoard presentation/window/scene and brightness observations without hiding or disabling security-critical lock-screen components.

Before treating this as usable, verify that the intended timeout restores normal display behavior, and design the final black-background scene so the retained previous app screen never remains visible after locking. Do not publish the current experimental presentation as privacy-safe.

## Phase 7.1 — gray-screen diagnosis and privacy-safe presentation

### Milestone A — preserved checkpoint

Status: `PASS`.

The pre-change Phase 7 state is preserved by tag
`phase7.1-baseline-before-gray-diagnosis` and commit `1041ef6`. The existing
experimental `NNPPhase7PseudoAOD.xm` display-mode substitution was not removed
or rewritten during this investigation. Production builds continue to use
`NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE=0`; the Phase 7 workflow remains a
separate opt-in build.

### Milestone B — read-only gray-screen diagnosis

Status: `PASS` for instrumentation; `NOT TESTED` for a new device capture.

`NNPController` now records, without changing system state:

* logical lock/unlock transition reason;
* count of visible and opaque SpringBoard windows;
* connected scene count;
* whether `UIScreen.brightness` is nonzero;
* the NotchNowPlaying window's visibility and opacity;
* the presentation root view's opacity.

The diagnostic log does not record artwork, titles, application content,
coordinates of other windows or authentication data. It does not remove or
hide any unidentified system window. These observations can narrow whether a
future screenshot is normal in the compositor but gray on the physical panel,
or already gray in the captured composition; they cannot by themselves name
the system owner of the effect.

Current evidence remains:

| Hypothesis | Evidence | Status |
| --- | --- | --- |
| A NotchNowPlaying window alone causes the gray screen | Native volume HUD is also gray; no window owner was identified | `NOT SUPPORTED` |
| A system-managed dimming/presentation layer affects the composition | Whole screen and HUD are affected | `PLAUSIBLE / NOT PROVEN` |
| Display-wide brightness or color processing affects output | Whole-screen symptom is consistent with it | `PLAUSIBLE / NOT PROVEN` |
| The experimental display-mode transition interacts with normal lock blanking | Timing correlation exists; no passive trace proves the exact owner | `PLAUSIBLE / NOT PROVEN` |

No BKS setter, HID factor replacement, BLS transition suppression, scene
blanking override or authentication component was added.

### Milestone C — screenshot comparison

Status: `NOT TESTED`.

The bounded next test is an attended comparison using the same non-sensitive
static screen: capture it while normally awake, enable the experimental setting
with Now Playing active, capture after the first physical side-button press,
and separately record how the physical panel looks. A normal-color capture with
a gray physical panel would favor downstream display processing; a gray capture
would favor composition or capture-path processing. Neither outcome alone
identifies a specific component. No screenshot or pixel comparison has been
claimed yet.

### Milestone D — dedicated privacy-safe presentation

Status: `PASS` in implementation; `NOT TESTED` on device.

The existing NNP window remains the only tweak-owned presentation, but the
experimental path now makes it an opaque, full-screen black presentation while
the experiment is active or the device is logically locked. Its root view and
`NNPView` are also opaque black, and the content hierarchy contains only the
existing artwork, title, artist and progress elements. No previous application
view or screenshot is copied into the hierarchy. This intentionally makes the
opt-in experimental screen black even before the physical lock transition so
that a polling delay in lock-state observation cannot leave the previous app
content as the presentation background.

The implementation preserves the normal lock screen and authentication path;
it does not claim that the system's gray output is solved. If the system applies
a display-wide effect after composition, the dedicated black source may still
appear gray on the physical panel.

### Milestone E — lifecycle and rollback

Status: `PASS` in code review; `NOT TESTED` for the new build on device.

The existing bounded maximum-duration stop, playback-stop cleanup, unlock
cleanup and idempotent display lifecycle remain in place. The new diagnostic
state is passive. Rollback is to disable `實驗性鎖定顯示`, stop playback and
respring; if necessary reinstall the stable Phase 5 package built with the
experimental flag set to `0`. No persistent system display policy is written.

### Phase 7.1 build/runtime status

| Validation | Result |
| --- | --- |
| Source/static review | `PASS` |
| Production configuration unchanged | `PASS` |
| Experimental compilation | `NOT TESTED` after Phase 7.1 changes |
| Package installation | `NOT TESTED` after Phase 7.1 changes |
| SpringBoard stability | `NOT TESTED` after Phase 7.1 changes |
| Dedicated black scene on target | `NOT TESTED` |
| 30-second timeout and normal restoration | `NOT TESTED` |
| Gray-screen owner | `UNSUPPORTED / NOT IDENTIFIED` |
| Privacy-safe pseudo-AOD completion | `UNSUPPORTED` pending device validation |

The Phase 7.1 experimental workflow was dispatched at GitHub Actions run
`35803792090` for commit `f4b2159`, but GitHub did not start a runner: the job
had zero steps and was rejected because the account's recent payment failed or
its spending limit must be increased. A retry had the same result. The stable
Phase 5 workflow was also dispatched as run `35803862259` against the same
commit and was rejected before its first step for the same account-level
reason. Therefore this is `NOT RUN / BLOCKED`, not a compiler failure. No
Phase 7.1 package was installed after this change.

Static validation completed: `git diff --check` passed, the production flag
remains disabled, and the experimental source path remains isolated behind the
existing compile-time and user-controlled settings.

After the repository was intentionally made public, the standard macOS runner
became available. Experimental workflow run `35804226513` compiled the
arm64e RootHide package successfully after the iOS 17 SDK diagnostics fix.
The resulting `com.user.notchnowplaying_0.1.2_iphoneos-arm64e.deb` was copied
to the target device, installed with `dpkg -i`, and SpringBoard was restarted
with `sbreload`; the remote command returned success. This establishes
`PASS` for compilation, package transfer, installation and respring only. It
does not establish the dedicated black scene, timeout, gray-screen diagnosis
or privacy-safe pseudo-AOD behavior.

The target-device test status after this deployment is still `NOT TESTED` for
the new Phase 7.1 behavior.

The next bounded step is to build the separate experimental package, install it
only for a short attended test, collect the new passive diagnostics, perform the
non-sensitive screenshot comparison, and verify timeout plus lock/unlock and
playback-stop cleanup. Stop immediately on abnormal heat, display behavior or
loss of normal lock-screen behavior.

## Phase 7.2 — premature black presentation correction

### Newly reported regression

The Phase 7.1 device test identified a regression: starting playback while the
device was unlocked immediately changed the entire tweak-owned window to opaque
black, leaving only NotchNowPlaying visible and preventing ordinary use of
other applications. The same test continued to report live artwork, metadata
and progress after the first side-button lock, while the complete display still
appeared gray. The gray symptom remains a separate issue from the premature
black presentation.

### Cause

`NNPDisplayController` correctly entered its experimental `Active` lifecycle
state as soon as eligible playback and the opt-in setting were present. In
`NNPController -applyLockedBackground`, the Phase 7.1 implementation treated
`lifecycleState == Active` as sufficient to select an opaque black background.
Because the controller arms before the physical side-button transition, that
condition became true during ordinary unlocked playback. This was a state
management error: “experiment armed” was conflated with “device is logically
locked and should use the dedicated black presentation.”

### Correction

Status: `PASS` in source review; device confirmation `NOT TESTED`.

The dedicated black background now depends only on the observed logical lock
state (`self.locked`). The experimental controller may still arm before the
side-button transition so the existing live locked-visible path is preserved,
but arming or playing music no longer makes the presentation opaque while
unlocked. When the lock observer reports unlock, the controller stops the
experiment and restores the transparent, nonintrusive presentation. No window
is removed, no system lock-screen layer is modified, and no authentication
behavior is changed.

This deliberately leaves a short observation-delay boundary: the black scene
starts when the existing lock-state observer reports logical lock, not by
guessing from a side-button event. The delay is recorded as a lifecycle/UI
timing limitation rather than addressed by modifying security-critical lock
components.

### Gray-output diagnosis status

Status: `NOT TESTED` for screenshot comparison; `UNSUPPORTED / NOT IDENTIFIED`
for exact owner.

The read-only diagnostic path remains unchanged. The required attended test is
to capture the same non-sensitive static content while normally awake and
again after the first physical side-button press with the experimental build,
while separately recording the physical panel appearance. A normal-color
system capture with a gray physical panel favors downstream display output
processing; a gray system capture favors composition or capture-path
processing. Either result narrows the hypotheses but does not identify a
specific system layer. The native volume HUD being gray remains evidence
against the NNP window alone being the source.

### Phase 7.2 validation matrix

| Validation | Result |
| --- | --- |
| Cause identified from Phase 7.1 source | `PASS` |
| Unlocked playback remains nonintrusive | `NOT TESTED` after correction |
| Experimental live update after lock preserved | `NOT TESTED` after correction |
| Gray-screen screenshot comparison | `NOT TESTED` |
| Logical lock/authentication behavior | `NOT TESTED` after correction |
| Unlock cleanup and transparent restoration | `NOT TESTED` after correction |
| Production build flag remains disabled | `PASS` |
| Privacy-safe pseudo-AOD completion | `UNSUPPORTED` pending device validation |

The next bounded step is separate production and experimental compilation,
followed by a short attended device test: verify normal use of another app
while unlocked, then verify one lock transition, live media updates, unlock
cleanup and the screenshot comparison. Do not classify the presentation fix as
successful until the unlocked playback test passes on the target device.

### Phase 7.2 build and deployment addendum

The separate production workflow completed successfully as run
`35804823114`, and the separate experimental workflow completed successfully
as run `35804825427` for commit `2e95c56`. The experimental arm64e package was
downloaded, copied to the target device, installed with `dpkg -i`, and
SpringBoard was restarted with `sbreload`; the remote command returned success.
These are `PASS` for compilation, package transfer, installation and respring.
The target-device behavior checks remain `NOT TESTED` until the attended
unlocked-playback and post-lock screenshot comparison are performed.

## Phase 7.2 device-result correction — user report

The user subsequently tested the deployed Phase 7.2 package. These results
supersede the earlier `NOT TESTED` entries for the corresponding behaviors:

| Test | Result | Observation |
| --- | --- | --- |
| Normal unlocked playback | `PASS` | Playback works normally. |
| Other applications while unlocked | `PASS` | The premature full-screen black regression was not present in ordinary unlocked use. |
| Restoration after unlocking | `PASS` | Normal behavior returned. |
| Dedicated black background after physical lock | `FAIL` | The intended black-only scene was not visible. |
| Previous application content after lock | `CONFIRMED` | Original content remained visible. |
| Whole-screen gray output | `CONFIRMED` | NotchNowPlaying and the entire display became gray. |
| Live metadata/artwork/progress after lock | `PASS` from earlier tests | The live update capability remains established by prior attended tests. |
| 30-second timeout | `NOT TESTED` | No timeout result supplied. |

The native volume HUD was also reported gray, and a second side-button press
showed the normal iOS lock screen. These results do not identify a specific
window, scene or display-processing owner.

## Phase 7.3 — lock-state reconciliation and gray-screen investigation

### Confirmed starting state

The Phase 7.2 source correction successfully addressed the unlocked playback
regression, but it did not produce a dedicated black scene after the first
physical lock. The strongest current possibilities are: the lock observer
does not observe the relevant transition; it observes it after system
composition has already changed; `self.locked` changes without a subsequent
reconcile; the tweak window becomes opaque but is obscured by a system surface;
or the display-mode substitution causes the system to retain/composite the
existing application content. The gray volume HUD keeps a tweak-owned window
alone from being a sufficient explanation.

### Instrumentation added

Status: `PASS` in source review; runtime collection `NOT TESTED`.

The diagnostic layer now creates compact transition identifiers (`T1`, `T2`,
...) and records a timestamped sequence without media content or credentials.
The sequence covers:

* `NNPLockStateController` startup and `SBLockScreenManager isUILocked` changes;
* `NNPController self.locked` changes and unchanged-state callbacks;
* reconcile eligibility and display lifecycle state;
* `NNPDisplayController` lifecycle transitions, arming, timeout and stopping;
* every `applyLockedBackground` call with expected black state, actual window
  visibility, window level, window/root opacity, visible/opaque window counts,
  scene count and nonzero screen-brightness observation;
* window show/hide cleanup;
* Phase 7 provider display-mode requests, mode substitution and restore calls.

The diagnostic path does not log artwork, song titles, application content,
credentials or authentication state. A hardware side-button press is not
claimed as independently observed; only the existing logical lock observer
event is labeled as observed.

### Gray-screen comparison

Status: `NOT TESTED`.

No screenshot pair or diagnostic session from the Phase 7.2 test was supplied.
The required attended comparison remains the same non-sensitive screen while
normally awake and after the first physical side-button press. If a system
screenshot remains normal while the physical panel is gray, downstream
brightness/color processing becomes stronger evidence. If the captured image is
gray, compositor/window/scene or capture-path processing becomes stronger
evidence. Neither result alone identifies an exact system component. If a
screenshot cannot be captured in the experimental state, that limitation must
be recorded and the transition log used instead.

### Phase 7.3 status

| Validation | Result |
| --- | --- |
| User-reported unlocked playback | `PASS` |
| User-reported other-app usability while unlocked | `PASS` |
| User-reported dedicated black scene after lock | `FAIL` |
| User-reported original content retention | `CONFIRMED` |
| User-reported whole-screen gray output | `CONFIRMED` |
| Source-level transition instrumentation | `PASS` |
| Production configuration unchanged | `PASS` |
| Production compilation after instrumentation | `PASS` — workflow `35805459044` |
| Experimental compilation after instrumentation | `PASS` — workflow `35805461385` |
| Experimental package transfer, installation and respring | `PASS` — deployed to target after workflow `35805461385` |
| Runtime diagnostic sequence | `NOT TESTED` |
| Screenshot comparison | `NOT TESTED` |
| Exact gray-screen owner | `UNSUPPORTED / NOT IDENTIFIED` |
| Phase 7.3 completion | `UNSUPPORTED` pending runtime evidence |

No display-mode substitution, BackBoard HID factor, BLS transition or
authentication behavior was changed in this diagnostic milestone. Recovery is
to disable the experimental setting, stop playback, unlock, and respring; the
stable production build remains the rollback path. The next bounded step is to
build and deploy this instrumentation, collect one short attended transition
log, and compare the actual window state at logical lock with the physical gray
appearance before considering any further display experiment.

### Phase 7.3 runtime-results addendum — first capture attempt

#### Package and collection

The target reported package `com.user.notchnowplaying` version `0.1.2` as
installed. The Phase 7.3 arm64e dylib was present at the expected RootHide
DynamicLibraries path after the deployment of workflow `35805461385`.

An attended capture was started at approximately device time `09:21 CST` on
2026-09-23 using the targeted
`/var/mobile/Library/NotchNowPlaying/load-path-diagnostic.log` path. The user
then performed the requested unlocked playback, first side-button lock,
second side-button press and unlock sequence. The file logger did not create
either its primary or fallback log file.

#### Available runtime evidence

The diagnostics plist was updated during/after the test and downloaded from
`/var/mobile/Library/Preferences/com.user.notchnowplaying.diagnostics.plist`.
The post-test values included:

```text
TweakLoaded = true
StartupTimestamp = 2026-09-23 01:16:04 +0000
UIVisible = true
LogicalLockState = false
PresentationWindowVisible = true
PresentationWindowOpaque = false
PresentationRootOpaque = false
PresentationDedicatedBlack = false
LockedVisibleLifecycle = 1 (Idle)
PresentationVisibleWindowCount = 9
PresentationOpaqueWindowCount = 5
PresentationConnectedSceneCount = 1
PresentationScreenBrightnessNonzero = true
Phase7ModeSubstitution = true
Phase7SubstitutedDisplayMode = 4
```

These are final/post-unlock state values, not a timestamped first-lock
sequence. They show that the tweak was loaded and that cleanup left the
presentation transparent and idle, but they do not establish whether the
black presentation was requested or visible at the first logical lock.
The plist also contained older blanking-observer records from previous runs;
they were not attributed to this session.

#### Classification

The first capture is `INSUFFICIENT EVIDENCE` for Cases A–D. The missing
capability is a recoverable per-event transition history: the file logger is
unavailable on this deployment and the existing scalar plist values only keep
the latest state. No code or display-path fix is justified by this capture.

#### Diagnostic collection correction

The logger now keeps a bounded `DiagnosticLogEvents` array (maximum 256
entries) in the existing diagnostics plist as a fallback whenever file writes
are unavailable. Entries contain only timestamp, process, PID and the tweak's
own diagnostic event text; no media metadata, application content,
credentials or authentication information is recorded. This is a diagnostic
instrumentation correction, not a display behavior change. It requires a new
build and one repeat attended test before classifying the lock presentation
failure.

### Phase 7.3 runtime-results addendum — Relaxin injection state

The user identified that Relaxin appears to have automatically disabled tweak
injection after the display incident. This explains why a device can remain
reachable over SSH while the SpringBoard presentation hook is no longer active.
The diagnostic package cannot treat an SSH connection or an installed dylib as
proof of injection into the current SpringBoard process.

The follow-up read-only check found:

```text
Package version: 0.1.2
ExperimentalLockedVisible before recovery: 1
DiagnosticLogEvents: 6
Latest events: SpringBoard startup, initial logical-lock state, initial
presentation snapshot, initial reconcile and cleanup
No new logical-lock-observed event for the intended physical-button test
```

The plist startup timestamp advanced after the respring, but the event history
contained only the post-respring initial state. It did not contain the required
first-button sequence, so the prior test cannot distinguish Case A, B, C or D.
Classification: `INSUFFICIENT EVIDENCE`; injected runtime result: `NOT TESTED`.

For safety, `ExperimentalLockedVisible` was then set to `0` and SpringBoard was
resprung. No display-mode or authentication behavior was changed. The next
valid collection requires Relaxin injection to be explicitly confirmed active
in the same SpringBoard process before the user repeats the attended lock test.

## Phase 7.4 — SpringBoard watchdog root-cause analysis and fail-safe recovery

### New device evidence

Status: `CONFIRMED (USER REPORTED)`; exact incident timestamp `NOT PROVIDED`.

Relaxin reported a Watchdog Timeout with the message:

```text
no successful checkins from SpringBoard (2 induced crashes) in 180 seconds
```

The user reported that backboardd, mediaserverd, audiomxd, logd and other
listed services continued successful checkins. Relaxin then temporarily
disabled tweak injection and initiated a userspace reboot. This establishes a
SpringBoard-specific availability failure, but the watchdog message alone does
not identify the blocking function, thread or module. The previous Phase 7.3
runtime capture is therefore `INSUFFICIENT EVIDENCE` for display-state
classification and must not be used as proof of a gray-screen cause.

### Relaxin / SpringBoard report retrieval

Status: `NOT FOUND` on the authorized device connection.

Targeted read-only searches of the available mobile/root Logs, CrashReporter
and Analytics directories for SpringBoard, Relaxin, watchdog and incident
reports returned no matching file. No unrelated system log or user data was
collected. Consequently the following remain `NOT TESTED`: incident timestamp
from the report, termination reason, sampled/blocked thread, SpringBoard main
thread stack, loaded NotchNowPlaying image, repeated frames and display/
backlight frames.

### SpringBoard blocking audit

Source audit result: `FAIL` for diagnostic fail-safe design; watchdog root cause
`NOT PROVEN`.

The Phase 7.3 diagnostic fallback synchronously called
`CFPreferencesCopyAppValue`, `CFPreferencesSetAppValue` and
`CFPreferencesAppSynchronize` from `NNPDiagnosticLog`. File logging also called
`mkdir`, `open` and `write` directly from the caller. Since diagnostic logging
is reached from `NNPPhase7PseudoAOD`'s display-mode hook and lock/reconcile
paths, this was a real SpringBoard blocking risk even though no report proves it
caused the watchdog.

The audit found no `dispatch_sync` in the Phase 7 paths, no intentional wait
for BackBoard, and no recursive preference callback that is proven to loop.
`dispatch_async` media callbacks return to the main queue for UI reconciliation,
and the bounded timeout uses `dispatch_after`; these remain potential workload
sources but not synchronous waits. The display hook's restore flag was already
idempotent for its restore path; a thread-local hook guard is now added to make
re-entry fail open to `%orig`.

### Fail-safe diagnostic correction

Status: `PASS` in source review; device runtime validation `NOT TESTED`.

`NNPDiagnosticLog` now only creates a small in-memory event and schedules a
coalesced flush on a serial background queue. File `mkdir/open/write` and
bounded plist serialization occur on that queue, never in the display/lock
caller. Events are bounded to 256 and may be dropped under pressure. Scalar
diagnostic writes and blanking-event persistence are also dispatched to the
same background queue. If persistence fails, the caller continues without
waiting; normal display and authentication behavior are not held for
diagnostics.

`NNPPhase7PseudoAOD` now has a narrow thread-local reentrancy guard. The hook
does the guard check and schedules passive logging before returning through the
original implementation; restore remains idempotent and no new display hook or
BackBoard control was added. The experimental path remains behind both the
compile-time flag and the user setting. Production remains unchanged.

### Phase 7.4 status before rebuild

| Item | Result |
| --- | --- |
| Watchdog event recorded | `PASS (USER REPORTED)` |
| Exact Relaxin report retrieved | `NOT FOUND` |
| Exact blocking frame identified | `NOT TESTED` |
| Synchronous diagnostic I/O audit | `PASS — risk identified` |
| Non-blocking diagnostic correction | `PASS` in source review |
| Display-mode path changed | `NO` |
| Production compilation after correction | `PASS` — workflow `35807532171` |
| Experimental compilation after correction | `PASS` — workflow `35807534457` |
| New physical lock experiment | `NOT TESTED` |
| Gray-screen issue | `UNSUPPORTED / SEPARATE` |

The next bounded step is production and experimental compilation plus static
inspection of the generated sources. Do not repeat the physical lock test until
both builds pass and Relaxin injection is explicitly confirmed active. The next
device test must be brief, attended, and stopped immediately if SpringBoard
slows, injection is disabled, or display recovery is abnormal; it must not wait
for another 180-second watchdog event.

Both requested builds completed successfully on 2026-09-23. Static search
confirmed no `dispatch_sync` in the audited Phase 7 sources. The generated
packages were not installed and no new physical lock experiment was started
after the watchdog incident. Phase 7.4 therefore remains `NOT TESTED` for
runtime stability and `UNSUPPORTED` for gray-screen resolution.

### Phase 7.4 deployment and pre-test validation

Status: deployment `PASS`; physical lock validation `NOT TESTED`.

The previously successful experimental artifact from workflow
`35807534457` was reused. Its workflow head is `98f508b`; the code included
the watchdog correction from `cf16538`. Package inspection confirmed the
arm64e package metadata and the dylib strings for the background diagnostics
queue, `DiagnosticLogEvents` and Phase 7 transition markers. The stable
production rollback artifact from workflow `35807532171` remains available
locally.

Before installation, the target had version `0.1.2` installed, but its dylib
timestamp predated the Phase 7.4 deployment. `ExperimentalLockedVisible` was
`0`; it was not enabled during installation. The corrected package was copied
to the device and installed with `dpkg -i` without an error. SpringBoard was
restarted with `sbreload` and SSH remained responsive afterward.

Post-respring evidence:

```text
Package: com.user.notchnowplaying 0.1.2 / iphoneos-arm64e
ExperimentalLockedVisible: 0
TweakLoaded: true
SpringBoardPID: 21374
StartupTimestamp: 2026-09-23 01:51:30 +0000
DiagnosticLogEvents: 31
```

The new event history contains SpringBoard startup, lock observer startup,
initial logical-lock reconciliation and display transition observations. This
confirms that the corrected dylib loaded into the current SpringBoard process
and that the nonblocking diagnostic fallback is persisting events. A working
SSH connection alone was not used as injection evidence. Relaxin's internal
injection flag is not exposed by the available device commands, but there was
no new auto-disable/watchdog report during this installation check.

Normal unlocked playback with the experimental setting disabled: `NOT TESTED`
as a user-interaction result. No physical lock test, gray-screen comparison,
timeout test or media playback test was started after deployment. The device
is left with the experimental setting disabled pending user readiness.

### Phase 7.4 attended runtime results

Status: SpringBoard safety `PASS`; lock presentation diagnosis `PASS` for
state reconciliation; gray-output resolution `INSUFFICIENT EVIDENCE`.

After the user confirmed physical readiness, the experimental preference was
enabled and SpringBoard was restarted. A post-test diagnostic plist was copied
from the device. It contained `TweakLoaded=true`, SpringBoard PID `21487`,
startup timestamp `2026-09-23 01:57:04 +0000`, and 114 bounded diagnostic
events. The dedicated file log was not present at the attempted path, so the
plist event history was the authoritative capture for this session.

The relevant transition was reconstructed from the events around the attended
test (timestamps are device event timestamps):

```text
01:59:06.740  T1 reconcile unlocked, show=YES, experimentEligible=YES
01:59:06.740  T1 DISPLAY lifecycle state=2 (Preparing)
01:59:06.740  T1 PHASE7 armed=YES
01:59:06.740  T1 DISPLAY lifecycle state=3 (Active)
01:59:06.742  T1 window visible=YES, level=1001
01:59:13.520  T1 display transition requested mode=0; substituted 0 -> 4
01:59:20.666  T1 display transition requested mode=3
01:59:21.294  T2 logical-lock-observed
01:59:21.294  T2 isUILocked changed value=YES
01:59:21.294  T2 self.locked=YES
01:59:21.295  T2 window visible=YES, expectedBlack=YES, rootOpaque=NO
01:59:21.295  T2 reconcile locked=YES, show=YES, lifecycle=3
01:59:21.296  T2 black-presentation: windowOpaque=YES, rootOpaque=YES
01:59:30.294  T3 logical-unlock-observed
01:59:30.294  T3 self.locked=NO
01:59:30.294  T3 transparent-presentation: windowOpaque=NO, rootOpaque=NO
01:59:32.451  T3 lifecycle state=4 -> state=1; experiment stopped
01:59:32.452  T3 window visible=NO cleanup
```

This rules out Case A (lock transition not observed), Case B (state
reconciliation failure) and Case C (requested presentation never became
opaque). It does not distinguish Case D subtypes: the opaque black
SpringBoard presentation may have been obscured by a system-managed surface,
or the final physical output may have been altered downstream by the display
transition. The earlier user-observed gray screen remains historical evidence,
but this capture does not independently record its physical appearance.

| Question | Result |
| --- | --- |
| First logical lock transition observed | `PASS` |
| `self.locked` reconciled to `YES` | `PASS` |
| Black presentation requested and activated | `PASS` |
| Unlock callback and cleanup | `PASS` |
| SpringBoard responsive during short test | `PASS` — no new watchdog/auto-disable observed |
| Actual physical panel appearance in this session | `NOT TESTED` |
| Screenshot comparison | `NOT TESTED` |
| 30-second timeout | `NOT TESTED` |

The display-mode substitution was active before the logical lock callback and
the black presentation was applied after that callback. No new BackBoard/BLS
hook or display-power modification was introduced. The watchdog correction is
therefore separate from the gray-screen issue and is not claimed as its cause
or fix.

Rollback: disable `ExperimentalLockedVisible`, respring, and use the retained
production package from workflow `35807532171` if injection recovery is
needed. The attended test restored the window and experimental lifecycle on
unlock. No authentication, Face ID, passcode or normal lock-screen behavior
was modified.

Next evidence-backed step: repeat one short attended capture only if a direct
physical observation is recorded alongside the timestamped events, and add a
system screenshot comparison when capture is available. Do not change the
display-mode hook based on this session alone.

### Phase 7.5 — extremely dim, noninteractive locked-visible display

#### Corrected observation

The user clarified that the earlier term “gray screen” was imprecise. The
observed behavior is: `Extremely dim, noninteractive locked-visible display`.
After the first physical side-button press, the previous application remains
visible, the touchscreen does not accept ordinary interaction, Now Playing
content continues updating, and the hardware volume HUD is also extremely
dim. A second side-button press shows the normal lock screen and unlocking
restores normal operation. Historical Phase 7.1–7.4 “gray” descriptions are
retained as contemporaneous wording, but should be read as this low-brightness
physical observation; they do not establish a gray overlay or color transform.

#### Source review and passive diagnostic preparation

Status: source review `PASS`; diagnostic changes `PASS` in source; build and
device deployment `NOT TESTED`.

The existing Phase 7.4 display path was preserved. In particular, the mode
substitution remains the only display hook: an armed mode-0 request is passed
as mode 4, with the existing thread-local reentrancy guard and fail-open
`%orig` path. No BackBoard/HID factor hook, BLS suppression, brightness setter,
authentication change or panel-power policy change was added.

The existing Phase 7.4 window observations already prove that the tweak-owned
window and root view become opaque at the logical-lock callback. They do not
prove that this window is the final surface composited by the display service.
The source review therefore keeps presentation composition and downstream
display output as separate hypotheses.

The diagnostic preparation adds only numeric, source-labelled UIKit and scene
observations to `NNPController`:

* `UIScreen.mainScreen.brightness` is recorded as
  `PresentationUIScreenBrightness` (a UIKit value in the 0.0–1.0 range), not
  as a claim about OLED output or BacklightServices policy.
* Screen scale, the presentation scene activation state and its window count
  are recorded at each existing presentation snapshot.
* The transition log now includes the numeric UIKit brightness and scene
  state alongside display-mode requests, lock state and window opacity.
* `NNPDiagnosticSetDouble` uses the existing asynchronous bounded persistence
  path. No synchronous I/O was added to the display hook or lock callback.

No reliable BacklightServices brightness-policy numeric value is currently
available through the existing safe interfaces. UIKit brightness,
BacklightServices policy state and physical OLED output therefore remain three
distinct measurements. A nonzero UIKit value must not be interpreted as panel
visibility or native AOD brightness.

#### Evidence model for the next attended comparison

The next test is intentionally not deployed automatically. It requires an
installed diagnostic build, active SpringBoard injection and a short attended
comparison of the same non-sensitive static screen:

| Observation | Interpretation | Status |
| --- | --- | --- |
| Normal/unlocked UIKit brightness value | Baseline source measurement only | `NOT TESTED` |
| Locked-visible UIKit brightness value | Distinguishes reported UIKit state from baseline | `NOT TESTED` |
| System screenshot versus physical panel | Can separate composition/capture appearance from downstream output | `NOT TESTED` |
| Exact BacklightServices policy value | No safe numeric interface currently established | `UNSUPPORTED / NOT IDENTIFIED` |
| Previous application still visible in final composition | Composition or display-mode retention candidate | `CONFIRMED historically; new screenshot NOT TESTED` |
| Touch non-interactive while logically locked | Consistent with normal lock enforcement | `CONFIRMED USER REPORTED` |

If the screenshot retains normal colors while the physical panel is extremely
dim, downstream brightness/output processing becomes the stronger hypothesis.
If the screenshot itself retains the previous application or is dimmed, scene
composition or capture-path behavior becomes stronger. Neither result alone
proves panel power state or identifies a system-owned surface. No window will
be removed or forcibly raised solely from this comparison.

#### Phase 7.5 preparation status

| Item | Result |
| --- | --- |
| Terminology corrected | `PASS` |
| Phase 7.4 nonblocking logger preserved | `PASS` |
| Reentrancy guard preserved | `PASS` |
| New display-control hook | `NONE` |
| Numeric UIKit brightness diagnostics | `PASS` in source; `NOT TESTED` on device |
| Scene/window diagnostic extension | `PASS` in source; `NOT TESTED` on device |
| Experimental build | `PASS` — GitHub Actions run `35809721287`; arm64e artifact downloaded locally |
| Installation/injection verification | `PASS` — diagnostic deployment section below |
| Physical display comparison | `NOT TESTED` — no screenshot/photo supplied |
| Timeout and recovery | `NOT TESTED` |

The next bounded step is to compile the separate experimental diagnostic
package and inspect its artifact. Deployment and the physical side-button
comparison require explicit user readiness. Until that occurs, the exact
dimming mechanism and the reason the previous application remains visible are
`INSUFFICIENT EVIDENCE`.

#### Phase 7.5 diagnostic deployment

Status: deployment and injection `PASS`; physical display comparison `NOT
TESTED`.

The experimental arm64e artifact from GitHub Actions run `35809721287` was
copied to the target and installed with `dpkg -i` successfully. The
`ExperimentalLockedVisible` preference was explicitly kept at `0`, and
SpringBoard was restarted with `sbreload`. Post-restart evidence from the
diagnostic preference domain showed:

```text
TweakLoaded=true
SpringBoardPID=21664
StartupTimestamp=2026-09-23 02:20:31 +0000
DiagnosticLogEvents=188
ExperimentalLockedVisible=0
```

The new event history includes the numeric UIKit brightness field; one
post-install snapshot recorded `UIKitBrightness=0.4015`. This is a UIKit
measurement only and is not a BacklightServices policy value or a physical
OLED measurement. No physical lock test, screenshot comparison, timeout test
or new display-control experiment has been started after this deployment.

#### Phase 7.5 attended brightness and presentation results

Status: logical-lock and presentation instrumentation `PASS`; brightness
mechanism identification `INSUFFICIENT EVIDENCE`; dedicated privacy-safe
presentation `FAIL` for the observed physical result.

The user completed one short attended side-button comparison. The physical
behavior is recorded as the corrected description: the display became
extremely dim and noninteractive, the previous application remained visible,
Now Playing continued updating, and the hardware volume HUD was also
extremely dim. The normal lock screen appeared after the second side-button
press and normal operation returned after unlock. No second-device photograph
or system screenshot from the locked-visible interval was supplied, so the
physical/screenshot comparison is `NOT TESTED`.

The captured diagnostic sequence was:

```text
02:23:04.308  display transition requested mode=0, armed=YES
02:23:04.308  displayMode 0 -> 4
02:23:13.588  display transition requested mode=3, armed=YES
02:23:14.029  logical-lock-observed; isUILocked=YES
02:23:14.029  self.locked=YES
02:23:14.030  logical-lock snapshot: UIKitBrightness=0.4015, sceneState=0,
                sceneWindows=14, windowLevel=1001, windowOpaque=NO,
                rootOpaque=NO, expectedBlack=YES
02:23:14.030  black-presentation snapshot: UIKitBrightness=0.4015,
                sceneState=0, sceneWindows=14, windowLevel=1001,
                windowOpaque=YES, rootOpaque=YES
02:23:17.029  logical-unlock-observed; self.locked=NO
02:23:17.030  transparent-presentation restored
02:23:31.523  experiment stopped; armed=NO
02:23:31.524  window visible=NO cleanup
```

The numeric UIKit brightness value remained `0.4015` across the available
snapshots. This is evidence that `UIScreen.mainScreen.brightness` did not
reflect the user's extremely dim physical-panel observation in this test. It
does not establish the BacklightServices policy value, the actual OLED drive
level or panel power state.

The lock callback, display-mode substitution, black presentation and unlock
cleanup all executed. The tweak-owned window was in the expected scene state
with level `1001` and became opaque. Nevertheless, the physical result still
retained the previous application. This rules out a missing logical-lock
callback and a basic opacity/reconciliation failure. It does not distinguish:

* a system-managed surface above the tweak window;
* display-mode retention of an earlier application scene; or
* downstream brightness/output processing after SpringBoard composition.

The native volume HUD being extremely dim is consistent with a display-wide
or system-managed output state, but it is not proof of a particular owner.
No unidentified window was removed, no window level was increased, and no
BackBoard/HID or brightness-control hook was added.

| Result | Status |
| --- | --- |
| Experimental package installed and injected | `PASS` |
| UIKit brightness captured numerically | `PASS` — `0.4015` in captured snapshots |
| Mode 0 -> 4 substitution observed | `PASS` |
| Logical lock and secure noninteractive behavior | `PASS` user-reported / callback captured |
| Black window/root presentation activated | `PASS` |
| Previous application absent from physical display | `FAIL` |
| Extremely dim physical display | `CONFIRMED USER REPORTED`; exact mechanism `INSUFFICIENT EVIDENCE` |
| Screenshot or second-device photo comparison | `NOT TESTED` |
| BacklightServices numeric policy value | `NOT TESTED / UNSUPPORTED INTERFACE` |
| 30-second timeout | `NOT TESTED` |
| Watchdog during short test | `PASS` — no new watchdog or injection disable observed |

After collection, `ExperimentalLockedVisible` was set to `0` and SpringBoard
was restarted. Recovery was normal. The next bounded step is a screenshot plus
second-device photograph during the same short interval, if the user can
provide both. The strongest current hypothesis is a downstream system display
state that preserves rendering but applies a very low physical brightness, with
composition/surface ordering still unresolved. No speculative display-control
correction is justified by this evidence.
