# Phase 30 — Keep the Unlock Transition Clear

Date: 2026-09-25
Target: iPhone 12 mini (`iPhone13,1`), iOS 17.1.2 (21B101), RootHide
Status: implementation prepared; device verification pending

## User-visible issue

After the Lock Screen was revealed for wake, an upward unlock swipe briefly
showed a black overlay. The overlay disappeared as SpringBoard finished
showing the Home Screen.

## Change

The Cover Sheet host now has a passive `UIPanGestureRecognizer` observer. It
only begins for a predominantly upward swipe that starts in the bottom 28%
of the screen while logically locked. It allows simultaneous recognition,
does not cancel touches, and does not change the gesture's destination.

When that swipe begins, the tweak marks the unlock transition pending,
reveals the native Lock Screen, keeps both blackout masks hidden if the
Cover Sheet is reattached during the animation, and changes the plugin
window's locked presentation background to transparent. Logical lock and
authentication state remain owned by SpringBoard. The pending state clears
when the lock observer reports a lock-state change.

The added diagnostic key `CoverSheetUnlockTransitionPending` and event
`COVERSHEET upward swipe from bottom detected` make it possible to confirm
whether the observer sees the gesture. Device verification is pending.
