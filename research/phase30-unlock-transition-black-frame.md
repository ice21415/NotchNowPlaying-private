# Phase 30 — Clear the Plugin Window at Unlock

Date: 2026-09-25
Target: iPhone 12 mini (`iPhone13,1`), iOS 17.1.2 (21B101), RootHide
Status: implementation prepared; device verification pending

## Runtime evidence

After the user reported that the black frame still appeared during an upward
unlock, the diagnostics from build 0.1.21 showed this sequence:

```text
11:29:56.919  SpringBoard backlight state=1; Lock Screen masks revealed
11:29:58.750  logical unlock observed
11:29:58.751  plugin windowOpaque=YES rootOpaque=YES
11:29:58.754  Cover Sheet presentation detached
```

The bottom-swipe observer added in 0.1.21 did not log an event. The concrete
black surface is the plugin's own full-screen window: it remained opaque
through the logical-unlock snapshot, then the asynchronous reconciliation
detached the Cover Sheet presentation and applied the transparent appearance.
This explains the black frame seen immediately before the Home Screen.

## Change in 0.1.22

When the existing lock-state observer first reads `isUILocked == NO`, the
controller now clears the plugin window, root view, and content background
synchronously before capturing diagnostics or scheduling reconciliation.
Lock-state polling now runs every 100 ms in common run-loop modes so touch and
animation tracking do not defer the observation for a full default-mode
interval.

This does not alter SpringBoard's lock state, swipe recognizers, or
authentication. The unused pan observer from 0.1.21 was removed after the
runtime trace showed it never reported the user's swipe. Device verification
is pending.
