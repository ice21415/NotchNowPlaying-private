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

## Phase 4B-6 — `0x2068c02c0` record handoff

### Resolution

```text
original address:  0x2068c02c0
type:              shared-cache branch thunk
resolved target:   0x1a1377b18
image/framework:   /usr/lib/system/libsystem_trace.dylib
symbol:            internal/unresolved; no Objective-C selector
```

The thunk is:

```text
0x2068c02c0:
  adrp x16, 0x1a1377000
  add  x16, x16, #0xb18
  br   x16
```

It is therefore not an Objective-C message wrapper, PLT/GOT display call, or
BackBoard entry point.

### ABI and record handling

The call-site ABI is preserved by the resolved implementation:

```text
ARG0: context/type pointer; retained into the temporary record
ARG1: prepared object/context; forwarded to the trace helper
ARG2: flags/status word; masked and used to form trace metadata
ARG3: descriptor/format context; forwarded into the temporary record
ARG4: pointer to the 0x98-byte record
ARG5: record length, 0x98
RETURN: void-like internal trace dispatch; no useful value returned to the caller
```

At `0x1a1377b18`, the implementation first copies `x4` to `x20` and `x5` to
`x19`, builds a small stack record, derives metadata from `x2`, and calls the
next internal routine:

```text
0x1a1377bcc:
  x0 = address of newly built trace metadata on the stack
  x1 = prepared context
  x2 = flags/status
  x4 = original 0x98-byte record pointer
  x5 = original 0x98-byte record length
  x6 = 0
  bl  0x1a1377be8
```

```text
record first use:  copied from x4 to callee-saved x20; x5 copied to x19
record second use: passed unchanged as x4/x5 to 0x1a1377be8
record escapes function: YES
```

No field-level display-mode comparison occurs in this helper. The `0x98`
bytes are treated as an opaque trace/log payload at this boundary.

### Destination and ownership

```text
record destination: libsystem_trace internal helper 0x1a1377be8
semantic owner:     system trace/log infrastructure
framework class:    generic system runtime, not BacklightServices semantic state
```

The first layer therefore dispatches/copies the record into generic tracing
infrastructure. It does not identify the display consumer that semantically
owns the record.

### IPC and display-boundary checks

Within the resolved thunk and its immediate implementation layer:

```text
IPC present:              NO direct xpc_connection/mach_msg/MIG/NSXPC call
IPC destination:          UNRESOLVED beyond this generic trace layer
display-service references: none
BackBoard handoff:        NO
BKS relationship:         NOT REACHED
```

The inner trace routine contains an authenticated indirect runtime call and
continues into system tracing code, but expanding that generic transport would
not be a display-semantic continuation. Accordingly, `0x2068c02c0` is
classified as:

```text
A — generic runtime helper only
```

The next semantic display boundary is not the trace helper. No runtime hook is
recommended for `0x2068c02c0`; the next useful target would be the semantic
producer/caller that constructs the `0x98`-byte payload, not the generic trace
transport.

## Phase 4B-7 — Non-trace semantic side effects of `0x200e30044`

### Call classification

The complete bounded call inventory falls into these groups:

```text
OBJECT LIFETIME:
  0x2068c04c0, 0x2068c05c0, 0x2068c05d0, 0x2068c05e0,
  0x2068c0610, 0x2068c0630, 0x2068c0640, 0x2068c0650,
  0x2068c0670, 0x2068c0690 and related shared retain/release helpers

READ-ONLY GETTER / PRESENTATION DIFF:
  presentation
  presentationEntries
  count
  firstObject
  flipbookContext
  differenceFromPresentation:
  insertions / removals
  eventID / previousState / state / sourceEvent / changeRequest

OBJECT CONSTRUCTION:
  initWithPresentationEntries:flipbookContext:expirationDate:

TRACE/LOGGING:
  string/short logging-description helpers and
  0x200e3056c → 0x2068c02c0

INTERNAL RECORD/STACK PREPARATION:
  0x200e30480–0x200e30548 stack stores

UNKNOWN SHARED RUNTIME HELPERS:
  0x2068c01d0, 0x2068c01e0, 0x2068c02c0, 0x2068c0270,
  and the other non-ARC shared thunks; none is proven here to be a
  display-service or state-commit call
```

No direct BKS, BackBoardServices, QuartzCore, IOKit, XPC, MIG, or Mach call is
reachable in this function after trace calls are excluded.

### Reduced non-trace CFG

```text
current/context objects
  → presentation / entries / collection getters
  → presentation difference calculation
  → derived presentation/object construction
  → event/context getters and collection-derived values
  → two derived displayMode getters
  → stack-only record assembly
  → trace/log helper (excluded from semantic graph)
  → lifetime cleanup
```

There is no direct setter on `_currentState`, `_lock_targetState`, a provider,
an environment session, or a display controller in this bounded function.

### Derived displayMode receiver provenance

```text
getter 0x200e302f0:
  receiver: x22, an object derived from the current/context input through the
            preceding internal preparation calls
  semantic role: derived current/presentation-side object; exact concrete
                 class is not recoverable from this call site alone

getter 0x200e30308:
  receiver: object loaded from the earlier stack-derived context slot
  semantic role: second derived presentation/context-side object; it is not
                 the original x3 mutable target-state argument
```

The original `x3` target-state argument is copied to `x21` at entry and then
overwritten at `0x200e300c8`. No target getter or target ivar load occurs in
the remainder of the function.

### DisplayMode semantic usage

The two getter results are stored at stack offsets `+0x80` and `+0x78`, then
copied into the 0x98-byte record assembled at `0x200e30480`–`0x200e30548`.
They are not compared, used as branch conditions, passed to a setter, or used
to select a state-machine transition in this function.

```text
displayMode used outside trace: NO
```

This is a statement about this helper: it does not exclude use by the upstream
producer or by a later semantic consumer elsewhere.

### State writes and callbacks

```text
direct object ivar writes: NONE proven
direct target/presentation setter calls: NONE
collection mutation: NONE proven; diff/collection values are read/constructed
block scheduling: NONE proven
notifications/delegates/completions: NONE proven
transaction commit: NONE proven
```

The apparent writes between `0x200e30480` and `0x200e30548` are stores to a
stack-local serialized/trace record, not writes to a system object or display
state.

### First semantic side effect after mode reads

```text
NO SEMANTIC SIDE EFFECT AFTER MODE READS
```

The first operation after the two mode getters that consumes their values is
record construction, followed by the already-resolved generic trace helper.
There is no state mutation or callback after those reads in this function.

### Semantic role and next target

```text
0x200e30044 semantic role:
  presentation-difference / transition bookkeeping with diagnostic record
  generation; not the target-state commit or display-control boundary

external handoff: NO in this helper
BackBoard/BKS relationship: NOT REACHED
next semantic trace target:
  the upstream caller/commit path that invokes 0x200e30044 and then performs
  the actual target/current state application; do not trace libsystem_trace
```

No runtime hook is recommended for this helper. A hook here would only repeat
record/diagnostic activity and would not answer where mode 0 propagates next.

## Phase 4B-8 — `performEvent:` post-bookkeeping commit path

### `0x200e30044` call site

```text
call address:   0x200e2fe80
callee:         0x200e30044
return address: 0x200e2fe84
```

Immediately after return, the code compares the already-held old/new reported
state values:

```text
0x200e2fe84: cmp x25, x21
0x200e2fe88: b.eq 0x200e2feac
```

The return register `x0` from `0x200e30044` is not consumed as a result. It is
overwritten by the subsequent branch helper/predicate calls.

### Post-call CFG

```text
0x200e2fe84
  ├─ oldState == newState
  │    → 0x200e2feac
  │
  └─ oldState != newState
       → predicate 0x2068bffb0(newState)
          ├─ true  → helper 0x200e2e6a0(self)
          └─ false → helper 0x200e2cfec(self)
       → 0x200e2feac

0x200e2feac
  → [self +0x38 invalidate:]
  → [self +0x20 scheduleWatchdogWithDelegate:explanation:timeout:]
  → store returned object to self +0x38
  → helper 0x200e2d454(self)
  → cleanup and return
```

The two branch helpers are the first non-trace calls after bookkeeping. Their
bounded bodies show transition-slot mutation:

```text
0x200e2e6a0:
  clears self +0x40

0x200e2cfec:
  computes a transition object and stores it to self +0x40
```

These are transition-state updates, not writes to `_currentState (+0x98)` or
`_lock_targetState (+0xa0)`.

### Current-state usage

```text
reads after 0x200e30044: NONE
writes after 0x200e30044: NONE
replacement: NONE
```

The post-call code does not load `self +0x98`, construct a new aggregate
state, or invoke an aggregate-state setter.

### Target-state usage

```text
reads after 0x200e30044: NONE
writes after 0x200e30044: NONE
consumed by: NONE proven
target escapes performEvent after the call: NO
```

The target object is supplied to `0x200e30044` in `x3`, but that helper does
not retain or read the original argument. After the call, the saved target
register is not used again before `performEvent:` returns.

### First post-bookkeeping semantic mutation

```text
address:       0x200e2fe98 or 0x200e2fea4 call site
operation:     state-dependent transition helper
object:        BLSHBacklightTransitionStateMachine self
offset:        +0x40 transition slot
value source:  event-state predicate and helper-produced transition object
classification: TRANSITION STATE MACHINE update
```

The direct aggregate/current-state commit is absent. The later `+0x38`
sequence is a separate invalidation/watchdog lifecycle update:

```text
0x200e2feac: receiver [self +0x38], selector invalidate:
0x200e2fef4: scheduleWatchdogWithDelegate:explanation:timeout:
0x200e2ff00: self +0x38 = returned watchdog/operation object
```

The exact ivar declaration names for `+0x38` and `+0x40` are not needed to
establish that they are transition-machine lifecycle slots; neither is the
known aggregate or mutable target state field.

### Caller-layer check

The known caller invokes `performEvent:` at `0x200e12958`. After the call,
its return value is not read; the caller performs only cleanup/lifetime work
before returning. No current/target aggregate commit is visible in this one
caller layer.

### Callback and external handoff

```text
callback/event propagation:
  internal transition helpers 0x200e2e6a0 / 0x200e2cfec
  watchdog invalidation/scheduling through +0x38

external framework handoff: NONE proven
BackBoard/BKS relationship: NOT REACHED
XPC/MIG/Mach/QuartzCore/IOKit: NONE proven in this bounded post-call path
```

This establishes a logical transition-state/lifecycle update, not a display
service handoff or physical blanking operation. The resolved target mode does
not escape `performEvent:` through the post-bookkeeping code.

```text
semantic commit classification:
  LOGICAL TRANSITION-STATE UPDATE
  not aggregate current-state commit
  not display-service or physical boundary

next trace target:
  one bounded caller/producer of transition slot +0x40, if needed;
  no runtime hook is justified at this point
```

## Phase 4B-9  Transition-slot +0x40 consumer

### +0x40 object

The slot is not a transition-state object.  Its concrete class is:

```text
class: BLSAssertion
slot:  BLSHBacklightTransitionStateMachine +0x40
```

The class identity is supported by the decoded global class pointer at
`0x22ed5b0d0`, which is `BLSAssertion`, and by the two selectors sent to the
stored object:

```text
0x200e8bd60  isActive
0x200e8bc00  invalidate
```

### Creator

`0x200e2cfec` is the creator/replacement path.  Its bounded object flow is:

```text
old = [self +0x40]
if (old != nil && [old isActive])
    return

touchLock = [BLSTouchLockAttribute touchLock]
inactive = [BLSValidWhenBacklightInactiveAttribute
             ignoreWhenBacklightInactivates]
attributes = [NSArray arrayWithObjects:... count:2]
newAssertion = [BLSAssertion acquireWithExplanation:observer:attributes:]
self +0x40 = newAssertion
```

The exact explanation/observer arguments are prepared by the surrounding
constant/object data, but no display state is modified by this helper.  The
meaningful operation is assertion acquisition and storage, not transition
state publication.

### Clear path

`0x200e2e6a0` is the clear/invalidate path:

```text
old = self +0x40
self +0x40 = nil
[old invalidate]
```

The old object is retained/lifetime-managed around the clear.  The helper is
selected by the post-bookkeeping state predicate; it is not a current-state
or target-state replacement.

### Meaningful readers

Receiver provenance restricts the relevant `+0x40` accesses to this pair:

| address | containing helper | read/use | classification |
|---|---|---|---|
| `0x200e2d02c` | `0x200e2cfec` | load `self+0x40`, send `isActive` | predicate / assertion lifecycle |
| `0x200e2e6c8` | `0x200e2e6a0` | load old object before clearing slot | invalidation / lifetime |
| `0x200e2d0dc` | `0x200e2cfec` | reload slot immediately before store | replacement/lifetime, not a downstream consumer |
| `0x200e2e6cc` | `0x200e2e6a0` | store zero to slot | state cleanup |
```

Image-wide raw `+0x40` matches include unrelated classes and scalar/stack
fields.  They are not attributed to this slot without receiver provenance.
No additional transition-machine reader was established.

### Consumer graph

```text
performEvent: state predicate
  ├─ active assertion → [BLSAssertion isActive]
  │                    └─ keep existing +0x40 assertion
  ├─ inactive/missing assertion
  │    └─ acquire BLSAssertion → store +0x40
  └─ clear branch
       └─ clear +0x40 → [BLSAssertion invalidate]

post-bookkeeping
  └─ +0x38 watchdog invalidate/schedule
```

### Watchdog relationship

`+0x38` is a separate lifecycle/watchdog slot.  The post-bookkeeping path sends
`invalidate` to the old `+0x38` object, then schedules a new watchdog with
`self` as delegate and stores the returned object back at `+0x38`.  No direct
read of `+0x40` by that watchdog path was proven.  The two slots are therefore
coordinated lifecycle guards, not a proven watchdog-to-assertion callback.

```text
watchdog role: invalidate/rearm transition lifecycle monitoring
callback/delegate: transition-state-machine self
reads +0x40: NO evidence in the bounded path
```

### Target/current bridge and downstream state

```text
target/current bridge: NOT FOUND
current aggregate commit: NOT FOUND
downstream state/object: BLSAssertion lifecycle state
external handoff: NONE proven
BackBoard/BKS: NOT REACHED
IPC/XPC/MIG/Mach: NONE proven
```

The first semantic consumer is `[BLSAssertion isActive]`; the first semantic
mutation is acquisition/replacement or invalidation of the assertion object.
This remains a transition-lifecycle layer.  It does not explain the physical
display boundary and does not provide a justified runtime hook for the next
stage.

```text
runtime-hook candidate: NONE
next safe trace target: one exact completion receiver outside +0x40, only if
                         a new static xref identifies it
```

## Phase 4B-10  Focused target-to-display-state consumer

### Question

The `+0x98`/`+0xa0` fields do not get replaced in the post-bookkeeping tail of
`performEvent:`.  The next focused question was where the target mode escapes
into the transition machinery that applies a display-state operation.

### Target-state operation factory

The helper at `0x200e308ec` is a receiver-proven operation factory.  Its
relevant data flow is:

```text
self +0x98                         -> [currentAggregate displayMode]
argument x1                         -> target displayMode
self +0x88                         -> pending/current operation context
argument x2                         -> null-operation policy flag

BLSHPendingUpdateDisplayMode
  operationForUpdateFromCurrentDisplayMode:
      current mode
  toTargetDisplayMode:
      target mode
  withPendingOperation:
      self +0x88
  isNullOperationAllowed:
      x2
```

The returned operation is then queried for `rampOperation`; when the ramp
duration is zero, the operation's duration is filled from the transition
machine's `+0xf0` fade-out duration.  This is not a trace-only path: it
constructs the current-to-target display-mode operation used by the transition
machinery.

### First exact display-mode consumer

The strongest bounded execution path is helper `0x200e32170`.  Its relevant
receiver and argument provenance are exact:

```text
x21 = transition-state-machine self
x19 = pending/transition operation produced by the surrounding path

x23 = [x19 targetDisplayMode]
x0  = [x21 + 0xf8]
x2  = x23
d0  = saved ramp duration

0x200e32370:
    [x21 + 0xf8 setDisplayMode:x23 withRampDuration:d0]
```

The selector dispatch is the authenticated/optimized selector stub resolved
as `setDisplayMode:withRampDuration:`.  Therefore this is the first exact
non-trace call in the recovered path whose argument is the target display mode
and whose receiver is an existing object owned by the transition state
machine.  It is downstream of the pending-operation construction and is not a
guessed receiver.

Immediately afterward the same helper loads `x21 + 0x30`, derives a boolean
from the target operation, and sends `setOnStandby:`.  That adjacent call is
classified as presentation/standby lifecycle state, not as proof of panel
power control.

### Receiver classification

The exact concrete class of `self + 0xf8` is not independently recovered from
validated Objective-C method metadata in this pass.  The aggregate-state
metadata declares its display-mode source as:

```text
BLSHBacklightDisplayStateMachine
```

and the `+0xf8` object is used through the matching display-mode operation
selector.  This supports the following conservative classification:

```text
receiver storage: exact — transition-machine +0xf8
receiver role: display-state-machine/display-mode consumer
concrete class: likely BLSHBacklightDisplayStateMachine; metadata proof pending
```

The class name is not promoted to exact solely from selector similarity.

### Mode paths

The already-confirmed runtime target values feed this same consumer path:

```text
awake:
  provider state 2
  target displayMode 4
  targetDisplayMode argument -> 4

manual lock:
  provider state 0
  target displayMode 0
  targetDisplayMode argument -> 0
```

Static evidence shows one selector with different numeric arguments, rather
than two independently named physical-display branches.  This establishes a
target-to-display-state-machine handoff, not yet a panel-power operation.

### One-layer external-boundary check

Within `0x200e32170` and the bounded target-operation factory:

```text
BackBoardServices/BKS direct call: none proven
XPC/MIG/Mach call: none proven
QuartzCore/CoreDisplay/IOKit call: none proven
trace calls: present elsewhere and excluded
```

The call at `0x200e32370` is therefore classified as:

```text
TARGET STATE -> DISPLAY-STATE-MACHINE / LOGICAL TRANSITION
```

It is not yet a display-service or physical-boundary proof.

### Target/current bridge status

There is no direct `self +0xa0 -> self +0x98` replacement in the analyzed
`performEvent:` tail.  The bridge is instead operation-based:

```text
current aggregate +0x98
  + target mode from mutable target/transition operation
  -> BLSHPendingUpdateDisplayMode operation
  -> targetDisplayMode
  -> [self +0xf8 setDisplayMode:withRampDuration:]
```

The applied/current aggregate replacement and any later provider publication
remain unresolved.

### Next safe observation

One passive runtime hook is justified at the exact selector:

```text
setDisplayMode:withRampDuration:
```

The hook must preserve receiver, mode, duration, return behavior, and all
other arguments.  It should log only sequence, receiver class, mode, and
duration, then call the original implementation unchanged.  No BLS request,
BKS setter, assertion, brightness, wake, or lock operation is involved.

The next static layer, if the hook confirms the call, is the implementation of
that receiver's `setDisplayMode:withRampDuration:` method.  That single layer
must be checked for a current-state commit, provider publication, IPC, or an
external display-service call before any deeper tracing is considered.

```text
classification:
  A — first target-mode-dependent downstream consumer resolved
  applied/current state: unresolved
  display-service handoff: unresolved
  physical blanking/power boundary: unresolved

## Phase 4B-11  CoreBrightness display-client boundary check

### Question

The first target-mode consumer is the existing
`BLSHBacklightDisplayStateMachine`, which calls
`-[BLSHBacklightOSInterfaceProvider transitionToDisplayMode:withDuration:]`.
The provider implementation then loads its `_displayStateClient` ivar at
offset `+0x38` and sends
`transitionToDisplayMode:withDuration:error:` to that object.  The next
bounded question was whether that lower receiver exists and is reached during
the naturally occurring transition.

### Static evidence

Runtime metadata resolves the lower class and method without invoking it:

```text
class: CBDisplayStateClient
framework: /System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness
selector: transitionToDisplayMode:withDuration:error:
runtime IMP: 0x1d5c7bc34
runtime image base: 0x1d5b18000
static image base: 0x1b80c8000
static IMP: 0x1b822bc34
```

The provider metadata is receiver-proven:

```text
provider class: BLSHBacklightOSInterfaceProvider
ivar: _displayStateClient
offset: +0x38
type: CBDisplayStateClient
```

The CoreBrightness implementation has a nontrivial display-mode transition
routine and returns a boolean/error-style result.  This makes it a strong
display-service/physical-boundary candidate if a live receiver is present,
but static class ownership alone does not prove that the observed transition
reaches it.

### Runtime evidence

The passive display-mode hook observed the normal mode calls:

```text
awake: provider=2, displayMode=4
lock baseline: provider=0, displayMode=0
display-mode receiver: BLSHBacklightDisplayStateMachine
downstream receiver: BLSHBacklightOSInterfaceProvider
_displayStateClient pointer before call: 0x0
_displayStateClient pointer after call: 0x0
```

The class-level passive hook on
`CBDisplayStateClient -transitionToDisplayMode:withDuration:error:` recorded
no call during the post-reload observations.  No arguments were changed and
no display operation was invoked by the diagnostic code.

### Classification

```text
target state: confirmed
logical display-state transition: confirmed
BacklightServicesHost -> CoreBrightness object: candidate only
CoreBrightness method reached by observed transition: not observed
physical boundary: unresolved
```

The nil `_displayStateClient` is significant: the observed
`BLSHBacklightOSInterfaceProvider` instance does not currently provide a live
CoreBrightness receiver for this path.  Therefore it would be incorrect to
declare `CBDisplayStateClient` as the physical boundary yet.  The next bounded
observation is one ordinary manual side-button lock transition with the
class-level passive hook still installed; a nonzero call count would confirm
the handoff, while zero would rule out this provider-to-CoreBrightness path
for the tested instance and require pivoting to the provider's other state or
service path.

```text
next semantic target: natural lock transition with CBDisplayStateClient hook
next runtime hook: none beyond the existing class-level passive hook

## Phase 4B-12  Provider field receiver pivot

### Question

Because the provider's `_displayStateClient` was nil and the
`CBDisplayStateClient` class-level hook saw no calls, the next receiver inside
the same provider implementation was inspected.  The provider uses its
`+0x08` object for the selector
`useAlwaysOnBrightnessCurve:withRampDuration:`.

### Runtime evidence

The exact object supplied by the live
`BLSHBacklightOSInterfaceProvider` instance was:

```text
provider: BLSHBacklightOSInterfaceProvider
field: +0x08
class: SBBacklightPlatformProvider
image: /System/Library/PrivateFrameworks/SpringBoard.framework/SpringBoard
selector present: useAlwaysOnBrightnessCurve:withRampDuration:
```

The class-level passive hook for
`CBDisplayStateClient -transitionToDisplayMode:withDuration:error:` remained
at zero calls during the observed mode-4/mode-0 sequence.  The provider's
`_displayStateClient` remained nil.  The new `SBBacklightPlatformProvider`
curve hook did not produce a call record in the captured transition window.

The image/IMP fields for the downstream selector were affected by the
diagnostic method interposition itself and are not treated as original IMP
evidence.  The class and receiver provenance are unaffected.

### Classification

```text
SBBacklightOSInterfaceProvider: provider/display-state layer
SBBacklightPlatformProvider: SpringBoard policy/curve receiver
useAlwaysOnBrightnessCurve: presentation/brightness-policy side effect
CBDisplayStateClient: CoreBrightness physical-boundary candidate, not reached
```

This pivot does not establish a physical boundary.  It rules out the live
provider instance's direct CoreBrightness-client call for the observed
transition and identifies the next high-value owner as the existing
SpringBoard backlight request path rather than another generic
BacklightServicesHost helper.

```text
next semantic target: passive observation of the existing
SBBacklightController request handoff and BLSBacklight execution call
```

## Phase 4B-13  Request execution and sleep-action ownership

### Question

The previous provider/display-state observations needed to be separated into
three layers: the SpringBoard-originated request, the BacklightServicesHost
state-machine execution, and any lower display-service handoff.  This pass
used the exact `performChangeRequest:` implementation and the live object
ownership recorded during the natural mode-4 to mode-0 transition.

### Static request path

The bounded provider path is:

```text
SBBacklightController
  -_performBacklightChangeRequest:completion:
  -> BLSBacklightChangeRequest
  -> BLSBacklight -performChangeRequest:
  -> BLSHBacklightStateMachine -performChangeRequest:
  -> BLSBacklightChangeEvent construction
  -> BLSHBacklightTransitionStateMachine -performEvent:
```

At `0x200e120e8`, the request implementation creates the asynchronous
continuation and reads `requestedActivityState` from the request.  The
derived event state is produced by the previously recovered helper, stored
as the event's `state`, and passed to `performEvent:`.  This is a logical
state-machine transition, not evidence of a display-server call.

The implementation also performs lifecycle/transition bookkeeping and
dispatches the event continuation.  The bounded disassembly did not show a
direct call to a BKS setter, CoreBrightness client, IOKit display path, or an
XPC/MIG send at this entry point.

### Runtime request evidence

The installed passive observer recorded one naturally occurring request:

```text
SBBacklightController request count: 1
request class: BLSBacklightChangeRequest
BLSBacklight performChangeRequest count: 1
BLSHBacklightStateMachine performChangeRequest count: 1
```

The `BLSBacklight` +0x08 object was receiver-proven as:

```text
BLSHBacklightStateMachine
```

The live state-machine object contained:

```text
_osInterfaceProvider = BLSHBacklightOSInterfaceProvider
_sleepAction         = BLSHOnSystemSleepAction
_lock_observers      = NSConcreteHashTable
_eventPerformer      = BLSHBacklightTransitionStateMachine
```

This supersedes the earlier assumption that the observed path necessarily
uses `BLSXPCBacklightProxy` or `BSServiceConnection`; neither passive hook
recorded a call in this transition.

### Sleep-action ownership

The runtime class `BLSHOnSystemSleepAction` exposes these relevant callbacks:

```text
systemSleepMonitor:sleepRequestedWithResult:
systemSleepMonitor:prepareForSleepWithCompletion:
systemSleepMonitorSleepRequestAborted:
systemSleepMonitorWillWakeFromSleep:
actionCompleted
```

The passive hooks for the two sleep-request callbacks recorded no invocation
during the captured side-button transition.  Therefore the object is a
lifecycle/sleep-action owner, but it is not a runtime-confirmed continuation
of this particular mode-4 to mode-0 sample.

### Boundary classification

```text
request construction:             upstream input
BLSHBacklightStateMachine:        logical state-machine execution
TransitionStateMachine:           logical target/display-state resolution
BLSHBacklightOSInterfaceProvider: provider/display-state layer
BLSHOnSystemSleepAction:          lifecycle owner, not reached in sample
CoreBrightness CBDisplayStateClient: physical-boundary candidate, not reached
BackBoard/BKS setter:             not reached
physical panel boundary:          unresolved
```

The next bounded static target is the exact implementation of
`BLSHBacklightOSInterfaceProvider -transitionToDisplayMode:withDuration:`
and its non-trace branches.  The live `_displayStateClient` is nil and the
SpringBoard platform-provider curve/blanking hooks did not record calls, so
no physical boundary can be claimed from those objects yet.  No additional
runtime hook is justified until that provider branch is reduced to one exact
semantic handoff.
```
```
```

## Phase 4B-14  Provider transition branch reduction

### Question

The next bounded layer was the implementation of
`BLSHBacklightOSInterfaceProvider -transitionToDisplayMode:withDuration:` at
`0x200de3c8c`.  The purpose was to separate its internal provider-state work
from the one possible lower display-state call.

### Static receiver/data-flow evidence

The method preserves the incoming mode in `x20` and duration in `d8`.  Its
relevant non-trace operations are:

```text
mode/duration
  -> internal helper 0x200de319c
       receiver: provider self
       input: x1 = retained provider object/context, x2 = 0
       writes provider ivars at +0x78 and +0x80
       classification: provider transition bookkeeping/state

provider +0x38
  -> objc message stub 0x200e8f9a0
       arguments: mode in x2, duration in d0, error storage in x3
       selector reference: transitionToDisplayMode:withDuration:error:
       classification: CoreBrightness display-state candidate

provider +0x08
  -> additional provider/platform-policy helper path
       mode/duration-dependent
       classification: platform brightness/policy path; exact selector not
       recovered from the optimized direct-selector stub
```

The call through `0x200e8f9a0` is receiver-proven statically as the object
loaded from provider offset `+0x38`; prior runtime object inspection identifies
that ivar as `_displayStateClient` with type `CBDisplayStateClient`.

The call is therefore a genuine semantic display-state candidate, but it is
guarded by the live receiver value.  In the observed device instance the
receiver pointer was zero before and after the mode transition.

### Runtime evidence

The natural mode sequence remained:

```text
awake: provider state=2, target displayMode=4
lock:  provider state=0, target displayMode=0
```

The provider method was reached, as shown by the existing provider hook's
receiver provenance.  The same observation recorded:

```text
provider +0x38 (_displayStateClient): nil
CBDisplayStateClient transition call count: 0
SBBacklightPlatformProvider blanking/curve hook count: 0
```

Thus the CoreBrightness call is a statically reachable but runtime-unreached
candidate for this iPhone 12 mini instance.  Sending a synthetic receiver or
calling the method would violate the observation boundary and is not justified.

### Internal helper result

`0x200de319c` is not a generic trace helper.  It reads and replaces provider
internal state at offsets `+0x78` and `+0x80`, retains the old value, and
constructs an internal transition/context object.  It does not directly call
BackBoard, BKS, CoreBrightness, IOKit, XPC, MIG, or a display setter in the
bounded body.  It is classified as provider transition state, not the physical
boundary.

### Classification

```text
provider mode transition:              runtime confirmed
provider internal state update:         statically confirmed
CBDisplayStateClient handoff:           statically reachable, runtime absent
SpringBoard platform blanking call:     runtime absent
BackBoard/BKS handoff:                  not reached
physical OLED/power boundary:           unresolved
```

The next safe observation is limited to one-time enumeration of the live
provider object's object-valued ivars and mode/duration call record.  This is
needed to determine whether an additional receiver, distinct from `+0x08` and
`+0x38`, is the actual display-service owner.  It does not invoke a new
private API or alter any argument.

## Phase 4B-15  Sleep-monitor callback and applied-state callback check

### Question

The provider's live object graph identified both a nil CoreBrightness client
and a non-nil sleep/lifecycle path.  A new passive build recorded the provider
transition, enumerated all object-valued provider ivars once, and observed the
existing display-state delegate callback without changing any call.

### Runtime evidence

The natural transition record was:

```text
provider transition mode:       0
provider transition duration:   0.185
provider object:                 BLSHBacklightOSInterfaceProvider
```

The receiver-proven provider object contained:

```text
_platformProvider          = SBBacklightPlatformProvider
_watchdogProvider          = BLSHWatchdogProvider
_criticalAssertProvider    = BLSHCriticalAssertProvider
_displayStateClient        = nil
_suppressionManager        = nil
_setCBDisplayModeTimer     = BSContinuousMachTimer
_lock_watchdogTimer        = nil
_cbDisplayModeDelegate     = BLSHBacklightDisplayStateMachine
```

The passive hook on
`BLSHBacklightDisplayStateMachine -displayState:didUpdateToMode:` recorded no
callback.  This rules out a runtime-confirmed applied-mode acknowledgement
through that delegate for this sample; it does not make the method unsafe or
prove that it is never used on another path.

In the same transition, the existing `BLSHOnSystemSleepAction` hooks did
record:

```text
systemSleepMonitor:prepareForSleepWithCompletion:  count=1
systemSleepMonitor:sleepRequestedWithResult:       count=1
monitor class: SWSystemSleepMonitor
completion class: __NSStackBlock__
```

This is the first runtime-confirmed callback leaving the BLS state-machine
object graph toward the system sleep coordinator.  It is a state/lifecycle
propagation boundary, not yet proof of the final panel-power operation.

### Classification

```text
BLS provider state/target:             confirmed
provider transition:                   confirmed
CoreBrightness display client:         not reached (nil receiver)
display-state delegate acknowledgement: not observed
BLSHOnSystemSleepAction:               runtime confirmed
SWSystemSleepMonitor:                  runtime confirmed receiver
physical blanking/power boundary:      unresolved
```

The next bounded static target is the implementation of the two
`BLSHOnSystemSleepAction` callbacks, using their exact class/method ownership,
or the single callback/completion receiver that they invoke.  Generic sleep
monitor internals will not be expanded.  No display mutation is justified.
