# Phase 2J — BackBoardServices Read-Only Runtime Verification

## Status

**Stopped: runtime probe was unstable and was removed before a lock-cycle test.**

The Phase 2J diagnostic package built successfully and was installed once. It
caused repeated SpringBoard Safe Mode/crash behavior shortly after reload. The
package was manually removed. No setter, IOPM assertion, brightness API, or
direct MIG request was used.

## Symbol resolution

The package contained `dlsym` resolution for:

| Function | Resolved | Called | Result |
|---|---|---|---|
| `BKSDisplayServicesStart` | intended | intended once | not safely recoverable from runtime logs |
| `BKSDisplayServicesIsScreenDisabled` | intended | attempted as part of first snapshot | runtime became unstable before usable result was captured |
| `BKSDisplayServicesGetBlankingRemovesPower` | intended | attempted as part of first snapshot when `_display` was available | runtime became unstable before usable result was captured |

The source did not call any mutation symbol.

## Main display objects

The attempted probe used the Phase 2I disassembly constant `<main>` as the
identifier and obtained a display object through the private `UIScreen`
`_display` accessor when present. This was not sufficient runtime proof that
the object/identifier pair matched the exact getter ABI. No object dump or
getter return value was safely captured.

## Awake baseline and lock timeline

Not completed. The crash occurred before a reliable awake baseline and before
the requested manual lock/wake/unlock cycle. No physical display conclusion
was recorded.

## Interpretation

Classification: **REJECTED/FAILED — runtime probe unsafe before verification**.

This does not prove that the `BKSDisplayServices*` wrappers are invalid. It
proves only that the current guessed runtime object acquisition path must not
be used in SpringBoard. The likely boundary is the display identifier/object
argument contract, but a crash report was not available in the readable crash
directories after removal, so the exact offending call is unresolved.

## Safety result

```text
BKS display setters called: NO
IOPM assertion created: NO
Brightness changed: NO
Direct MIG request: NO
powerd/backboardd injection: NO
MobileGestalt changed: NO
System binaries patched: NO
Manual lock cycle completed: NO
Package removed after instability: YES
```

## Follow-up boundary

The runtime probe is now compile-time disabled by default through
`NNP_PHASE2J_READONLY_RUNTIME=0`. No further device test should be attempted
until the exact Apple-created display identifier/object acquisition path is
recovered from an actual SpringBoard caller or a safer read-only API.
