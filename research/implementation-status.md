# NotchNowPlaying Implementation Status

## Working

- SpringBoard injection through the roothide/ElleKit package path
- MediaRemote Now Playing metadata and artwork
- Spotify detection (`com.spotify.client` observed on the target)
- Artwork, title, artist, and progress UI
- Lock/unlock observation through `SBLockScreenManager`
- PreferenceLoader settings page
- Separate user-preference and diagnostic domains
- Lightweight CFPreferences diagnostics
- Release builds that exclude the Phase 2J BackBoard probe

## Disabled pending research

- Locked-visible mode
- `BKSDisplayServicesIsScreenDisabled`
- `BKSDisplayServicesGetBlankingRemovesPower`
- All BackBoardServices setters and unblank helpers
- `blankingRemovesPower` manipulation
- Display assertions intended to defeat explicit lock blanking

## Reason

Phase 2E showed that `kIOPMAssertionTypePreventUserIdleDisplaySleep` does not
keep the panel visible after an explicit lock. A later Phase 2J probe using an
unverified display identifier/object argument caused SpringBoard instability and
Safe Mode. The stable release therefore keeps all BackBoard display control
outside the production execution path until an Apple caller ABI is recovered.

## Build variants

- Release: normal MediaRemote/UI build; experimental locked-visible backend off.
- Diagnostic: may enable additional CFPreferences/logging flags, but no
  BackBoard display control.
- Experimental: reserved for future research and not enabled by default.
