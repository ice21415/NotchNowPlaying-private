# Phase 6 — Locked-Visible Feasibility and Prototype

Date: 2026-09-22  
Target: iPhone 12 mini / iPhone13,1, iOS 17.1.2, RootHide  
Baseline: `main` commit `6c43599`

## Result

`UNSUPPORTED` for a genuine locked-visible presentation after a normal
physical side-button lock.

The Phase 5 awake-screen prototype remains the supported result. The target
device visibly renders the existing artwork/title/artist/progress UI while the
display is awake, but the UI disappears when the side button starts normal
display blanking. No candidate below provides a sufficiently understood,
reversible SpringBoard-local contract for keeping the built-in panel visible
without changing display policy or crossing the confirmed BackBoard HID
zero-factor boundary.

No production code or authentication behavior was changed in Phase 6.

## Evidence boundary

Phase 4B already established the relevant active path and is not repeated
here:

```text
BLS state 2/0
  → target displayMode 4/0
  → BLSHPendingUpdateDisplayMode
  → BLSHBacklightDisplayStateMachine
  → BLSHBacklightOSInterfaceProvider
  → _BKSHIDServicesSetBacklightFactorWithFadeDurationAsync
  → com.apple.backboard.hid.services / backboardd
```

For the observed lock-side transition, the provider supplies factor `0.0`.
This is a confirmed external display-service boundary and a strong
correlation with the visual blanking response. It is not proof of panel-power
removal, and this phase does not attempt to alter or suppress it.

## Candidate evaluation

### 1. Existing SpringBoard `UIWindow` overlay

Status: `PASS` while awake; `FAIL` after physical blanking.

The current `NNPController` presents the existing `NNPView` in a noninteractive
SpringBoard window. Phase 5 device validation confirmed artwork, metadata,
progress and media updates while the display was awake. The same manual test
confirmed that a physical side-button lock causes normal display blanking and
the overlay is no longer visible.

The window is a content-layer presentation. It does not own the system
backlight transition or panel-power policy. Increasing its window level would
not supply a display-power contract and was not attempted.

### 2. `SBLockScreenManager` / `isUILocked`

Status: `PASS` for observation only; `UNSUPPORTED` for display retention.

`NNPLockStateController` reads `SBLockScreenManager`'s `isUILocked` state and
uses it to reconcile the existing UI. This preserves lock enforcement but does
not provide a lock-screen rendering lease, wake lease, or permission to change
the physical display transition. No method on this observation path was used
as a presentation override.

### 3. `PreventUserIdleDisplaySleep` / display assertion

Status: `FAIL` for this target and use case.

Phase 2E created a valid ordinary `PreventUserIdleDisplaySleep` assertion and
released it through its normal timeout/cleanup path. The target still turned
the panel off after explicit physical lock. Therefore idle-sleep prevention is
not equivalent to suppressing explicit lock blanking. Repeating or extending
that assertion would not be new evidence and would violate the safety cutoff
for this phase.

### 4. Native ambient / Always-On presentation path

Status: `UNSUPPORTED` for this tweak and target.

Static research identified SpringBoard's native ambient branch, including
`SBScreenSleepCoordinator`, `_shouldPresentAmbientOnSleepAndLock`,
`SBAlwaysOnSettings`, and `SBBacklightPlatformProvider` capability/policy
state. The evidence shows a hardware- and policy-gated native path, not a
general third-party presentation API. The exact AOD request/state and its
panel-power policy were not recovered as a safe client contract. Existing
research also records no native AOD capability for this iPhone13,1 target.

The presence of selectors or fields containing “AlwaysOn” is not evidence that
NotchNowPlaying can opt in. No ambient controller, private assertion, or AOD
policy object was instantiated.

### 5. BLS assertions (`currentDisplayStateAssertion`, `disableAODAssertion`)

Status: `UNSUPPORTED` / insufficiently understood.

The recovered objects show assertion storage and invalidation concepts, but the
factory attributes, entitlement requirements, lifetime, exact effect, and
relationship to panel visibility are unresolved. `disableAODAssertion` is
more naturally an inhibition of AOD policy than a positive keep-visible lease.
Constructing or retaining one would be an unvalidated system-policy change, so
it was not attempted.

### 6. Scene settings / `bls_setBlanked:`

Status: `FAIL` as a physical-display mechanism.

Phase 4B statically identified scene-state propagation through
`FBSMutableSceneSettings bls_setBlanked:`. That is scene bookkeeping/state
propagation, not a proven panel-power or display-service control. A scene
setting cannot be promoted to a locked-visible mechanism without new causal
evidence below the established boundary; no scene setting was modified.

### 7. BKS display setters and zero-factor override

Status: `REJECTED` by safety constraints.

`BKSDisplayServicesSetDisplayBlanked`,
`BKSDisplayServicesSetBlankingRemovesPower`, direct BackBoard HID calls, and
suppression/rewriting of the zero-factor request would alter system display
policy or the normal sleep transition. They are outside the allowed prototype
boundary and were not called.

### 8. External-display cover-sheet path

Status: `FAIL` / external-only.

Phase 4 research identified the relevant SpringBoard BKS callers under
`SBExternalDisplayCoverSheetController`. Their external-display role does not
provide a built-in iPhone panel presentation mechanism and was not reused.

## Prototype decision

No isolated Phase 6 prototype was added. `NNPDisplayController` therefore
remains the side-effect-free feasibility boundary from Phase 5:

```objc
- (BOOL)isLockedVisibleSupported; // NO
```

The compile-time flag remains disabled in normal builds:

```text
NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE=0
```

The existing media/UI/lock-state implementation is unchanged. The existing
Phase 5 GitHub Actions workflow remains the build path and explicitly builds
with the experimental flag disabled.

## Validation matrix

| Validation | Result | Evidence |
|---|---|---|
| Source review at latest main | `PASS` | Controllers, Phase 4B/5 records, workflows reviewed |
| RootHide compilation | `PASS` baseline | GitHub run `35723934048` |
| Package installation | `PASS` baseline | Target package `com.user.notchnowplaying` 0.1.2 installed |
| SpringBoard injection | `PASS` baseline | UI appeared after respring |
| Awake-screen UI | `PASS` | Artwork, metadata and progress rendered |
| Media updates | `PASS` | Existing Phase 5 manual playback validation |
| Normal physical lock behavior | `PASS` | Display blanked normally; lock remained enforced |
| UI after physical blanking | `FAIL` for objective | Overlay was no longer visible |
| Genuine locked-visible behavior | `UNSUPPORTED` | No safe presentation/panel contract |
| Authentication/lock bypass | `NOT ATTEMPTED` | Explicitly out of scope |

## Rollback

No Phase 6 package was produced and no device state was changed. The current
package can be removed with the normal package manager if required. Keep
`NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE=0`; the existing awake-screen package
has no display-service mutation to undo.

## Stop condition and next step

The stop condition is reached: the remaining candidates either fail on the
target, belong to native hardware/policy-managed AOD, are semantically
unresolved private assertions, are external-display-only, or require exactly
the unsupported display-system modifications prohibited by this phase.

Do not continue into generic backboardd/driver/panel-power reverse engineering
unless the research scope is explicitly changed to a separate passive study.
For NotchNowPlaying, preserve the stable awake-screen prototype and report
locked-visible as `UNSUPPORTED`.
