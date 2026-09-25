# NotchNowPlaying

NotchNowPlaying is a standalone SpringBoard tweak for iPhone 12 mini / iOS
17.1.2. It reads system Now Playing state through MediaRemote and displays a
compact artwork, title, artist, and progress bar around the notch.

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
