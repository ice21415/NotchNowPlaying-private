# Phase 2H — Locked-but-Visible Display Experiment

Target: iPhone13,1 / D52gAP, iOS 17.1.2 (21B101)

## BackBoard client ABI

### Resolved functions

No safe client functions were resolved.

Static inspection confirmed these names in the copied `/usr/libexec/backboardd` image:

```text
BKDisplayIsDisplayBlanked
BKDisplaySetDisplayBlanked
BKDisplayIsDisabled
BKDisplaySetDisabled
_BKDisplaySetDisabled
```

The same image contains:

```text
BKDisplayServices MiG Server
com.apple.backboard.display.services
```

This establishes that BackBoard owns a display service and contains display blank/disable operations. It does not establish that these functions are exported by `BackBoardServices.framework` to SpringBoard, nor does it reveal their C ABI, display identifier arguments, return types, entitlement checks, or MIG message layout.

### Framework

`BackBoardServices.framework` exists in the iOS 17.1.2 sealed payload and its `Info.plist` identifies the framework executable. The executable image is in the dyld shared cache. The available development environment did not include a dyld-cache extractor or Objective-C/Mach-O metadata tool capable of recovering a trustworthy client declaration for the four names above.

### Client/daemon boundary

The strongest evidence-supported boundary is:

```text
SpringBoard / system client
        ↓ unknown BackBoardServices client ABI
com.apple.backboard.display.services (MIG endpoint)
        ↓
backboardd internal display blank/disable implementation
```

The endpoint ownership was confirmed read-only with `launchctl print` on `user/501/com.apple.backboardd`. No Mach message or XPC request was sent.

### Confidence

* **CONFIRMED:** the four names occur in the iOS 17.1.2 backboardd image.
* **CONFIRMED:** `com.apple.backboard.display.services` and `com.apple.backlightd` are active backboardd endpoints.
* **STRONG INFERENCE:** the names belong to an internal BackBoard display service implementation.
* **UNRESOLVED:** SpringBoard-callable signatures, entitlements, state semantics, and client ABI.

## Read-only state

No Phase 2H state query was invoked because the read-only client ABI was not confidently established.

| State | Result |
|---|---|
| Awake blanked | NOT QUERIED |
| Locked blanked | NOT QUERIED through `BKDisplayIsDisplayBlanked`; Phase 2E separately observed the panel fully dark after lock |
| Awake disabled | NOT QUERIED |
| Locked disabled | NOT QUERIED |
| Logical lock | Phase 2G runtime observer confirmed `SBLockScreenManager`/`isUILocked` exists and recorded one lock/unlock cycle |

Phase 2G observed these Darwin-compatible callbacks without mutating state:

```text
com.apple.backboardd.backlight.changed
com.apple.springboard.hasBlankedScreen
```

It did not receive `com.apple.backboardd.display-disabled` during that cycle.

## Runtime client-class evidence

The Phase 2G runtime observer used class/selector introspection only:

| Class | Present in SpringBoard | Relevant result |
|---|---:|---|
| `SBBacklightController` | YES | `screenIsOn` present; `setIdleTimerDisabled:forReason:` absent |
| `SBLockScreenManager` | YES | `sharedInstance` and `isUILocked` present |
| `BKDisplayBrightnessController` | NO | no Objective-C class discovered |
| `BKBacklightClient` | NO | no Objective-C class discovered |
| `BKDisplayBlankingObserver` | NO | no Objective-C class discovered |
| `BLSBacklight` | YES | `sharedBacklight` present; tested update selector absent |

No unknown class was instantiated and no control selector was invoked.

## Mutation

```text
Attempted: NO
Function: NONE
Return: NOT APPLICABLE
```

The required one-shot mutation controller was intentionally not created because the ABI prerequisite failed. There was no unblank request, no disabled-state request, no IOPM assertion, and no brightness operation.

## Security

```text
Logical lock before: unchanged; no Phase 2H mutation run
Logical lock during: NOT APPLICABLE
Logical lock after: unchanged
Face ID/passcode still required: unchanged / not bypassed
```

No lock-state method was called by Phase 2H. The previous stable package remained installed throughout this Phase 2H investigation.

## Physical display

```text
Panel became visible: NOT TESTED
Overlay visible: NOT TESTED
Duration: NOT APPLICABLE
```

Phase 2E remains the only controlled physical-display experiment: the valid `PreventUserIdleDisplaySleep` assertion did not keep the panel visible after explicit lock.

## Restoration

```text
Original blank state restored: NOT APPLICABLE — no mutation occurred
Normal sleep works: unchanged; no Phase 2H display call
Normal wake works: unchanged; no Phase 2H display call
SpringBoard stable: YES
backboardd stable: YES
```

## Result

**A — no usable client interface.**

The internal BackBoard symbols are insufficient to safely construct an unblank request. Calling a guessed function signature, sending an undocumented MIG message, or using a daemon-internal symbol would violate the experiment boundary and could destabilize display/security behavior.

The first mutation experiment was therefore not executed. In particular, `BKDisplaySetDisabled` was not called, and no attempt was made to infer whether blanking or disabled state is the missing condition.

## Recommended next step

Do not proceed to a locked-visible display mutation on this primary device through the currently discovered interfaces. A future attempt would require a separately verified iOS 17.1.2 BackBoardServices client ABI, entitlement behavior, and rollback contract—preferably on a disposable test device. Direct backboardd injection, binary patching, MobileGestalt changes, and alternate power assertions remain rejected.

## Safety

Confirmed:

* no system binary patch
* no powerd injection
* no backboardd injection
* no MobileGestalt change
* no authentication bypass
* no brightness mutation
* no display mutation
* no IOPM assertion
* zero mutation attempts

Phase 2H stops at ABI resolution. No experimental package was installed and no SpringBoard reload was performed.
