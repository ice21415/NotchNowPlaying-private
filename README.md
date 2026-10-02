# NotchNowPlaying

NotchNowPlaying is a standalone SpringBoard tweak for iPhone 12 mini / iOS
17.1.2. It reads system Now Playing state through MediaRemote and displays a
compact artwork, title, artist, and progress bar around the notch.

## Charging flow (0.1.109)

While active locked AOD is displayed and charging below 100%, two synchronized teal streams run from the bottom
center along the rounded screen edges, repeating every 3.2 seconds. Battery
level limits how far each stream travels along its path: 50% reaches halfway,
and the range extends toward the notch as the battery charges. Short tails
scale down at low charge levels. No separate charging window is created. Leaving AOD removes the view and
releases its shape layers and animations. It stops
when charging stops or the battery is full, pauses while the panel is off,
and respects Reduce Motion with a static edge indicator. Enable or disable
it with the "啟用充電流光" setting.

The current battery percentage appears near the bottom for eight seconds on
charge presentation or battery-level changes, then its label is released.
All plugin AOD surfaces move every 30 seconds across a 169-position grid using
native panel pixel coordinates, including notifications and charging streams.
A brief black interval also rests overlapping pixels inside solid artwork.
The protection stops outside AOD and cannot guarantee prevention of OLED burn-in.
See [the pixel coverage audit](research/aod-pixel-audit.md) for checks and limits.

AOD brightness can adapt to fresh ambient-light sensor readings independently
of the system auto-brightness switch. A continuous target curve with short ramps limits abrupt
changes; unavailable or stale samples return to baseline brightness. Sampling
runs only during active locked AOD and releases its client on exit. See
[ambient brightness validation](research/aod-ambient-continuous.md).

While locked AOD is actively displayed, charging keeps the custom overlay
visible even when iOS reports the display as off. Phone AC-power wake requests
and the native battery presentation are suppressed only during this active
AOD state with charging flow enabled. Manual wake and ordinary charging
outside AOD keep the system behavior.

Use the `Build charging flow with Apple Clang` GitHub Actions workflow for
installable packages: `normal` builds the standard overlay, while `aod`
preserves the experimental Phase 7 AOD build. Both use Apple's compiler on
macOS 26 and verify package architecture, version and bundled preferences.
See `research/charging-flow.md` for implementation and device checks.

## Current release

- Spotify-only mode is enabled by default (`com.spotify.client`).
- Artwork, title, artist, and progress update from MediaRemote.
- Lock/unlock state is observed through SpringBoard's lock-screen manager.
- Preferences are available through PreferenceLoader.
- The UI is black/OLED-friendly and updates progress at approximately 1 Hz.
- The overlay disappears normally when iOS blanks the physical display.

Continuous locked-screen display retention is not enabled in the current
release. This is not native AOD.

`NNP_ENABLE_EXPERIMENTAL_LOCKED_VISIBLE` remains disabled by default. In the
experimental build, a bounded trial substitutes a dim backlight factor and
suppresses only BLS Host's black overlay request while the trial is armed.
The BLS display mode remains `Off`, so a visible result is not yet established
and this is not native AOD. If the trial ends while locked, it restores the
black overlay. See
`research/phase5-locked-visible-experiments.md` and
`research/phase7-pseudo-aod.md` and
`research/phase28-active-lock-ca-blanking.md`.

Experimental builds also record a two-minute incident window after a display
mode transition. Diagnostics include requested/forwarded modes, call stacks,
lock/lifecycle/timer state, and a five-second background heartbeat with main
queue responsiveness. Events are stored in the
`com.user.notchnowplaying.diagnostics` preferences domain under
`DiagnosticLogEvents`; no process signal handlers are installed.

## Installation

Build with Theos and the roothide scheme:

```sh
make clean package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1
```

Install the generated arm64e package through Sileo or the known-good device
deployment workflow. A SpringBoard reload may be required after installation;
do not reboot the device.

## Architecture

```text
MediaRemote → NNPMediaController → NNPState → NNPController → NNPView
                                      ↑             ↓
                              NNPLockStateController  NNPDisplayController
```

The display controller is an intentionally disabled abstraction. It does not
call BackBoardServices, IOKit display setters, powerd, or backboardd.

## Known limitation

iPhone13,1 has no native AOD path. Previous research found that ordinary
`PreventUserIdleDisplaySleep` does not override explicit lock blanking. The
BackBoardServices argument contract remains unsafe to call after an earlier
getter probe destabilized SpringBoard. No BackBoard getter or setter is used by
the production build.
