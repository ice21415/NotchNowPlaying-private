# Covered / face-down AOD blanking — 0.1.123

The previous native pocket observer did receive events, but the inspected state was out-of-pocket. Covering the display is a different requirement and cannot rely on the native pocket classification alone.

The AOD now enables UIDevice proximity monitoring and device orientation notifications only while the feature and AOD are active. A proximity-near or face-down state is confirmed for 0.8 seconds; uncovering is confirmed for 0.25 seconds. Timers are one-shot and cancelled on new input or deactivation. Previously enabled proximity monitoring is preserved. No camera or gaze monitoring is used. An object must cover the sensor near the notch; darkness alone is insufficient.

The existing AOD implementation normally substitutes zero backlight and suppresses native display blanking. While covered, these substitutions are bypassed. The feature directly calls the saved native BKS screen-blank implementation and zero-backlight function, keeping the logical AOD session for restoration. Uncovering requests native unblanking and restores the dimmed factor. Exiting the logical session clears the covered flag without independently waking an inactive session. UI work uses the existing suspension path.

These are native blanking requests rather than just black overlay content. Actual sensor changes, blanking, restoration and manual wake still require device validation. No wattage savings have been measured. Proximity sensing itself has a cost.

GitHub Actions run 37274797899 passed normal and AOD builds and existing checks. AOD package SHA256: `16e55b015016bc59d3ac5809c70d9daf6af66c3132ba709532291ff2b98c08da`.

Primary UIKit references: [UIDevice](https://developer.apple.com/documentation/uikit/uidevice), [proximity monitoring](https://developer.apple.com/documentation/uikit/uidevice/isproximitymonitoringenabled), [proximity state](https://developer.apple.com/documentation/uikit/uidevice/proximitystate).
