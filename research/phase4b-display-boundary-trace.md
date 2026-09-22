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

## Phase 4B-4 — Confirmed `performEvent:` mode-0 branch

### `performEvent:` CFG

```text
-[BLSHBacklightTransitionStateMachine performEvent:]
  → read event state
  → compare/store self->_backlightState (+0x50)
  → prepare/retrieve self->_lock_targetState (+0xa0)
  → mode helper 0x200e2d338(self, newReportedState, ...)
  → [targetState setDisplayMode:mode]
  → helper 0x200e30044(self, event/context, currentState,
                       targetState, oldEqualsNew, pendingEvent)
  → subsequent transition/notification machinery
```

The call at `0x200e2fe80` is the first downstream continuation after the
target display-mode store. Its receiver is the transition-state-machine
object; the target-state object is supplied as an explicit argument. This
helper is internal to `BacklightServicesHost`, not a proven display-service
boundary.

### Mode-0 branch condition

```text
inputs:       new reported event state
comparison:   newState == 0
taken target: mode helper 0x200e2d338 returns
              [policyObject isAlwaysOnSuppressed]
```

The mode-selection helper handles state `3`, then state `1`, and reaches the
zero-state path only when `newState == 0`. The returned q value is the
suppression/policy result, which is the already-observed target mode `0` for
the manual lock transition. This does not give mode `0` a physical panel
meaning.

```text
mode-0 first helper:  0x200e2d338
mode-0 second helper: 0x200e30044
```

### Helper ABI and provenance

```text
0x200e2d338:
  x0 = BLSHBacklightTransitionStateMachine self
  x1 = new reported backlight state
  return = q display-mode value
  reads = policy object derived from self +0x48; suppression getter
  writes = none proven in the bounded slice

0x200e30044:
  x0 = transition-state-machine self
  x1 = retained event/context object
  x2 = current aggregate state self +0x98
  x3 = mutable target state self +0xa0
  x4 = old/new equality flag
  x5 = pending/prewarmed event context
  return = internal transition/update result
```

The second helper is the first mode-independent continuation after
`setDisplayMode:`. Its inspected bounded slice contains internal
BacklightServicesHost calls, but no proven direct BKS, BackBoardServices,
QuartzCore display-transaction, IOKit, or panel-power call.

### Runtime branch observation

The existing passive `performEvent:` observation called the original method
unchanged and recorded the resulting target state:

```text
awake:       provider state 2 → target displayMode 4
manual lock: provider state 0 → target displayMode 0
```

Thus the mode-0 outcome is runtime-confirmed at the target-state boundary. No
additional internal-function hook was added because it would add risk without
exposing a new physical-boundary fact at this stage.

```text
runtime mode-0 branch: PASS
awake branch: state 2 → mode 4 → generic continuation 0x200e30044
lock branch: state 0 → mode 0 → generic continuation 0x200e30044
```

### External handoff and physical boundary

```text
external handoff: not proven in the bounded mode-0 continuation
framework: BacklightServicesHost internal
BackBoard/BKS relationship: NOT REACHED in the inspected slice
first display-service boundary: UNRESOLVED
first physical-boundary candidate: UNRESOLVED
```

The mode-0 branch is resolved through the first internal helper and
runtime-confirmed at the target-state boundary, but the inspected continuation
does not establish a display-service or physical blanking boundary. If more
work is authorized, inspect exactly one bounded downstream helper layer from
`0x200e30044`; no display mutation is justified.

## Phase 4B-5 — First downstream layer from `0x200e30044`

### `0x200e30044` CFG

The bounded implementation spans `0x200e30044`–`0x200e306a4`. Its entry
arguments are preserved as follows:

```text
x0 → x23   transition-state-machine self
x2 → x22   current aggregate/state input
x3 → x21   target-state argument at entry
x4 → x26   old/new equality flag
x5 → x20   pending/prewarmed event context
```

The entry copy of `x3` is overwritten at `0x200e300c8` before any target-state
getter or target-state field load is performed. No later instruction in this
bounded function reloads the original target-state argument from a saved stack
slot or another register.

The direct-call/branch structure is:

```text
0x200e3008c–0x200e300a8  internal state/context acquisition
0x200e300b0               branch on old/new equality flag
0x200e300b4–0x200e300cc  internal context/presentation preparation
0x200e300d8–0x200e3010c  presentation, presentationEntries, count processing
0x200e30110               compare an entry/count-derived value with 2
0x200e301d8               differenceFromPresentation: on derived presentations
0x200e30208–0x200e30218  count calls on derived collection objects
0x200e30220–0x200e30318  event/context and derived-object field preparation
0x200e30320–0x200e30478  identity/presence branches and internal collection work
0x200e30480–0x200e30548  construct a 0x98-byte internal record
0x200e3056c               pass that record to shared/internal helper 0x2068c02c0
0x200e30570–0x200e30668  cleanup/release paths
```

### State-dependent call sites

| Call site | Callee/operation | Target-state dependency | DisplayMode dependency | Condition |
| --- | --- | --- | --- | --- |
| `0x200e300b0` | internal preparation | NO | NO | `oldEqualsNew` |
| `0x200e300d8` | `presentation` on derived `x22` | NO direct target proof | NO | `self/context` valid |
| `0x200e300ec` | `presentation` on stack-derived object | NO direct target proof | NO | same preparation path |
| `0x200e300f8` | `presentationEntries` | NO direct target proof | NO | derived presentation exists |
| `0x200e30104` | `count` | NO | NO | derived entries path |
| `0x200e30110` | integer comparison | NO | NO | entry/count-derived value `>= 2` |
| `0x200e301d8` | `differenceFromPresentation:` | NO direct target proof | NO | derived presentation identity/path |
| `0x200e30208` | `count` | NO | NO | derived collection |
| `0x200e30214` | `count` | NO | NO | derived collection |
| `0x200e302f0` | `displayMode` getter | NO direct target proof | YES, derived receiver | unconditional on active path |
| `0x200e30308` | `displayMode` getter | NO direct target proof | YES, derived receiver | unconditional on active path |
| `0x200e3056c` | internal/shared helper `0x2068c02c0` | NO direct target proof | YES, receives record containing getter results | record complete |

The two `displayMode` calls are the earliest displayMode-related operations,
but their receivers are derived objects already produced inside this helper;
they are not the `x3` target-state object. Their returned q values are copied
into the record assembled at `0x200e30480`–`0x200e30548`. The record is then
passed to `0x2068c02c0` with size `0x98` at `0x200e3056c`.

### First target/mode-dependent call

```text
exact targetState.displayMode consumer: NOT PRESENT in this layer
earliest derived displayMode getters: 0x200e302f0 and 0x200e30308
first call receiving their propagated record: 0x200e3056c → 0x2068c02c0
```

```text
receiver provenance:
  0x200e302f0/0x200e30308 use derived collection/presentation objects;
  neither receiver is proven to be x3 at the call site.

arguments at 0x200e3056c:
  x0 = internal record/type context
  x1 = previously prepared object/context
  x2 = equality-derived size/flag
  x3 = internal descriptor/context
  x4 = pointer to the 0x98-byte record
  x5 = 0x98
```

Because the original target-state argument is dead within this helper, a
mode-4 versus mode-0 branch split cannot be assigned to `0x200e30044`.

```text
MODE 4: no target-mode branch in this helper; same internal path
MODE 0: no target-mode branch in this helper; same internal path
```

### Callee classification and external-boundary check

```text
0x200e302f0 / 0x200e30308:
  BacklightServicesHost internal/derived-object getter calls

0x200e3056c → 0x2068c02c0:
  shared/internal record-construction or handoff helper;
  no Objective-C selector or external display-service symbol is proven here
```

Expanding the shared thunk target one level identifies internal runtime/helper
code, not a direct `BKS*`, BackBoardServices, QuartzCore display transaction,
IOKit, blanking, screen-disabled, or power-removal call. Therefore:

```text
BackBoard handoff: NO in this bounded layer
BKS relationship: NOT REACHED
first display-service boundary: UNRESOLVED
```

### Next safe runtime hook

No new hook is justified by this layer. A hook on `0x200e3056c` would observe
an internal record after the mode getters but would not prove that the record
came from the mutable target state or that it crosses to display services.
The next bounded static target, if continued, is the single helper receiving
the `0x98`-byte record at `0x2068c02c0`/its resolved target, without recursive
fan-out.
