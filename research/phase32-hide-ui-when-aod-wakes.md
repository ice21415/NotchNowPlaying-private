# Phase 32 — Hide the Player When Pseudo-AOD Wakes

Date: 2026-09-26
Target: iPhone 12 mini (`iPhone13,1`), iOS 17.1.2 (21B101), RootHide
Status: implementation prepared; device verification pending

## Cause

The Phase 31 visibility rule used the locked-visible session's `Active`
lifecycle as its AOD signal. That lifecycle remains active when the screen is
woken to show the normal Lock Screen, so the player could remain visible during
the wake/unlock flow even though the display was no longer in the dimmed AOD
presentation.

## Change

Track the dimmed AOD presentation separately from the longer-lived locked
session. The existing SpringBoard backlight wake hook clears that presentation
state and synchronously hides the UI and removes its Cover Sheet blackout.
Subsequent dim-factor substitution while still locked marks AOD presentation
active again, allowing the UI to return only after the dimmed state resumes.
Logical unlock also clears the AOD state and hides the UI immediately before
the normal asynchronous reconciliation.

Diagnostics now record `Phase7AODPresentationActive` independently of
`LockedVisibleLifecycle`, so a wake should show `NO` while the lock session can
remain `Active`.

## Verification

Build with the Phase 7 GitHub Actions workflow and confirm arm64e architecture.
On device, enter pseudo-AOD and confirm the player appears; wake the screen and
confirm the player and blackout disappear on the normal Lock Screen; let the
screen return to dimmed pseudo-AOD and confirm the player appears again; then
unlock and confirm it stays hidden.
