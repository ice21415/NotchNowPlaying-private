# Phase 31 — Show the Player Only During Active Pseudo-AOD

Date: 2026-09-25
Target: iPhone 12 mini (`iPhone13,1`), iOS 17.1.2 (21B101), RootHide
Status: implementation prepared; device verification pending

## Behavior

With Experimental Locked Visible enabled, the player UI now requires all of
the existing media and preference checks plus a locked device and an Active
display lifecycle. Spotify playback by itself no longer makes the UI appear
while the phone is unlocked, or while the locked-visible experiment is merely
Preparing. When the backlight-factor substitution activates the pseudo-AOD
session, the display controller notifies the main controller and the UI is
reconciled into the Cover Sheet.

The experiment is armed in the background while eligible music is playing and
the device is unlocked, provided lock-screen display is enabled. Hiding the UI
does not disarm it. Losing playback, disabling the tweak, disabling lock-screen
display, or unlocking the phone stops the experiment through the existing
reconcile path.

## Safety and diagnostics

The display lifecycle callback only schedules the controller's existing main
queue reconciliation; it does not change SpringBoard's lock state or issue
backlight requests. Cover Sheet cleanup now handles the pre-AOD case where no
plugin window has been created yet. Reconcile diagnostics include eligibility,
visibility, lock state, and lifecycle state, making it possible to confirm
that `Preparing` stays hidden and `Active` becomes visible.

## Verification

Build with the pinned current Apple toolchain in the Phase 7 GitHub Actions
workflow. On device, play Spotify while unlocked and confirm the player stays
hidden; press the side button and confirm it appears only after the display
lifecycle reaches `Active`; unlock and confirm it hides.
