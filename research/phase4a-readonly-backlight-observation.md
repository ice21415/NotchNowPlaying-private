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
