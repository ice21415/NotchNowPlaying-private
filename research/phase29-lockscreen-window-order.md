# Phase 29 — Lock Screen Window and Scene Diagnosis

Date: 2026-09-25  
Target: iPhone 12 mini (`iPhone13,1`), iOS 17.1.2 (21B101), RootHide  
Input: user photo `IMG_3859.HEIC` after the Phase 28 experiment

## Photo finding

The photographed display shows the iOS Lock Screen: the lock glyph, status
indicators, bottom flashlight and camera controls, and home indicator are
visible. No NotchNowPlaying artwork, title, artist, or progress is visible.
The panel is still faintly emitting light. The photo is consistent with the
reported later full dim/off transition and does not show a Safe Mode screen.

This confirms that suppressing the BacklightServices-originated CA blank
request did not replace the regular Lock Screen with the plugin's AOD view.
It does not by itself distinguish a SpringBoard window layered above the
plugin from the plugin window being attached to a different scene.

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

The read-only diagnostic package is version `0.1.16`. It retains the Phase 28
60-second experiment bound and the exact BKS blank-request filter. Runtime
collection on the device remains pending.
