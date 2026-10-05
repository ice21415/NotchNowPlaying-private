# Spotify next-track preview (0.1.116)

The preview sits between the playback time/progress and lyrics, and appears only when the current track has a known duration and more than zero but at most 60 seconds remaining. Position is extrapolated from the media timestamp and playback rate, so pausing freezes the threshold and seeking backwards removes the preview. Short tracks can show it throughout playback. Empty or unrelated queue data removes the row and its spacing.

The compact card displays a 32-point cover, next-track hint, title and artist. Long titles truncate, and the full text remains available to accessibility. Entry plays a single 0.4-second fade and 0.5-second upward transition, with slightly staggered title/artist movement. Reduce Motion disables translations. All elements remain within the existing content container and whole-view AOD pixel shift; animations are removed when playback becomes invisible.

## Data source

On the test device, MediaRemote returned only the current content item, including after configuring an explicit three-item request on a fresh controller. The read-only `research/tools/media_queue_probe.m` verifies this without sending playback commands.

The Spotify-injected module observes `SPTEsperantoPlayer` through `addPlayerObserver:` and receives `player:stateDidChange:`. It reads `SPTPlayerState.future` and the first future track's URI/title/artist; repeat-one selects the current track. Each getter is checked for an object return type, and unsupported states produce no guessed next track. The interface reference is [spoti.pw's runtime-derived player declarations](https://github.com/skopevoj/spoti.pw/blob/main/tweak/Sources/Headers/SPTPlayer.h). This interface is private and can change across Spotify versions.

Only changes to the current/next track metadata write a small `SpotifyQueueSnapshot` preference and send the existing preferences notification. No extra recurring timer or queue network request is added. SpringBoard reads the snapshot through the existing Spotify lyrics snapshot path and refreshes it through the existing progress update. Track URI association rejects stale snapshots from another song, including songs with identical titles. A title/artist match is used only when an identifier is unavailable. Snapshots older than six hours are rejected.

The Spotify track's `coverArtURLSmall`, `coverArtURL` or `imageURL` getter provides the next cover reference. `spotify:image:` identifiers are mapped to the image CDN, and HTTPS image URLs on `i.scdn.co` are accepted. SpringBoard loads covers only while the preview is eligible and visible, creates a maximum 96-pixel thumbnail, and caches up to eight thumbnails with a 512 KiB cost limit. Hiding or changing the preview cancels an in-flight request and rejects obsolete completions. Failed requests do not retry on every progress update.

## Validation

- GitHub Actions run `37253837841`: Apple arm64e AOD and normal builds successful; charging policy, diagnostics batching, and queue association tests passed.
- AOD package SHA-256: `ba78ae11cb90ff5d94dacf47f486369f23f06ac4178112c484c6fc2fc9eaff97`.
- Installed 0.1.113 on the existing test phone. Spotify's native observer populated distinct current and next track metadata, and SpringBoard reported `SpotifyNextTrackAvailable = YES`.
- Device track names and raw probe logs remain in ignored local build artifacts.
- The user confirmed the next-track preview appears after playing the playlist and entering AOD. Transition quality has not been separately rated; runtime and visibility checks do not prove absence of OLED aging.
- 0.1.115: run `37254635954` passed both builds. Device diagnostics confirmed a cover URL and decoded next-cover image; the user confirmed all content loaded successfully.
- 0.1.116: run `37255270562` passed both builds and association/cover URL/final-minute checks, including the 60-second boundary, paused position, elapsed timestamp, completed track, invalid duration and short tracks. AOD package SHA-256: `39ec4b4c92571309cff3c7ab1b90c93b2401f057103690481df06ca77456be62`.
