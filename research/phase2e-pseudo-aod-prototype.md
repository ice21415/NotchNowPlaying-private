# Phase 2E — Pseudo-AOD Prototype

## Startup

| Key | Result |
|---|---|
| TweakLoaded | YES |
| SpringBoardPID | 3411 |
| ControllerInitialized | YES |

The constructor marker and controller state were recorded through the CFPreferences domain `com.user.notchnowplaying.diagnostics`. The earlier raw-file diagnostic paths were not used for critical data.

## Eligibility

| Key | Result |
|---|---|
| Locked | YES |
| SpotifyDetected | YES |
| ActiveMediaBundle | `com.spotify.client` |
| PlaybackActive | YES |
| NowPlayingValid | YES |
| EligibilityPassed | YES |

## Assertion

| Key | Result |
|---|---|
| Attempted | YES — exactly one actual attempt |
| IOReturn decimal | `0` |
| IOReturn hex | `0x00000000` |
| Assertion ID | `35277` |
| Valid | YES |
| Release result | `0` |
| Release reason | `timeout` |
| Release timestamp | `2026-09-20 07:28:07 +0000` |

The call used only `IOPMAssertionCreateWithDescription` with `kIOPMAssertionTypePreventUserIdleDisplaySleep`, a ten-second timeout, and `kIOPMAssertionTimeoutActionRelease`. The independent local watchdog and the system timeout converged on the idempotent release path.

## Physical display

| Observation | Result |
|---|---|
| Panel stayed visible | NO |
| Overlay stayed visible | NO |
| Normal display sleep | YES — observed full darkness after lock |

## UI

The existing UI implementation remained unchanged for this experiment and was not visible after the panel powered off.

| Element | Result while the panel was powered |
|---|---|
| Artwork | Existing Now Playing artwork path retained |
| Title | Existing title label retained |
| Artist | Existing artist label retained |
| Progress | Existing approximately 1 Hz update retained |
| Black OLED background | YES |

No brightness, refresh-rate, or ambient rendering API was added.

## Result

**B — assertion accepted but explicit lock still powers the display off.**

This is confirmed by the runtime return code and valid assertion ID, followed by a successful release. The physical observation shows that this client-side idle-display assertion does not keep the locked iPhone 12 mini panel visibly powered through the explicit lock/display-off transition.

This is not native AOD and does not demonstrate an ambient or low-refresh panel mode.

## Diagnostics note

The captured `LastError` field contained a stale diagnostic value from the first implementation despite the successful return code. The authoritative fields are `AssertionCreateResultDecimal=0`, `AssertionCreateResultHex=0x00000000`, `AssertionIDValid=true`, and `AssertionReleaseResult=0`. The source was corrected so future successful calls record `LastError=none`; no further device test was run.

## Safety

Confirmed:

* no brightness modification
* no refresh-rate modification
* no powerd injection
* no backboardd injection
* no MobileGestalt change
* no system binary patch
* no alternate assertion type
* one actual assertion attempt only
* assertion released after ten seconds
* SpringBoard remained responsive

## Decision

The ordinary SpringBoard client assertion is not sufficient for a persistent pseudo-AOD on this device. Do not switch assertion types or escalate to powerd/backboardd injection automatically. Any later phase would need a separately approved design, with the current result treated as a controlled negative for this interface.
