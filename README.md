# Notch Now Playing

Standalone Phase 2A prototype for SpringBoard on iPhone13,1 / iOS 17.1.2.

This project is intentionally separate from Lilywhite. It reads Now Playing
through MediaRemote, renders a small UIKit overlay, observes lock/unlock, and
does not prevent display sleep or modify powerd/backboardd.

Build with the existing local toolchain:

```sh
THEOS=../Lilywhite/build-env/roothide-theos make package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1
```

The Spotify-only filter currently requires the runtime bundle identifier
`com.spotify.client`; this must be verified on-device before treating the
runtime test as complete.
