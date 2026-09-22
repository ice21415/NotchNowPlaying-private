# Phase 4B — Display Boundary Trace

Observational-only Phase 4B-1. No BLS request, BKS setter, assertion,
brightness change, lock API, wake/unblank operation, or target-state mutation
was performed.

## Phase 4A baseline

```text
awake provider state: 2
lock provider state: 0
```

## Static candidate chain

The smallest previously validated chain is:

```text
BLSHBacklightTransitionStateMachine -performEvent:
  event state → _backlightState (+0x50)
  helper 0x200e2d198 → _lock_targetState (+0xa0)
  targetState setDisplayMode: at 0x200e2fe58
  helper 0x200e2f598
  targetState setPresentation: at 0x200e2f71c
  current aggregate/environment presentation update
```

The target-state comparison site is the transition/update helper at
`0x200e2d5d4`–`0x200e2d5f0`:

```text
current = [_currentState displayMode]
target  = [_lock_targetState displayMode]
compare current and target
```

The next statically bounded environment operation is
`-[BLSHBacklightEnvironmentStateMachine setPresentation:withTargetBacklightState:]`
at `0x200e074d8`. Its operation object carries the q-valued target state, but
the recovered operation does not translate modes 0/1/4 into panel-power names.

## Runtime target-state observation

A passive hook on the existing
`BLSHBacklightTransitionStateMachine -performEvent:` called the original method
unchanged, then read the existing `_lock_targetState` object and its
`displayMode` getter. It recorded only the first matching awake and lock modes.

```text
Phase 4B-1 workflow: 35678617867
artifact SHA256: 4C1B571451F5C44E57BDE87DA7AFA0C8E9246FCBA07635750C4EA550438D22F5
target class: BLSHBacklightMutableTargetState
sequence: 2
```

```text
awake provider state: 2
awake displayMode: 4
lock provider state: 0
lock displayMode: 0
```

This confirms the runtime correlation for the observed conditions:

```text
provider 2 → target displayMode 4
provider 0 → target displayMode 0
```

The observation does not establish that mode 0 means panel power off.

## Presentation

The same passive observation read the existing target presentation ivar only
for class identity.

```text
awake presentation: BLSHBacklightEnvironmentPresentation
lock presentation: BLSHBacklightEnvironmentPresentation
```

No presentation object was modified or dumped.

## Downstream consumer

```text
class: BLSHBacklightEnvironmentStateMachine
selector: setPresentation:withTargetBacklightState:
arguments: derived BLSHBacklightEnvironmentPresentation, target q state
ordering: statically after target presentation preparation
```

The immediate target-state comparison is proven, but a runtime hook on the
environment operation has not been added. The first consumer that crosses
into a physical display service remains unresolved.

## Physical boundary status

```text
CORRELATED at provider/target-state level
physical panel boundary: UNRESOLVED
BackBoard/display-service handoff: UNRESOLVED
```

The result is sufficient to establish the requested provider-to-target
correlation, but not sufficient to label mode 0 as physical panel-off or to
identify a first hardware boundary. The next bounded static target, if
continued, is the exact implementation/call chain of
`setPresentation:withTargetBacklightState:` toward its environment operation;
no display mutation is justified.

## Phase 4B-2 environment operation trace

Static candidate:

```text
environment selector:
  setPresentation:withTargetBacklightState:
implementation:
  BLSHBacklightEnvironmentStateMachine, IMP 0x200e074d8
operation:
  BLSSetPresentationOperation
initializer:
  initWithBacklightState:additions:
```

The recovered implementation stores the presentation and q-valued target
state, constructs/replaces the operation, and enters the environment update
path. The operation inherits its q storage from `BLSHEnvironmentOperation`.
No direct BKS/display-service call has been proven in the bounded static slice.

For Phase 4B-2, a passive hook called the original setter unchanged and
persisted a fresh build identity plus zeroed sequence counter. After reload,
awake Spotify playback, and one ordinary manual side-button transition:

```text
environment hook: NO EVENT OBSERVED
EnvSetPresentationCount: 0
Sequence: 0
```

The pre-existing provider/target fields visible in the preference file were
not used as new Phase 4B-2 evidence because they were not written by this
environment-hook build. No operation or BackBoard hook was added after this
negative result.

## External handoff

```text
caller: BLSHBacklightEnvironmentStateMachine setPresentation... path
callee: BLSSetPresentationOperation initializer / environment operation path
framework: BacklightServicesHost
receiver: environment-state-machine-owned operation state
arguments: q target state plus additions/presentation context
```

```text
BackBoard handoff: UNRESOLVED
BKS relationship: UNRESOLVED
first display-service boundary: UNRESOLVED
first physical-boundary candidate: UNRESOLVED
```

The absence of a runtime setter event means the environment hook cannot yet be
used to establish ordering. The next safe action is one bounded static
resolution of the operation execution selector/process ownership, not another
runtime hook or any display operation.

## Unlock retry

One ordinary user unlock was performed after the zero-event lock observation,
followed by one persistent-diagnostics read. The fresh hook-owned fields were
unchanged:

```text
EnvSetPresentationCount: 0
Sequence: 0
```

Therefore the missing setter event is not explained merely by reading too
early after the lock transition. The older target/provider fields remain
excluded from this hook result because this build did not write them.
