# Phase 26 — Passive Runtime Backlight Probe

## Purpose

The supplied SpringBoard crash is an abort issued by
`BLSHWatchdogProvider` on the main queue. The passive probe is intended to
capture the live side-button-to-display-off sequence and identify the last
completed request/event/mode/blanking operation before a repeat watchdog.

## Capture points

The standalone `BacklightFlowProbe` tweak logs, without changing arguments or
return values:

* `SBLockHardwareButtonActions performSinglePressAction` as the side-button
  sequence marker;
* SpringBoard's `_performBacklightChangeRequest:completion:`;
* the BLS client and host `performChangeRequest:` handoffs;
* transition event ID, current/previous state, and request fields;
* target display mode and ramp, provider display mode and duration;
* CA blanked and unblank notifications.

Each record uses `mach_continuous_time`, PID, and a serial asynchronous file
writer. The log is appended to
`/var/mobile/Library/NotchNowPlaying/backlight-flow-probe.log`. Comparing the
side-button marker with the first later event shows where the observed delay
occurs. The probe does not request a display mode, alter a BLS request, change
brightness, or call a BackBoard API.

The constructor also appends a one-line `probe-bootstrap` marker synchronously
before scheduling the normal asynchronous logger. This tiny marker separates
an injection failure from a failure in the dispatch-based log writer.

## Build and installation gate

The probe source is in `BacklightFlowProbe/`. A Clang 22 build for generic
`arm64` compiled and linked successfully, but generic arm64 cannot be loaded
into this device's arm64e SpringBoard. A Clang 22 `arm64e` build on the local
WSL/Linux toolchain linked only with the old Theos `ld64-609` and emitted
`object file ... was built with an incompatible arm64e ABI compiler`; that
artifact must not be installed.

Theos documents that the iOS 14+ arm64e ABI is required for injecting into
arm64e system binaries and that producing it requires the macOS/Xcode linker;
its Rootless guidance lists GitHub Actions or macOS as the safe build route.
Therefore no package from the local Linux arm64e build has been installed.
The source is ready for a macOS/Xcode build with the current SDK/toolchain.

## Reading the trace

The useful capture is one press followed by enough time to reproduce the
failure. Preserve the log from before the press through the SpringBoard
restart. If a `side-button-single-press-action` is followed by no BLS request,
the delay is upstream in SpringBoard's sleep/lock route. If a request and
event appear but the final target mode has no matching completion, the
display-state transition/watchdog is the next boundary. If target/provider
modes complete but CA blank/unblank or another callback stalls, the boundary
is downstream. These are diagnostic interpretations, not assumptions about
what the phone will emit.

## First device load check

GitHub Actions run `35967754199` built version `0.1.0` on macOS 14 with
Xcode 15.4 / iOS SDK 17.5. The extracted dylib is arm64e and has the modern
ABI marker absent from the local Linux link. The package manager installed it
as `iphoneos-arm64e`, and SpringBoard was resprung.

The expected log was not created after that respring. Version `0.1.1` adds a
small synchronous `probe-bootstrap` write before starting the asynchronous
logger; GitHub Actions run `35969142971` rebuilt that package, which was
installed and resprung as well. The log still did not appear, although
SpringBoard remained listed by launchd. This does not yet distinguish a tweak
injection failure from a sandbox/path write failure. No side-button trace has
been captured yet, so do not infer anything about the backlight transition
from this empty log.
