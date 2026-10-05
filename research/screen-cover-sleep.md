# Covered / face-down AOD blanking — 0.1.123

The previous native pocket observer did receive events, but the inspected state was out-of-pocket. Covering the display is a different requirement and cannot rely on the native pocket classification alone.

The AOD now enables UIDevice proximity monitoring and device orientation notifications only while the feature and AOD are active. A proximity-near or face-down state is confirmed for 0.8 seconds; uncovering is confirmed for 0.25 seconds. Timers are one-shot and cancelled on new input or deactivation. Previously enabled proximity monitoring is preserved. No camera or gaze monitoring is used. An object must cover the sensor near the notch; darkness alone is insufficient.

The existing AOD implementation normally substitutes zero backlight and suppresses native display blanking. While covered, these substitutions are bypassed. The feature directly calls the saved native BKS screen-blank implementation and zero-backlight function, keeping the logical AOD session for restoration. Uncovering requests native unblanking and restores the dimmed factor. Exiting the logical session clears the covered flag without independently waking an inactive session. UI work uses the existing suspension path.

These are native blanking requests rather than just black overlay content. Actual sensor changes, blanking, restoration and manual wake still require device validation. No wattage savings have been measured. Proximity sensing itself has a cost.

GitHub Actions run 37274797899 passed normal and AOD builds and existing checks. AOD package SHA256: `16e55b015016bc59d3ac5809c70d9daf6af66c3132ba709532291ff2b98c08da`.

Primary UIKit references: [UIDevice](https://developer.apple.com/documentation/uikit/uidevice), [proximity monitoring](https://developer.apple.com/documentation/uikit/uidevice/isproximitymonitoringenabled), [proximity state](https://developer.apple.com/documentation/uikit/uidevice/proximitystate).

## Investigation and 0.1.124

0.1.123 did not receive UIKit cover or face-down transitions in AOD. Native capability inspection showed that the UIKit monitoring flag was set while BackBoard proximity detection was inactive. A standalone CoreMotion diagnostic aborted when run as root, but succeeded as mobile and returned measured acceleration including z ≈ +1 for face-down. Standalone sensor assertions were obtainable, although they did not show active proximity in that process; they do not prove delivery inside SpringBoard.

0.1.124 uses accelerometer updates at 2 Hz in the SpringBoard/mobile context and an owned native low-power proximity request. Face-down uses z > 0.85 to enter and z < 0.65 to leave. Repeated equal sensor samples no longer restart the confirmation timer. The Foundation confirmation test covers repeated samples, transient occlusion, interrupted recovery, cancellation after leaving AOD, and owner release. Sensor resources are released when the feature or AOD is disabled.

GitHub Actions 37277004606 passed normal and AOD builds. The first AOD attempt hit the existing lock observer test's startup timing assertion; rerunning the failed job passed. Package SHA256: `fc6e532bb46c127f970965b289e5b37b6bb1d33edea336e769e761124d2d6cec`.

Device 0.1.124: motion available and samples received, face-down detected, covered state confirmed, native display blank requested. The proximity assertion exists, but native proximity active initially read false. The user subsequently confirmed that both face-down and hand-cover blanking and restoration work. The native active getter by itself therefore should not be treated as the availability test for this low-power request. Manual side-button behavior remains a separate regression check. No measured power savings have been established.
