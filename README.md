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
