# AOD brightness control

The existing pseudo-AOD path replaces the native zero backlight factor with the system's dimmed factor, read from `BLSHBacklightOSInterfaceProvider`'s `_backlightDimmedFactor` ivar. Device diagnostics recorded this factor as approximately `0.05`.

The Preferences slider stores `AODBrightnessMultiplier` from 100% to 400%. Its default, 100%, preserves the current behavior. The replacement factor is the system dimmed factor multiplied by this value and capped at `0.20`; this is a global backlight factor, so uncovered system surfaces may also appear brighter and power use may increase. The native hook reads an atomic value, while the controller updates it during preference reconciliation. A changed value takes effect the next time AOD starts.

Runtime diagnostics report the base system dim factor, selected multiplier, and effective replacement factor as `Phase7SystemDimmedBacklightFactor`, `Phase7AODBrightnessMultiplier`, and `Phase7DimmedBacklightFactor` respectively.

## Device follow-up

On device after a 400% setting was saved and AOD was restarted, Preferences reported `AODBrightnessMultiplier=400`, while runtime diagnostics still showed `Phase7AODBrightnessMultiplier=1` and an effective factor of `0.05`. The controller was using its cached preference value when reconciling AOD eligibility. The controller now synchronizes and rereads the multiplier immediately before arming an eligible AOD session; `PreferenceAODBrightnessMultiplier` records the value read for that session.

The first device run after that change confirmed the preferences reread returned 4, but the HID factor hook still logged `multiplier=1.00x` and substituted `0.05`. This localizes the mismatch to the value publication path between the controller and hook; the exact cause is not yet confirmed. The display setter now republishes the atomic value even when its cached property is unchanged, and the controller explicitly republishes the freshly read value on every eligible reconcile. `Phase7RequestedAODBrightnessMultiplier` records what the controller sends to the hook.

## Physical brightness follow-up

On-device diagnostics for build 0.1.30 confirm the hook forwards `0.20` at a 400% setting, but the user saw no brightness change. Build 0.1.31 tried `UIScreen.brightness`; device diagnostics then showed the value was already `1.0` before AOD and stayed capped at `1.0` for every slider value. The user again confirmed no visible change, so this UIKit path is removed.

The factor hook previously substituted zero only while a synchronous `transitionToDisplayMode:` call temporarily published its provider object. Any later zero-factor callback during the same armed pseudo-AOD session passed through unchanged. The next diagnostic build applies the cached system dim factor times the selected multiplier to every main-display zero-factor callback while armed, and records callback count, input/output factor, and provider availability in the existing heartbeat. This tests a concrete follow-up-reset hypothesis but does not establish that CoreBrightness routes the substituted factor to panel nits. If telemetry shows `0.20` reaches the native setter and the screen remains unchanged, the remaining unresolved edge is downstream of this tweak's BKS factor call.
