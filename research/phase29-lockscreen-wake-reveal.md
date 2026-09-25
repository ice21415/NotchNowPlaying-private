# Phase 29 — Reveal Lock Screen on Wake

Date: 2026-09-25
Target: iPhone 12 mini (`iPhone13,1`), iOS 17.1.2 (21B101), RootHide
Status: implementation prepared; device verification pending

## User-visible issue

After waking the screen with the side button while the pseudo-AOD overlay was
active, the black Cover Sheet mask remained in place. The user had to tap near
the bottom of the display before the native Lock Screen became visible.

## Change

The Phase 7 hook now observes SpringBoard's existing
`SBBacklightController setBacklightState:source:animated:completion:` method.
Phase 17's static reconstruction identifies state `1` as the full-brightness
path and state `3` as the ordinary sleep-side path. The replacement calls the
original method with every argument unchanged. It only sends a UI reveal when
all of these conditions hold:

* the experimental pseudo-AOD is armed;
* SpringBoard still reports the device locked;
* a BacklightServices-originated blank request was suppressed for this lock
  session; and
* SpringBoard is entering backlight state `1`.

On that event, the tweak hides the opaque Cover Sheet and status-bar masks so
the native Lock Screen is visible for authentication. The existing bottom-
center touch reveal remains available if the backlight callback does not run.
The BKS unblank path also reveals the Lock Screen when it follows a suppressed
lock blank request.

Diagnostics record `Phase7WakeHookInstalled`, the SpringBoard state/source,
and `COVERSHEET ... reason=side-button-wake`. Installation or runtime delivery
of the wake event has not yet been confirmed on-device.

## Safety scope

This change does not change the selected backlight state, animation, source,
completion block, lock state, authentication state, or the original BKS
blank/unblank result. It changes only the visibility of the tweak's own
Cover Sheet masks after a qualifying wake. Build and device verification are
pending.
