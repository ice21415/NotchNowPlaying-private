# Phase 27 — Event State Provenance Probe

## Question

The passive iPhone trace recorded a lock-button request with
`requestedActivityState=0`, then an event carrying that request with
`state=0`. The iOS 17.1.2 static analysis of the host state-machine helper
predicts event state `2` for that request. This probe records the event at
construction and consumption so the difference can be localized.

## Probe changes

Probe version `0.1.4` adds these read-only observations:

- Request object addresses at SpringBoard, BLS client, BLS host, event
  initializer, and transition-machine boundaries.
- `state` and `previousState` initializer arguments.
- The initialized event's `state` getter result and the raw `_state` ivar
  value, using the runtime ivar offset and checking its `q` encoding.
- At event consumption, the event address, getter result, raw ivar, associated
  request address, and the `state` getter's current IMP image and offset.
- The `state` getter's runtime IMP image and offset. This probe does not hook
  that getter, so the attribution can reveal whether another injected image
  replaced it.

The initializer hook passes every original argument to `%orig` and returns its
result unchanged. The existing `performEvent:` hook continues to call `%orig`
without changing the event. No display mode, request state, brightness, or
sleep behavior is modified.

## How to read the next trace

For a single request, match the `request=0x...` value across stages. Match the
event using `receiver=0x...`, `result=0x...`, and `event=0x...`:

1. If `stateArgument`, `getterState`, and `rawState` differ immediately after
   initialization, the initializer/getter/ivar assumption is wrong or a hook
   changes the value during construction.
2. If all three agree after initialization but differ at `performEvent:`, the
   event is changed between construction and consumption, or the consumer sees
   a different event instance.
3. If all three agree at both points but `stateArgument` is `0` for the
   lock-button request, the runtime producer differs from the statically
   recovered call path. The logged getter IMP image and request identity then
   help identify which runtime method or request was observed.
4. If the constructor hook does not log while the event does, the producer may
   use another initializer, another concrete event class, or a direct allocation
   path.

Keep the experimental AOD preference disabled for this capture. Trigger one
ordinary music-playing side-button lock, then retrieve
`/var/mobile/Library/NotchNowPlaying/backlight-flow-probe.log`. The test should
not be used to infer AOD success; it only resolves the event provenance gap.

Build this arm64e package with the dedicated macOS 26 GitHub Actions workflow.
It records Xcode, Clang, iPhoneOS SDK, and RootHide Theos revisions alongside
the package, so the installed compiler/toolchain can be checked before the
device capture.

The first two builds used macOS 26.6.2, Xcode 26.6, Apple Clang 21.0.0, and iOS
SDK 26.5. Clang rejected both a direct Objective-C-to-byte-pointer cast and a
direct bridge to a typed byte pointer under ARC. The probe now bridges the
event to `const void *` first, then reads the ivar bytes; neither failed build
produced an installable package.
