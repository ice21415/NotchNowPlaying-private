# Phase 4A — Read-Only Backlight Observation

This phase prepared one disabled-by-default observational path. It was built
by GitHub Actions but was not installed or run on the device. Consequently,
no state values are claimed in this report.

## Execution attempt

```text
Local/remote commit: 7296432d75eee27d4a74265e9181aa5a851c5c23
GitHub push:         PASS
GitHub Actions:      PASS — run 35566036139
Artifact:            PASS — downloaded from that run
Artifact SHA256:     469AB0ECA2F0902B3B470CD454396A8CC118AF640E4D5F0D83F352AFE04612FF
SSH uname check:     PASS
Transfer/install:    PASS — scp completed and dpkg installed the package
Awake sample:        NOT EXECUTED
Lock sample:         NOT EXECUTED
```

## Deployment diagnosis

```text
Artifact SHA256:  PASS
SSH basic:        PASS (`NNP_SSH_OK`)
SSH BatchMode:    FAIL — interactive keyboard/password authentication required
Transfer method:  SCP/SFTP
Remote path:     `/var/tmp/notchnowplaying-phase4a.deb`
Remote SHA256:    PASS
Installation:    PASS (`dpkg -i`)
Reload:           `/usr/bin/sbreload` invoked
Runtime logs:     NOT AVAILABLE
```

## File-logging fallback attempt

```text
Source fix commit: 3ca6ebe6b9b7c4434560563bfa797a89e784fc56
GitHub Actions:   PASS — run 35567883357
Artifact SHA256:  9A174423EE9554DE3B56234DA56908FFA8D94B46C0D63EE6ECE4627BECF0D95F
SCP transfer:     PASS to /var/tmp/notchnowplaying-phase4a.deb
Remote checksum:  NOT OBTAINED — subsequent SSH banner exchange timed out
Installation:     NOT ATTEMPTED for revised artifact
Runtime logs:     NONE
```

The revised artifact was subsequently installed and reloaded. The remote
checksum matched the expected SHA256, but no Phase4A file log was produced.
No additional runtime probe was performed.

## Revised deployment diagnosis

```text
Artifact commit: 3ca6ebe6b9b7c4434560563bfa797a89e784fc56
GitHub Actions: PASS — run 35567883357
Artifact SHA256: PASS — 9A174423EE9554DE3B56234DA56908FFA8D94B46C0D63EE6ECE4627BECF0D95F
SSH interactive: PASS
Remote SHA256: PASS
Revised installation: PASS — dpkg -i
SpringBoard reload: PASS — /usr/bin/sbreload; new PID observed
Installed rootless paths: PASS — /var/jb/Library/MobileSubstrate/DynamicLibraries
Phase4A file log: MISSING
Existing startup diagnostics: not updated after reload
Awake sample: NOT EXECUTED
Lock sample: NOT EXECUTED
```

The revised package is present in ElleKit's `/var/jb/usr/lib/TweakInject`
directory with its matching filter plist. However, the diagnostics
preference mtime remained from the earlier run and neither the Phase4A file
log nor the existing startup diagnostics changed after the new SpringBoard
reload. This leaves SpringBoard/ElleKit execution or loading as the blocker;
it does not indicate an artifact or transfer checksum problem.

The bounded BatchMode check established that the endpoint requires interactive
authentication. The explicitly authorized interactive connection then
completed transfer and installation. No SSH or device configuration was
changed. The device had no usable `/usr/bin/log`, `syslog`, or
`idevicesyslog`; `log` resolved only to a zsh builtin and produced no Phase4A
records. Therefore no runtime sample was claimed.

The commit contains only the Phase 4A source, flag integration, dedicated
workflow, and this report. No package was compiled locally.

## Acquisition

```text
existing object source: +[BLSBacklight sharedBacklight]
receiver:               BLSBacklight class object
class validation:       [object isKindOfClass:BLSBacklight]
state selector:         -backlightState
ownership:              system/framework-owned singleton; no alloc/init,
                        proxy construction, or manual connection creation
```

The source was selected because the static work established `sharedBacklight`
as the framework singleton accessor. The helper fails closed if either the
class, singleton accessor, returned object, or state selector is unavailable.

## Safety boundary

```text
constructs requests:       NO
constructs events:         NO
acquires assertions:       NO
opens XPC/MIG connection:  NO
mutates display:           NO
changes brightness:        NO
changes idle timer:        NO
touches authentication:    NO
reads logical lock state:  NO
```

The sole state-bearing message send is `-[BLSBacklight backlightState]` on the
validated singleton. `sharedBacklight` is used only as the approved existing
singleton acquisition accessor.

## Implementation

The experimental source is [NNPPhase4AReadOnlyBacklight.m](C:\Users\ice21\OneDrive\文件\tweak\NotchNowPlaying\NNPPhase4AReadOnlyBacklight.m). It is compiled only if:

```c
#define NNP_ENABLE_PHASE4A_READONLY_BACKLIGHT_LOG 1
```

The Makefile default is `0`, so normal release behavior and its compiled file
set remain unchanged. The helper performs no retry, polling, timer,
`dispatch_after`, sleep, or delayed sample. It logs the validated object and
class once, then logs an integer only:

```text
[NNP][Phase4A] BLSBacklight object=<ptr> class=<class>
[NNP][Phase4A] reason=awake state=<integer>
[NNP][Phase4A] reason=lock-transition state=<integer>
```

The awake read occurs once from the existing post-startup path if SpringBoard
is active, otherwise once on the standard `UIApplicationDidBecomeActive`
notification. The lock-transition read occurs once on the existing read-only
Darwin notification `com.apple.springboard.hasBlankedScreen`. Its callback
only calls the helper and returns; it neither hooks nor changes the normal
lock action, arguments, timing, or result.

## Awake sample

```text
state:    NOT EXECUTED
log line: [NNP][Phase4A] reason=awake state=<integer>
```

## Explicit-lock sample

```text
state:    NOT EXECUTED
log line: [NNP][Phase4A] reason=lock-transition state=<integer>
```

## Comparison

```text
awake:           NOT EXECUTED
lock-transition: NOT EXECUTED
same/different:  UNRESOLVED
```

## Interpretation

```text
OBSERVED:   no runtime sample exists yet.
CORRELATED: no physical state name is assigned by this preparation.
UNRESOLVED: whether awake and lock-transition values differ, and whether
            either integer is a universal physical-state label.
```

If manually enabled later, `awake != lock-transition` establishes only that
the provider-maintained accessor changed across the two naturally occurring
conditions. Equality is also informative but does not authorize extra probes:
the sample may precede a provider update, use a shared reported state, or sit
above the layer that blanks the panel.

## Static/runtime reconciliation

The future integer must be interpreted only against the established producer
model:

| Reported state | Static producer |
| ---: | --- |
| 0 | nonzero request with Always-On false or suppressed |
| 1 | nonzero request with Always-On true and not suppressed |
| 2 | `requestedActivityState == 0` |
| 3 | `requestedActivityState == 2` |

The implementation does not label an observed value `Off`, `ActiveOn`, or
`AlwaysOn`; that would exceed the evidence of one observation.

## Deployment result

```text
F — runtime injection/logging remains the blocker; no Phase4A sample was obtained.

## Minimal injection-probe diagnosis

```text
InjectionProbe workflow: PASS — run 35569984837
InjectionProbe artifact: downloaded successfully
InjectionProbe install: PASS — dpkg -i
SpringBoard reload: PASS — new PID observed
InjectionProbe constructor: FAIL — /var/mobile/Library/Preferences/NNPInjectionProbe.log missing
NotchNowPlaying constructor: NOT REACHED — startup diagnostics unchanged
```

The probe and NotchNowPlaying packages are present in both observed rootless
paths:

```text
/var/jb/usr/lib/TweakInject
/var/jb/Library/MobileSubstrate/DynamicLibraries
```

The filter plist targets `com.apple.springboard`. ElleKit's injector files are
installed, including `/var/jb/usr/lib/TweakInject.dylib` and
`/var/jb/usr/lib/ellekit/libinjector.dylib`.

However, SpringBoard's inspected environment contains:

```text
DYLD_INSERT_LIBRARIES=/usr/lib/systemhook-0E34A8F7F290BABD.dylib
```

and that exact file was not present at either `/usr/lib` or the checked
rootless `/var/jb/usr/lib` path. Together with the missing minimal-probe
constructor log, the most specific supported diagnosis is a global
roothide/ElleKit systemhook/bootstrap injection failure. No bootstrap or
system configuration was modified.

```text
Phase4A awake: NOT EXECUTED
Phase4A lock-transition: NOT EXECUTED

## Relaxin + RootHide injection diagnosis

```text
Active jailbreak: Relaxin
RootHide manager: 1.3.9
RootHide patcher: 2.1.4-1+debug
ElleKit: 1.2-1 (installed compatibility/injector component)
Active jbroot: /var/containers/Bundle/Application/.jbroot-0E34A8F7F290BABD/
jbroot resolution: /usr/bin/jbroot
RootHide brand: 0E34A8F7F290BABD
```

The earlier systemhook conclusion was corrected. The logical SpringBoard
environment path:

```text
/usr/lib/systemhook-0E34A8F7F290BABD.dylib
```

is provided by Relaxin's `/basebin` namespace; the actual file exists as:

```text
/basebin/systemhook-0E34A8F7F290BABD.dylib
```

It is a valid universal arm64/arm64e Mach-O. The active tweak directory is
rooted at the resolved jbroot and is mirrored through the observed RootHide
paths:

```text
/var/containers/Bundle/Application/.jbroot-0E34A8F7F290BABD/usr/lib/TweakInject
/var/jb/usr/lib/TweakInject
/var/jb/Library/MobileSubstrate/DynamicLibraries
```

The Relaxin startup launchd service is the decisive failure point. Its actual
configuration contains:

```text
DISABLE_TWEAKS=1
```

and its inspected status is:

```text
state: not running
last exit code: 255
```

The supported `jbctl reboot_userspace` operation was attempted once. After
reconnection, `DISABLE_TWEAKS=1`, exit code 255, the missing InjectionProbe
constructor log, and the unchanged NotchNowPlaying startup diagnostics all
remained. No launchd plist, systemhook, bootstrap binary, credential, or
authentication setting was manually modified.

```text
InjectionProbe constructor: FAIL
NotchNowPlaying constructor: NOT REACHED
Phase4A awake: NOT EXECUTED
Phase4A lock-transition: NOT EXECUTED
Root cause category: Relaxin tweak injection disabled/startup failure
Repair result: NOT REPAIRED — requires the supported Relaxin/RootHide
               enable-tweaks control; no safe public CLI was identified
```
```
```

No display mutation was performed.

## Phase4A execution trace

```text
Trace source commit: 49466eb80890927cae1eb504d24d7fc425a87056
GitHub Actions: PASS — run 35573463100
Artifact SHA256: A5609B019241FC6753274967F74DBBF1D0C7D9E9383D49EE29F29DAB59DED0F8
Phase4A implementation strings in artifact: PASS
Trace directory: /var/mobile/Library/NotchNowPlaying
Trace directory permissions: corrected to mobile:mobile 755
Trace file: MISSING after SpringBoard reload
```

The artifact was independently inspected and contains the implementation
markers, including `phase4a-trace.log`, `PHASE4A_START_ENTER`,
`BLS_CLASS_LOOKUP_BEGIN`, and `BACKLIGHT_STATE`. The diagnostics directory was
also made writable by the SpringBoard `mobile` user and a direct mobile write
test succeeded before reload.

No runtime marker was produced, including the first constructor marker:

```text
PHASE4A_COMPILED: no runtime record
CTOR_ENTER: no runtime record
POST_STARTUP_BLOCK_ENTER: no runtime record
PHASE4A_START_ENTER: no runtime record
```

Therefore the first missing execution stage is the injected dylib constructor,
before the existing four-second block, UIApplication state, BLS class lookup,
or notification registration. No BLS accessor was called and no runtime state
value was collected.

## Loaded image identity

```text
SpringBoard PID: 11613
Active jbroot: /var/containers/Bundle/Application/.jbroot-0E34A8F7F290BABD/
```

The three visible NotchNowPlaying dylib paths are one backing file, not stale
duplicates:

| Path | Inode | Size | mtime | SHA256 |
| --- | ---: | ---: | --- | --- |
| `/var/jb/usr/lib/TweakInject/NotchNowPlaying.dylib` | 7152676 | 108192 | 2026-09-21 16:07 | `fe164043d2b651ebaa49f7f40e3b7a7ac50c47aa20a6f2c90ead5ab11f02eb03` |
| `/var/jb/Library/MobileSubstrate/DynamicLibraries/NotchNowPlaying.dylib` | 7152676 | 108192 | 2026-09-21 16:07 | same inode / same file |
| `/var/containers/Bundle/Application/.jbroot-0E34A8F7F290BABD/usr/lib/TweakInject/NotchNowPlaying.dylib` | 7152676 | 108192 | 2026-09-21 16:07 | same inode / same file |

The package manager owns the canonical logical package path. RootHide's
installer/patch layer expands the installed backing image beyond the GitHub
payload size; its backing-file SHA256 therefore differs from the raw package
payload SHA256. The installed arm64e Mach-O contains the instrumented strings:

```text
phase4a-trace.log
CTOR_ENTER
PHASE4A_START_ENTER
BLS_CLASS_LOOKUP_BEGIN
BACKLIGHT_STATE
```

The `mobile` user successfully appended a temporary write to the trace path
after its directory ownership was corrected to `mobile:mobile`; the test file
was then removed. Thus the trace path itself is writable.

Existing read-only process-image interfaces could not enumerate SpringBoard's
mapped Mach-O images: `launchctl procinfo` returned `Could not print Mach info
for pid 11613: 0x5`, and `/proc/11613/maps` did not expose the mapping. The
exact mapped path and loaded-image hash consequently remain unproven, although
no stale disk copy was found.

## Runtime isolation update

GitHub-built isolation results:

UI-only identity marker: PASS
Phase4A object linked but inactive: PASS
constructor CFPreferences-only probe: PASS
delayed trace-only probe: FAIL — UI disappeared
one-read BLS UI probe without immediate UI refresh: FAIL — UI disappeared

The one-read probe used only the recovered read-only BLS path:
sharedBacklight followed by backlightState.

No BLS request, assertion, setter, brightness call, lock/authentication call,
or display mutation was executed. No valid awake or lock-transition integer was
obtained. The deployed package was rolled back to the verified UI-only build.

This is runtime instability evidence for the combined BLS lookup/read path in
the current SpringBoard/Relaxin environment, not a semantic mapping and not a
physical display-state result.

## Runtime binary-search isolation

Test 1 (`dispatch_after` delayed no-op) was built and deployed without
installing `NNPController`, so Spotify UI was intentionally not applicable.

```text
workflow: 35671280332
commit: 37abe26ce8870a16aba5f89c82f59238a5c9a26a
artifact SHA256: 6CED92AA8D51FDC56A640E35342BE95376CA093BCD4DD2EE1D839BEBCC0F6BB9
remote SHA256:  6CED92AA8D51FDC56A640E35342BE95376CA093BCD4DD2EE1D839BEBCC0F6BB9
install: PASS
reload: PASS
SpringBoard PID before reload: 14653
SpringBoard PID after reload: 14725
SpringBoard PID after additional stability interval: 14725
Spotify UI: NOT APPLICABLE
Crash/Jetsam: none observed in the bounded check
Delayed no-op: PASS
```

The PID change from 14653 to 14725 is the expected `/usr/bin/sbreload`
deployment reload, not an additional runtime restart. The unchanged PID during
the follow-up interval supports that the delayed no-op itself did not restart
SpringBoard.

```text
Test 1 delayed no-op: PASS
Test 2 delayed static bool: PASS
Test 3 delayed CFPreferences: NOT RUN
Test 4 controller install: NOT RUN in this matrix step
Test 5 diagnostic helper: NOT RUN in this matrix step
Test 6 BLS class: NOT RUN
Test 7 selector: NOT RUN
Test 8 sharedBacklight: NOT RUN
Test 9 backlightState: NOT RUN
Test 10 lock callback: NOT RUN
Test 11 lock BLS read: NOT RUN

Test 2 (`dispatch_after` plus only `static volatile BOOL reached = YES`) was
also deployed without installing `NNPController`, so Spotify UI remained not
applicable. The package and remote checksum matched; the first post-reload
SSH attempt timed out while SpringBoard was returning, but a bounded retry
showed SpringBoard running at PID 14794 and a second stability check retained
PID 14794.

```text
workflow: 35671563406
commit: 833733a1167b464aeef55c89feffd04dad2680cb
artifact SHA256: 88B0CF3CA753F5DC6B85DBEEEFB12DE54DB3080B411277F54A1D1A1C50F79E5A
remote SHA256:  88B0CF3CA753F5DC6B85DBEEEFB12DE54DB3080B411277F54A1D1A1C50F79E5A
install: PASS
reload: PASS
SpringBoard PID before reload: 14725
SpringBoard PID after reload: 14794
SpringBoard PID after additional stability interval: 14794
Spotify UI: NOT APPLICABLE
Crash/Jetsam: none observed in the bounded check
Delayed static bool: PASS
```
```
