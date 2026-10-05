# Spotify next-track preview (0.1.113)

The preview sits between the playback time/progress and lyrics. Empty or unrelated queue data removes the row and its spacing. The label truncates long titles, announces its full text to accessibility, and plays a single 0.28-second fade with a 3-point upward transition when its text changes. Reduce Motion disables the translation. The existing content container and whole-view AOD pixel shift cover the new label; animations are removed when playback becomes invisible.

## Data source

On the test device, MediaRemote returned only the current content item, including after configuring an explicit three-item request on a fresh controller. The read-only `research/tools/media_queue_probe.m` verifies this without sending playback commands.

The Spotify-injected module observes `SPTEsperantoPlayer` through `addPlayerObserver:` and receives `player:stateDidChange:`. It reads `SPTPlayerState.future` and the first future track's URI/title/artist; repeat-one selects the current track. Each getter is checked for an object return type, and unsupported states produce no guessed next track. The interface reference is [spoti.pw's runtime-derived player declarations](https://github.com/skopevoj/spoti.pw/blob/main/tweak/Sources/Headers/SPTPlayer.h). This interface is private and can change across Spotify versions.

Only changes to the current/next track metadata write a small `SpotifyQueueSnapshot` preference and send the existing preferences notification. No extra recurring timer or network request is added. SpringBoard reads the snapshot through the existing Spotify lyrics snapshot path and refreshes it through the existing progress update. Track URI association rejects stale snapshots from another song, including songs with identical titles. A title/artist match is used only when an identifier is unavailable. Snapshots older than six hours are rejected.

## Validation

- GitHub Actions run `37253837841`: Apple arm64e AOD and normal builds successful; charging policy, diagnostics batching, and queue association tests passed.
- AOD package SHA-256: `ba78ae11cb90ff5d94dacf47f486369f23f06ac4178112c484c6fc2fc9eaff97`.
- Installed 0.1.113 on the existing test phone. Spotify's native observer populated distinct current and next track metadata, and SpringBoard reported `SpotifyNextTrackAvailable = YES`.
- Device track names and raw probe logs remain in ignored local build artifacts.
- The user confirmed the next-track preview appears after playing the playlist and entering AOD. Transition quality has not been separately rated; runtime and visibility checks do not prove absence of OLED aging.
