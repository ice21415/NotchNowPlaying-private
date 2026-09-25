# Phase 29 — Lock Screen Window and Scene Diagnosis

Date: 2026-09-25  
Target: iPhone 12 mini (`iPhone13,1`), iOS 17.1.2 (21B101), RootHide  
Input: user photo `IMG_3859.HEIC` after the Phase 28 experiment

## Photo finding

The photographed display shows the iOS Lock Screen: the lock glyph, status
indicators, bottom flashlight and camera controls, and home indicator are
visible. No NotchNowPlaying artwork, title, artist, or progress is visible.
The panel is still faintly emitting light. The user reports the latest attempt
looks the same as the photo. Neither shows a Safe Mode screen.

This confirms that suppressing the BacklightServices-originated CA blank
request did not replace the regular Lock Screen with the plugin's AOD view.
The runtime window-order data below shows the plugin view is in the same scene
but behind the Lock Screen window.

The Phase 28 60-second bound ends the experiment and restores the BKS blank
overlay when the device is still locked. That matches the later transition to
a fully black display in the user's report. No watchdog or Safe Mode was
reported for this trial.

## Read-only instrumentation

The next diagnostic build records, at the locked presentation snapshot:

* each connected `UIWindowScene` role, activation state, key window class, and
  window count;
* every visible window, ordered by descending `windowLevel`, with its class,
  key/opacity/visibility state, frame, scene role/state, root controller class,
  and already-loaded root subview count;
* whether the plugin view is attached to its own window and the class, frame,
  visibility, and alpha of its child views.

This only reads public UIKit scene/window properties and logs class names and
geometry. It does not enumerate private view hierarchies, modify the lock
screen, change the display mode, or alter BacklightServices state. The next
attended short test should distinguish an inactive/wrong scene from a visible
Lock Screen window with a higher UIKit level. If the lock surface is outside
the enumerated UIKit windows, static research must identify a safe, existing
SpringBoard presentation container before attempting any hierarchy change.

## Build

The read-only diagnostic package was version `0.1.16`. Captured runtime data
confirms there is one application scene and that the plugin view and its music
content are visible and attached. The visible window order is
`SBCoverSheetWindow` at level `1050`, secure wallpaper at `1035`, then the
plugin `UIWindow` at `1001`. The Cover Sheet is the key window and uses
`SBCoverSheetPrimarySlidingViewController` as its root controller. This
explains why UIKit reports the plugin UI as visible while it is absent from
the photographed screen.

GitHub Actions run `36122268374` passed on macOS 26 with Xcode `26.6`, Apple
Clang `21.0.0`, and iPhoneOS SDK `26.5`. The workflow compiled the arm64e
package and passed its architecture and deployment-target inspection. Version
`0.1.16` was installed over `0.1.15`, followed by `/usr/bin/sbreload`. The
device readback reported `TweakLoaded=1`, SpringBoard PID `3847`, and
`ExperimentalLockedVisible=1`.

## Phase 30 — bounded Cover Sheet attachment experiment

Version `0.1.17` adds an opt-in presentation path for the Phase 7 experimental
build. Once the existing dimmed-lock experiment is active, the controller
looks only in its own scene for a visible, exact `SBCoverSheetWindow` whose
root controller is `SBCoverSheetPrimarySlidingViewController`. It moves the
existing transparent, non-interactive `NNPView` into that controller's root
view, where the higher Lock Screen window can render it. It moves the view
back to the plugin window when eligibility ends, on hide, and during unlock.
The progress timer retries discovery if the Lock Screen window appears after
the initial lock transition.

The code does not change window levels, Cover Sheet controllers, passcode
views, BacklightServices hooks, or the existing maximum-duration behavior.
The embedding option is off by default and enabled only by the dedicated
GitHub Actions experimental build. If the private host classes differ at
runtime, diagnostics record the failed guard and leave the previous
presentation path in place.

GitHub Actions run `36124504622` passed with Xcode `26.6`, Apple Clang
`21.0.0`, and iPhoneOS SDK `26.5`. The arm64e and deployment-target checks
passed. Package `0.1.17` was installed over `0.1.16`, then `sbreload` was
invoked. The new SpringBoard startup record has PID `3939`.

After the user's lock-screen attempt, the diagnostics plist reported
`LogicalLockState=1`, `UIVisible=1`, `LockedVisibleLifecycle=3` (active),
`CoverSheetPresentationActive=1`, and
`CoverSheetPresentationHost=SBCoverSheetPrimarySlidingViewController`. The
plugin view was attached to `SBCoverSheetWindow`; the user independently
confirmed the playback UI is now visible over the same dim Lock Screen.
The active experiment's timer was configured for 60 seconds, so this build
still returns to the system's normal display-off behavior at its configured
maximum duration.

## Phase 31 — black Lock Screen surroundings

Version `0.1.18` adds a black view over the Cover Sheet root and a 40-point
black strip over the status bar window. The NNP player view is kept above the
Cover Sheet mask. Tapping the player area toggles the native Lock Screen
controls and status icons so the user can reveal the passcode UI when needed;
unlocking or ending the experiment removes both masks. The black view also
blocks touches on the hidden Flashlight and Camera corners, while allowing
other Lock Screen gestures through. The display backlight factor is unchanged,
so the entire panel, including the player pixels, still follows the existing
dimmed factor.

This is an OLED-oriented mask: hidden Lock Screen pixels become black while
the player artwork and text remain rendered. It does not hide unrelated
higher-level system alert or recording-indicator windows. Device validation
of mask visibility and the reveal paths is pending.

## Phase 32 — reveal Lock Screen during the unlock swipe

Version `0.1.19` also reveals the native Lock Screen when the user starts an
upward gesture in the bottom-center part of the display. The mask then lets
that same touch continue to SpringBoard so the normal swipe-to-unlock or
passcode flow can proceed. Touches on the hidden bottom-corner Camera and
Flashlight controls remain blocked. Tapping the player area remains an
alternative reveal path.
