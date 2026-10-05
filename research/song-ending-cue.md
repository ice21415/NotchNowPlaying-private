# Song ending cue — 0.1.121

The progress fill changes to a muted amber once a playing song has more than zero and at most ten seconds remaining. The color transition lasts 0.65 seconds and uses linear timing. The existing remaining-time display provides the numeric cue; the next-song preview still appears during the final minute.

The existing progress update drives eligibility. No new timers, network requests, pulse loops, layout changes, or extra layers are introduced. Pause, seek outside the final ten seconds, track changes, invalid duration, and completion restore the artwork accent. Track changes restore immediately. Reduced Motion bypasses the transition; hiding or removing the view cancels the named animation. The existing pixel-shift container continues to move the progress layer.

GitHub Actions run 37272059024 passed both normal and AOD builds and existing checks. The AOD package SHA256 is `9daee20763612d5b05ffe00d9af20996c267253f363195d7c2c2134ccc2d855a`.

Visual validation on the phone is pending: seek to about fifteen seconds remaining, enter AOD, observe the amber transition and next-song card, then verify seek-back and natural track transitions restore the original accent. No power savings claim is made for this visual feature.
