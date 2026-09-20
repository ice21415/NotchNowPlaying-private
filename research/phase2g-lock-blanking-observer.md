# Phase 2G — Lock / Blanking Observer

Target: iPhone13,1 / D52gAP, iOS 17.1.2 (21B101)

## Observer availability

| Surface | Type | Registration succeeded | Callback observed | Confidence |
|---|---|---:|---:|---|
| `com.apple.springboard.hasBlankedScreen` | Darwin notification-compatible name | YES | YES, twice | CONFIRMED for this SpringBoard observer |
| `com.apple.backboardd.display-disabled` | Darwin registration accepted; likely internal display-disabled notification name | YES | NO | STRONG that no callback occurred during the captured cycle; type/payload unresolved |
| `com.apple.backboardd.backlight.changed` | Darwin notification-compatible name | YES | YES, twice | CONFIRMED for this SpringBoard observer |
| `backboardd.display-blanking` | Static backboardd notification/string surface; not registered in this run | NOT TESTED | NOT TESTED | CONFIRMED as a binary string only |

The observer used `CFNotificationCenterGetDarwinNotifyCenter()` and only registered callbacks. It did not post, suppress, or alter any notification. The two observed names produced callbacks, proving that they are usable as Darwin notification names from this injected SpringBoard process. Lack of a `display-disabled` callback does not prove that the name is never posted; its payload/type and posting conditions remain unresolved.

## Runtime classes

The observer used `NSClassFromString`, `class_getInstanceMethod`, and `class_getClassMethod` only. It did not instantiate or invoke any of the probed classes/selectors.

| Class | Present | Relevant selectors | Invoked? |
|---|---:|---|---:|
| `SBBacklightController` | YES | class `sharedInstance`; instance `screenIsOn`; `setIdleTimerDisabled:forReason:` absent | NO |
| `SBLockScreenManager` | YES | class `sharedInstance`; instance `isUILocked` | NO by the observer; existing read-only lock polling used the already-working selector |
| `BKDisplayBrightnessController` | NO | none available through Objective-C runtime | NO |
| `BKBacklightClient` | NO | none available through Objective-C runtime | NO |
| `BKDisplayBlankingObserver` | NO | none available through Objective-C runtime | NO |
| `BLSBacklight` | YES | class `sharedBacklight`; `registerForBacklightUpdates` absent on this class | NO |

The runtime result is specific to the SpringBoard process and this iOS 17.1.2 image. A class absent from SpringBoard may still exist in backboardd or another process.

## Lock timeline

The captured preference events used both wall time and monotonic milliseconds. The observer's SpringBoard PID was 3569.

```text
sequence  monotonic ms  wall time                 event
1         13680968      2026-09-20 07:50:43      OBSERVER_STARTED
2         13680978      2026-09-20 07:50:43      LOGICAL_LOCK=0
3         13681979      2026-09-20 07:50:44      LOGICAL_LOCK=0
4         13702518      2026-09-20 07:51:04      com.apple.backboardd.backlight.changed
5         13702619      2026-09-20 07:51:05      com.apple.springboard.hasBlankedScreen
6         13702980      2026-09-20 07:51:05      LOGICAL_LOCK=1
7         13703716      2026-09-20 07:51:06      com.apple.springboard.hasBlankedScreen
8         13703720      2026-09-20 07:51:06      com.apple.backboardd.backlight.changed
9         13704980      2026-09-20 07:51:07      LOGICAL_LOCK=0
```

Relative ordering in this observed cycle:

```text
backlight.changed
  → hasBlankedScreen
  → logical lock = 1
  → hasBlankedScreen
  → backlight.changed
  → logical lock = 0
```

The two initial `LOGICAL_LOCK=0` records are startup polling records, not a second lock cycle. The observer marked itself completed after seeing `LOGICAL_LOCK=1` followed by `LOGICAL_LOCK=0`. It then stopped collecting events.

This ordering does not establish causality. In particular, the logical-lock poll interval was one second, while Darwin callbacks arrived asynchronously. The exact physical lock-button timestamp and notification payload were not captured.

## Physical observation

```text
Panel visibly off: not independently timestamped in this observer run
Closest software events: 07:51:05–07:51:06 backlight/hasBlankedScreen callbacks
```

The observer did not use invasive panel-state detection. No exact causal event is claimed. Phase 2E independently established that the panel becomes fully dark after explicit lock on this device.

## BackBoard state

No `BKDisplayIsDisplayBlanked` or `BKDisplayIsDisabled` query was invoked. Although static backboardd evidence contains those names, a safe SpringBoard client ABI and entitlement contract were not confirmed in Phase 2G.

Observed coarse notification state:

| State surface | Observation |
|---|---|
| Backlight | Two `com.apple.backboardd.backlight.changed` callbacks |
| Display blanking | Two `com.apple.springboard.hasBlankedScreen` callbacks |
| Display-disabled | No callback for `com.apple.backboardd.display-disabled` |
| Brightness | Not queried or modified |

## SpringBoard state

Logical lock was read using the existing `SBLockScreenManager` / `isUILocked` polling path. The observer recorded the transition from `LOGICAL_LOCK=1` to `LOGICAL_LOCK=0` and then marked the one-shot experiment complete.

Runtime introspection found:

* `SBBacklightController` exists and exposes `screenIsOn`.
* `SBBacklightController` does not expose `setIdleTimerDisabled:forReason:` on this runtime.
* `SBLockScreenManager` and `isUILocked` exist.
* `BLSBacklight` exists, but the inspected update-registration selector is not on that class.

No class was instantiated by the observer, and no control selector was invoked.

## Candidate control boundary

**D — no safe control boundary identified.**

The runtime observer establishes that SpringBoard can passively receive two display/backlight notification names, but it does not expose a verified client token or transaction that can delay or suppress explicit lock blanking. `SBBacklightController`'s legacy idle-timer selector is absent, and the BackBoard classes/control symbols remain daemon/internal surfaces.

## Recommended Phase 2H

No display-control experiment should be performed automatically. The safest conclusion for this primary device is that continuous pseudo-AOD should not proceed through direct display mutation or BackBoard daemon hooks.

If a future Phase 2H is approved, it should first validate a separately documented, entitlement-supported client API on a disposable/test device. It must not use `BKDisplaySetDisplayBlanked`, `BKDisplaySetDisabled`, `setBacklightLocked:forReason:`, BackBoard MIG requests, or alternate IOPM assertions merely because the names appear in static metadata.

## Safety

Confirmed:

* no display mutation
* no power assertion
* no brightness change
* no powerd injection
* no backboardd injection
* no MobileGestalt change
* no lock-security modification
* one passive lock/wake/unlock cycle collected
* observer stopped after completion

The observer package was diagnostic-only. No setter, display query, BackBoard request, brightness API, or lock interception was used.
