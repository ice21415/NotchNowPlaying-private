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

## Phase 4B-3 — BLSSetPresentationOperation static resolution

### Class hierarchy

```text
BLSSetPresentationOperation (class_t 0x22fdf7c60, instance size 0x18)
  → BLSHEnvironmentOperation (class_t 0x22fdf7698, instance size 0x10)
    → NSObject
```

The class-data records identify the two classes and the superclass link. No
additional superclass or protocol-bearing execution layer was found in this
chain.

`BLSSetPresentationOperation` has one subclass ivar:

```text
+0x10  _additions       object/operation-detail collection
```

The inherited storage is:

```text
+0x08  _backlightState  q / int64_t
```

The object therefore occupies 0x18 bytes including the object header. The q
value is carried unchanged; this class contains no comparison or translation
of values 0, 1, 2, 3, or 4.

### Initializer

```text
selector: -initWithBacklightState:additions:
IMP:      0x200e0ba60
type:     @32@0:8q16@24
```

The initializer first invokes the superclass initializer with the q argument,
then stores the additions object at `+0x10`. The base initializer and getter
are:

```text
-initWithBacklightState:  0x200e0b8fc  @24@0:8q16
-backlightState           0x200e0b9d8  q16@0:8
```

The subclass methods are:

```text
-additions                0x200e0bba4  @16@0:8
-description              0x200e0bae4  @16@0:8
```

### Candidate execution methods

No operation execution selector was found. The complete relevant method sets
are data/diagnostic methods only:

| Class | Selector | IMP | reads q-state | reads additions | execution candidate |
| --- | --- | ---: | --- | --- | --- |
| BLSSetPresentationOperation | `initWithBacklightState:additions:` | `0x200e0ba60` | stores | stores | NO |
| BLSSetPresentationOperation | `additions` | `0x200e0bba4` | NO | returns | NO |
| BLSSetPresentationOperation | `description` | `0x200e0bae4` | diagnostic formatting | diagnostic formatting | NO |
| BLSHEnvironmentOperation | `initWithBacklightState:` | `0x200e0b8fc` | stores | NO | NO |
| BLSHEnvironmentOperation | `backlightState` | `0x200e0b9d8` | returns | NO | NO |
| BLSHEnvironmentOperation | `description` | `0x200e0b948` | diagnostic formatting | NO | NO |

Consequently, `BLSSetPresentationOperation` is not an `NSOperation`-like
active object in this image. There is no `execute`, `perform`, `run`, `apply`,
`start`, or `main` method to hook.

### Owner and processor

The owner is the environment state machine:

```text
owner class: BLSHBacklightEnvironmentStateMachine
owner ivar: +0x60 _lock_setPresentationOperation
```

The operation is created/replaced in the `setPresentation:withTargetBacklightState:`
continuation and is consumed by the internal helper:

```text
processor/helper: 0x200e087b8
input:            environment-state-machine self plus continuation context
operation read:   self +0x60
```

The helper is reached by direct branches from the environment update blocks at
`0x200e07e38`, `0x200e07e80`, `0x200e09940`, `0x200e0a844`,
`0x200e0a868`, and `0x200e0b078`. Within that helper, the operation slot is
read and the base `backlightState`/subclass `additions` data is consumed through
the internal object-processing path. A small follow-on helper at
`0x200e0ab14` handles the operation-related comparison/update step.

```text
BLSHBacklightEnvironmentStateMachine
  +0x60 _lock_setPresentationOperation
      ↓
internal update helper 0x200e087b8
      ↓
operation data getters / helper 0x200e0ab14
```

The scheduling context is block-based and serialized with the environment
state-machine update path. The exact dispatch queue label is not present in
the bounded static slice, so the queue is reported as `UNRESOLVED`; no
independent operation queue or `NSOperationQueue` consumer was found.

### Downstream calls and external boundary

The direct callees reached from the operation-consuming helper remain inside
the BacklightServicesHost image or its runtime/object-management support:

```text
0x200e087b8 → 0x200e0ab14
0x200e087b8 → internal presentation/update helpers
operation getters → object-processing/runtime helpers
```

No direct call from this bounded operation path to a `BKSDisplayServicesSet*`
symbol, BackBoardServices display setter, QuartzCore display transaction, IOKit
display function, or panel-power API was proven. The known BKS landmarks are
therefore `NOT REACHED` in this slice, rather than direct or wrapper calls.

```text
BackBoard handoff: UNRESOLVED
BKS relationship: NOT REACHED in the bounded operation path
first physical boundary: UNRESOLVED
```

This is a negative scope result, not evidence that no deeper display path
exists anywhere in the system.

### Previous environment setter relevance

The setter remains statically valid as an operation-construction/update path,
but its passive runtime hook produced no events for the observed lock/unlock
transition (`EnvSetPresentationCount = 0`, `Sequence = 0`). Therefore its
relevance to the observed side-button path is:

```text
UNLIKELY for the observed runtime transition
```

It may still serve an alternate environment/session path. The zero-event
result does not justify calling it globally dead, but it does exclude it as a
proven runtime boundary for this experiment.

### Exact bounded graph

```text
BLSHBacklightEnvironmentStateMachine
  setPresentation:withTargetBacklightState:
    creates/replaces BLSSetPresentationOperation
      initWithBacklightState:additions:
    stores at +0x60

environment update block
    → helper 0x200e087b8
    → BLSHEnvironmentOperation backlightState / additions data
    → helper 0x200e0ab14 and internal presentation/update work
    → no proven BackBoard/BKS handoff in this bounded slice
```

No new runtime hook is justified by this static result. A hook on
`0x200e087b8` would be a function-level internal hook rather than an exact
Objective-C execution selector and would need a separate authorization/repair
phase; it is not added here.

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
