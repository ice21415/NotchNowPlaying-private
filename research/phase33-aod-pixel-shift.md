# Phase 33 — AOD Player Pixel Shift

Date: 2026-09-26
Target: iPhone 12 mini (`iPhone13,1`), iOS 17.1.2 (21B101), RootHide
Status: implementation prepared; device verification pending

## Behavior

When pseudo-AOD is Active, the player artwork, labels, and progress elements
move together to a random offset of 1–3 physical display pixels in each axis.
The position is selected when AOD presentation begins and changes every 30
seconds. The full-screen plugin view, Cover Sheet blackout, status-bar mask, and
touch target do not move. The offset returns to zero as soon as the UI hides or
the preference is disabled.

The new `AODPixelShiftEnabled` preference defaults to enabled and can be turned
off in the Lock Screen settings group. The shift only redistributes pixel use;
it cannot guarantee that burn-in will not occur. Static illuminated artwork
and text can still age OLED pixels over time.

## Implementation

`NNPView` applies a sublayer translation to its player children, converted from
physical pixels to UIKit points using the display scale. `NNPController` owns a
30-second common-run-loop timer that is started only while the player is
visible in active pseudo-AOD and invalidated/reset on hide.

## Verification

Build using the current Apple toolchain in the Phase 7 GitHub Actions workflow.
On device, confirm the movement is barely perceptible and that artwork, text,
and progress shift together without moving the blackout or revealing Lock
Screen content. Confirm the setting disables movement and that unlock stops
the timer and returns the content to its original position.
