# Phase 28 — Active Lock Capture and CA Blanking Boundary

Date: 2026-09-25
Target: iPhone 12 mini (`iPhone13,1`), iOS 17.1.2 (21B101), RootHide
Capture: Backlight Flow Probe 0.1.5; experimental preference enabled

## Result

The active test did enter the normal lock path. The experiment changed the
BackBoard HID backlight factor from `0.0` to the provider's dim factor `0.05`,
but the BLS target and provider remained in display mode `0`. BacklightServices
then set its CA blanked state to `1`, which calls
`BKSDisplayServicesSetScreenBlanked(YES)` and places the BackBoard black overlay
over the display.

This identifies why the factor-only experiment still looks like an ordinary
lock. The changed luminance is hidden beneath a later black overlay. The trace
does not prove whether display scanout also stops after mode `0`, so removing
the overlay is a discriminating experiment, not yet a complete AOD proof.

## Device trace

The same request and event object identities were preserved through the host:

```text
side-button-single-press-action
request=0x282724c00 activity=0 sourceEvent=3 explanation="lock button"
event request=0x282724c00 stateArgument=0 getter=0 rawState=0 previousState=2
target mode=0, ramp=0.185 s
provider mode=0, duration=0.185 s
provider-ca-blanked value=1
```

On the following touch, the probe recorded an activity-1 request, event state
`2`, target mode `4`, `provider-will-unblank`, `provider-ca-blanked value=0`,
and provider mode `3`. The system therefore completed the ordinary blank and
unblank operations; the constructor state, getter, and raw event field agree.

The installed NotchNowPlaying diagnostic domain also records the experimental
factor substitution `0.0 -> 0.05`, a locked-visible session, and unchanged mode
`0`. `ExperimentalLockedVisible=1` was present in the preference domain. The
feature was therefore armed for the test; this result is not explained by a
missed preference or a failed factor hook.

## Interpretation

Three separate operations are now observed on the same lock path:

1. The normal BLS event requests state `0` and transitions to display mode `0`.
2. The Phase 7 experiment substitutes a nonzero HID factor while retaining
   the native BLS transition values.
3. BLS sets CA blanked, producing the opaque black BackBoard overlay.

The third operation is a strong immediate explanation for the black screen.
If suppressing only the BLS-originated `BKSDisplayServicesSetScreenBlanked(YES)`
call reveals the existing dimmed SpringBoard presentation, the overlay is the
blocking boundary. If the display stays black, mode `0` also disables or
removes visible scanout and must be investigated separately.

## Next bounded experiment

The Phase 7 experimental hook now targets only the outgoing BKS blank request
when all conditions hold:

* the locked-visible experiment is armed;
* the request is `blanked == YES`;
* the call site resolves to `BacklightServicesHost.framework`.

The hook leaves the BLS event, target/provider mode, factor substitution,
lock-state enforcement, and unblank (`blanked == NO`) path unchanged. It logs
the caller image and offset. If the experiment is disarmed while the device is
still locked, it restores the black overlay through the original BKS function.
The normal unblank operation still calls the original function.

This remains a device-specific diagnostic experiment. A visible result would
not establish native AOD or a supported public API. It would show that the
SpringBoard-rendered pseudo-AOD can remain visible when BLS's black overlay is
omitted, while the native mode remains `0`.

## Build gate

The dedicated experimental workflow now runs on macOS 26 and records Xcode,
Apple Clang, iPhoneOS SDK, and RootHide Theos/SDK revisions. It verifies the
package architecture is `iphoneos-arm64e` and inspects the dylib build target
before the package is eligible for device installation.

Run `36120412666` passed with Xcode `26.6`, Apple Clang `21.0.0`, and iOS SDK
`26.5`. The produced dylib is arm64e with minimum iOS `15.0`; `lipo` and
`vtool` checks passed. The package is `0.1.15` and is installed on the device.
After respring, SpringBoard PID `3677` reported `TweakLoaded=1` and the
experimental preference remained enabled. At the time of the post-install
check, `PlaybackActive=0`, so no new locked-visible session had armed yet; the
visual result of the CA-blank suppression experiment is pending an attended
music-playing side-button press.
