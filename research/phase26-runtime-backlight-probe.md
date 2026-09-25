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
before scheduling the normal asynchronous logger. Version `0.1.2` writes both
the primary file and `/tmp/backlight-flow-probe.log`; the second destination
distinguishes a SpringBoard sandbox restriction on the primary path from a
failure to load the tweak.

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

## Follow-up user test

After installing `0.1.1`, the user pressed the side button and reported that
SpringBoard behaved normally (no safe-mode/crash during that attempt). The
expected log was still absent. The device confirms the package and both probe
files are installed, and `/var/mobile/Library/NotchNowPlaying` exists and is
owned by `mobile` with owner-write permission. Because the constructor's
synchronous marker also did not appear, the attempt yielded no transition
trace. It is not evidence that the BLS path completed normally: probe loading
or SpringBoard's ability to write at that path remained unverified at the time.

## Version 0.1.2 load diagnosis and correction

Version `0.1.2` added `/tmp/backlight-flow-probe.log`. GitHub Actions run
`35970359958` built it successfully with Xcode 15.4 / iOS SDK 17.5. The package
is `iphoneos-arm64e`; the extracted dylib is Mach-O `arm64e` with PAC support.
It was installed over `0.1.1`, and `sbreload` completed. Neither the primary
file nor the `/tmp` fallback appeared.

An earlier interpretation blamed the absent marker on disabled global tweak
injection because `com.aapl.relaxin.startup` showed `DISABLE_TWEAKS=1` and
exit 255. That was incorrect. Relaxin's shipped startup plist sets
`DISABLE_TWEAKS=1` for the one-shot `jbctl internal startup` helper itself;
its stopped state after running does not establish SpringBoard injection
status. Relaxin's app code exposes a separate `Tweak Injection` control backed
by the RootHide `.safe_mode` marker. The device currently has no
`/var/jb/basebin/.safe_mode`, matching the user's report that injection is on.

The current RootHide Manager configuration lists third-party app IDs and no
`com.apple.springboard` entry. SpringBoard has the expected RootHide
`DYLD_INSERT_LIBRARIES` systemhook. A previous crash report also showed
`NNPInjectionProbe.dylib` loaded in SpringBoard, and its preferences domain
contains `ConstructorReached=YES` (last modified Sep 21). These establish that
the injection route has worked before, but they do not prove the new
BacklightFlowProbe constructor ran after the latest reload.

## Version 0.1.3 runtime load confirmation

GitHub Actions run `36113062064` built version `0.1.3` successfully with
Xcode 15.4 / iOS SDK 17.5. The package is `iphoneos-arm64e`; the extracted
dylib is Mach-O `arm64e` with PAC support. It was installed over `0.1.2`, and
`sbreload` completed.

The direct files at `/var/mobile/Library/NotchNowPlaying` and `/tmp` remain
absent, but the fallback through `CFPreferences` succeeded. The device created
`/var/mobile/Library/Preferences/com.user.nnpbacklightflowprobe.plist` at Sep
25 16:30. Its values include:

```text
Bootstrap = probe-bootstrap 60650.273399 pid=3228
Trace = 60650.283178 pid=3228 probe-loaded
       60652.101416 springboard-request ... explanation=boot
       60652.101453 bls-client-request ...
       60652.101475 bls-host-request ...
       60652.101607 bls-event ... eventID=1 state=2 previousState=2
       60652.101688 bls-event-request ...
```

This proves that SpringBoard loaded this probe, its Logos hooks are active,
and the preferences logger works. It also identifies the reason the earlier
file-based checks were inconclusive: those two direct file destinations did
not accept the probe's writes. The captured transition so far is only the
SpringBoard boot request (`explanation=boot`); the trace does not yet contain
`side-button-single-press-action`. No AOD or lock-button conclusion can be
drawn from this boot sample.

Next capture: with music playing and the display active, press the side button
once, then leave the phone undisturbed for at least 45 seconds or until the
failure occurs. The resulting `Trace` preference will preserve the ordered
SpringBoard/BLS records even if the tweak is disabled after a panic.
