# Phase 2F — Explicit Lock Display-Off Path

Target: iPhone13,1 / D52gAP, iOS 17.1.2 (21B101)

## Executive conclusion

The available evidence places the physical panel-off operation in the BackBoard display/blanking pipeline, not in the SpringBoard UIKit window. `backboardd` owns the relevant display service and contains the display-disabled, display-blanking, backlight, and display-state surfaces. Its launchd service exposes `com.apple.backboard.display.services` and `com.apple.backlightd`.

The exact SpringBoard caller for the physical-lock transition was not recovered from the available iOS 17.1.2 dyld-cache tooling. The working prototype did confirm that SpringBoard's logical lock state changes through `SBLockScreenManager`/`isUILocked`, followed by the user-observed panel-off transition. Static evidence strongly suggests that the lock/policy path sends a display blank/disable request to BackBoard, but this is not a recovered call graph.

No safe, confirmed SpringBoard client token that suppresses the explicit lock display-off transition was found. `IOPMAssertionCreateWithDescription(...PreventUserIdleDisplaySleep...)` was proven to succeed in Phase 2E, but the panel still turned off on explicit lock. The remaining BackBoard symbols are either observation surfaces, display mutation APIs, MIG/daemon interfaces, or internal assertion bookkeeping. They must not be invoked from the tweak without a separately approved experiment.

Classification: **D for a safe continuous-on route at the current evidence level**. A client-side interface may exist internally, but no reasonable, confirmed, SpringBoard-accessible mechanism was established.

## Explicit lock timeline

Only part of the timeline was passively confirmed:

```text
physical lock button
        ↓
SpringBoard logical lock state changes
        ↓
lock-screen/display policy evaluates the display
        ↓
BackBoard display blank/disable path
        ↓
backlight/panel becomes physically off
```

Evidence and limits:

| Stage | Evidence | Confidence |
|---|---|---|
| Logical lock | Existing SpringBoard prototype reads `SBLockScreenManager` and `isUILocked`; Phase 2E recorded `LastLockState=locked`. | CONFIRMED for the logical state observation |
| Lock-screen presentation | SpringBoard owns the running Lock Screen/UI process and the ordinary overlay disappears when the display powers down. | STRONG INFERENCE for the transition ownership |
| Display blank/disable request | `backboardd` contains `BKDisplaySetDisplayBlanked`, `BKDisplaySetDisabled`, `_BKDisplaySetDisabled`, `BKDisplayBlankingObserver`, and display-blanking notifications. | CONFIRMED as available backboardd surfaces; request caller not confirmed |
| Backlight/panel off | User observed full darkness after the Phase 2E lock; backboardd contains backlight state/control and `com.apple.backlightd`. | CONFIRMED observation; exact driver call not recovered |

No exact timestamps for the button event, blanking notification, and physical panel-off event were available. The device had no usable `notifyutil` or unified-log CLI, and the existing readable `ThreadsNoSpoiler.log` contained no matching display events. No notification was suppressed or altered.

## Process responsibility

| Stage | Process | Component/interface | Evidence | Confidence |
|---|---|---|---|---|
| Logical device lock | SpringBoard | `SBLockScreenManager` / `isUILocked` observation used by the working tweak | Runtime observation in the prototype | CONFIRMED for state ownership/observation |
| Lock Screen presentation | SpringBoard | Lock Screen/SpringBoard UI process | SpringBoard is the UI owner; overlay lifecycle follows its lock state | STRONG |
| Display policy and blanking | backboardd | `BKDisplayServices MiG Server`, `BKDisplaySetDisplayBlanked`, `BKDisplaySetDisabled` | Strings and symbols in the iOS 17.1.2 backboardd binary | CONFIRMED as service ownership |
| Display-disabled bookkeeping | backboardd | `_BKDisplayDisabledAssertions`, `_displayDisabledAssertion`, `displayBlankingObservationAssertion` | backboardd symbols and Objective-C metadata strings | CONFIRMED as internal state surfaces |
| Backlight endpoint | backboardd | `com.apple.backlightd`, `BKBacklightClient`, backlight manager | `launchctl print user/501/com.apple.backboardd` and binary strings | CONFIRMED |
| Power policy | powerd | `com.apple.PowerManagement.control`, `com.apple.iokit.powerdxpc`, BacklightServices/AOD strings | launchd endpoints and powerd metadata | CONFIRMED |
| Panel hardware transition | display/backlight driver | No direct driver call graph recovered | bounded static inspection only | SPECULATION beyond BackBoard boundary |

## BackBoard findings

### `_BKDisplayDisabledAssertions`

`backboardd` contains:

```text
_BKDisplayDisabledAssertions
_displayDisabledAssertion
BKDisplayIsDisabled
BKDisplaySetDisabled
_BKDisplaySetDisabled
```

It also contains:

```text
BKDisplayBlankingObserver
_BKDisplayBlankingContext
addDisplayBlankingObserver:
displayBlankingObservationAssertion
backboardd.display-blanking
```

The symbol name and the log strings:

```text
acquiring display-disabled assertion on %@
releasing display-disabled assertion on %@
exited with display-disabled assertion on %@, releasing
```

show that this is an internal assertion/bookkeeping surface associated with disabling or blanking a display. The evidence does **not** establish that it is a client assertion that prevents display disable. The direction is therefore:

**STRONG INFERENCE:** a “display-disabled assertion” asserts/records that the display is to be disabled, or tracks a display-disable operation. It should not be treated as a keep-the-panel-on token.

### Display state and blanking

Actual discovered names include:

```text
displayState
DisplayStateControlSupported
BKDisplaySetDisplayBlanked
BKDisplayIsDisplayBlanked
BKDisplayWillUnblank
BKDisplayGetBlankingRemovesPower
BKDisplaySetBlankingRemovesPower
BKDisplayIsDisabled
BKDisplaySetDisabled
```

These are present in backboardd and are not proof of a safe SpringBoard client contract. The `BKDisplaySet...` symbols are display mutation surfaces and were not called.

### Backlight control

Actual names include:

```text
BKBacklightClient
backlightManager
backlightLocked
lockBacklight
setBacklightLocked:forReason:
setLockBacklight:
_BKHIDXXSetBacklightFactorWithFadeDuration
```

The existing vendor header also contains the legacy SpringBoard declaration:

```objc
SBBacklightController
-setIdleTimerDisabled:forReason:
```

That header is development metadata, not device-version proof. The iOS 17.1.2 runtime did not provide enough local class metadata to confirm this selector as a usable lock-transition override. Phase 2E's successful IOPM idle-display assertion further shows that ordinary idle prevention is not equivalent to explicit-lock display retention.

## SpringBoard findings

The working tweak observes logical lock through `SBLockScreenManager` and `isUILocked`; it does not alter that state. The prototype's overlay is a normal SpringBoard UIKit window and disappears when BackBoard turns the panel off.

The copied standalone SpringBoard image contains only limited lock/AOD strings (`Device.Display.AlwaysOn`, `SBLockdownEverRegisteredKey`, and `com.apple.springboard.lockScreenContentAssertion`). Most iOS 17 SpringBoard Objective-C implementation is in the dyld shared cache, and the available cache tooling did not recover a trustworthy method-level call graph for the physical lock button path.

Therefore:

* **CONFIRMED:** logical lock is a SpringBoard-visible state separate from the overlay's visibility.
* **STRONG INFERENCE:** SpringBoard's lock/policy transition requests or causes BackBoard display blanking/disable.
* **NOT CONFIRMED:** the exact SpringBoard class, selector, or caller that submits the display-off request on this build.

## IPC

Read-only `launchctl print` showed:

### backboardd

```text
service: user/501/com.apple.backboardd
program: /usr/libexec/backboardd
endpoint: com.apple.backlightd
endpoint: com.apple.backboard.display.services
endpoint: com.apple.backboard.system-app-server
endpoint: com.apple.backboard.hid-services.xpc
endpoint: com.apple.backboard.hid.services
```

The backboardd binary labels its display interface:

```text
BKDisplayServices MiG Server
com.apple.backboard.display.services
```

This is strong evidence for a Mach/MIG-style client boundary behind BackBoardServices. No message was sent.

### powerd

```text
service: user/501/com.apple.powerd
endpoint: com.apple.PowerManagement.control
endpoint: com.apple.iokit.powerdxpc
```

These are power-policy endpoints. Phase 2E used only the client IOKit assertion API and did not contact either endpoint directly.

### Notifications

Static backboardd evidence includes:

```text
com.apple.backboardd.display-disabled
com.apple.backboardd.backlight.changed
com.apple.springboard.hasBlankedScreen
backboardd.display-blanking
```

Their names support observation of display blanking/backlight transitions. Payload formats and exact posting order were not recovered. No notification was posted, intercepted, or suppressed.

## Candidate APIs

| Interface | Framework/process | Semantics | Apple caller | Risk | Confidence |
|---|---|---|---|---|---|
| `IOPMAssertionCreateWithDescription` + `PreventUserIdleDisplaySleep` | IOKit / powerd client boundary | Prevents idle display sleep; does not override explicit lock on this target | Not needed; tested by NotchNowPlaying | Low when short-lived, but ineffective for this goal | CONFIRMED behavior from Phase 2E |
| `SBBacklightController -setIdleTimerDisabled:forReason:` | SpringBoard metadata/header | Candidate idle-timer client surface | Current iOS 17 caller not confirmed | Could keep normal display path awake; does not prove lock override | SUSPECTED / unverified on target |
| `BKBacklightClient` / `setBacklightLocked:forReason:` | BackBoard/backlight path | Backlight lock/control, likely policy/client-specific | No caller recovered | Direct display-policy mutation and entitlement/security risk | STRONG as internal surface; unsafe client contract |
| `BKDisplaySetDisplayBlanked` | BackBoard display service | Explicit display blank mutation | BackBoard/internal callers | Directly changes display state; wrong direction for pseudo-AOD | CONFIRMED symbol; semantics strongly indicated by name |
| `BKDisplaySetDisabled` / `_BKDisplaySetDisabled` | BackBoard display service | Disable/enable display state | BackBoard/internal callers | Direct display mutation; could blank/disable or destabilize UI | CONFIRMED symbol; client safety unconfirmed |
| `_BKDisplayDisabledAssertions` | backboardd internal state | Tracks display-disabled assertions | backboardd | Internal bookkeeping, not a safe client API | CONFIRMED existence; semantics STRONG |
| `BKDisplayBlankingObserver` / notification names | BackBoard | Observe blanking/disabled changes | BackBoard observers | Observation only if registered through a supported boundary | CONFIRMED observation surface |
| `com.apple.backboard.display.services` | BackBoardServices/MIG | BackBoard display service transport | SpringBoard/system clients | Direct IPC is daemon-level and not appropriate for this tweak without proof | CONFIRMED endpoint; request contract unconfirmed |

## Security separation

The desired future state would keep:

```text
logical device lock = ON
passcode/Face ID requirement = ON
touch security = ON
display panel = potentially visible
```

The Phase 2F evidence does not show that any candidate display interface changes authentication or data-protection state. However, direct BackBoard or SpringBoard lock-path interception could affect security-sensitive transitions. Any design that bypasses the lock request, disables passcode state, or changes Lock Screen security must be rejected.

The safe conceptual separation is clear; a safe implementation boundary is not.

## AOD / StandBy comparison

### AOD

Earlier reports confirmed powerd AOD/Ambient names and a missing native AOD capability marker on iPhone13,1. No supported-device call graph was recovered. It is therefore not possible to claim whether supported devices skip blanking, enter a different display state, or re-enter an ambient renderer after blanking.

### StandBy

StandBy was not activated or modified during this phase. No device-specific StandBy assertion or display-state caller was recovered from the available artifacts. Any relationship to this lock/display path remains **SPECULATION**.

## Future implementation options

Ranked by technical evidence, not preference:

1. **Confirmed client-side supported interface:** none identified. The existing IOPM idle assertion is confirmed ineffective for explicit lock.
2. **Client display-state request:** BackBoard display service/MIG and `BKBacklightClient` surfaces exist, but no safe SpringBoard client contract or entitlement was confirmed. This remains research-only and high risk.
3. **Invasive BackBoard hook:** technically closer to the owner of the transition, but explicitly unsafe for the primary device and outside the approved scope. Do not implement automatically.
4. **Abandon continuous pseudo-AOD:** use event-driven brief wake, tap-to-show, or keep the normal screen-on prototype while accepting that the panel powers off on lock.

## Recommended Phase 2G experiment

The safest next experiment is **not** to invoke a display-control API. First add a read-only diagnostic observer in SpringBoard for the already identified notification/state surfaces, if a passive observer can be registered without altering display policy:

```text
observe only:
  com.apple.springboard.hasBlankedScreen
  com.apple.backboardd.display-disabled
  com.apple.backboardd.backlight.changed
```

One-shot behavior:

* explicit diagnostic arm;
* observe one lock/unlock cycle;
* no display or power calls;
* no daemon injection;
* stop after the first complete cycle.

Expected observation: timestamped ordering between logical lock, blanking notification, display-disabled notification, and wake/unlock. Rollback is removing the diagnostic package; no display state should be changed. Failure modes are missing notification visibility, sandbox/entitlement restrictions, or SpringBoard instability from an incorrectly registered observer. If passive observation cannot be done safely, stop at this boundary and retain fallback option 4.

## Safety status

Phase 2F performed read-only device inspection and copied binaries from the device for local analysis. It did not:

* invoke display-enable/disable or brightness APIs;
* create any power assertion;
* hook or inject into powerd/backboardd;
* modify MobileGestalt or lock state;
* send XPC/Mach requests;
* restart a daemon, reboot, or respring;
* patch binaries or system files.

No Phase 2G experiment was executed.
