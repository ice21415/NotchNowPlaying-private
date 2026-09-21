# Phase 4A — Read-Only Backlight Observation

This phase prepared one disabled-by-default observational path. It was not
built, installed, enabled, or run, and no device was accessed. Consequently,
no state values are claimed in this report.

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

## Phase 4B recommendation

```text
B — the prepared observation is informative, but one bounded read-only
    correlation would still be required before semantic feature use. No
    observation has been performed in this offline workspace.
```

No display mutation was performed.
