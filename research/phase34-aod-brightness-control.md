# AOD brightness control

The existing pseudo-AOD path replaces the native zero backlight factor with the system's dimmed factor, read from `BLSHBacklightOSInterfaceProvider`'s `_backlightDimmedFactor` ivar. Device diagnostics recorded this factor as approximately `0.05`.

The Preferences slider stores `AODBrightnessMultiplier` from 100% to 400%. Its default, 100%, preserves the current behavior. The replacement factor is the system dimmed factor multiplied by this value and capped at `0.20`; this is a global backlight factor, so uncovered system surfaces may also appear brighter and power use may increase. The native hook reads an atomic value, while the controller updates it during preference reconciliation. A changed value takes effect the next time AOD starts.

Runtime diagnostics report the base system dim factor, selected multiplier, and effective replacement factor as `Phase7SystemDimmedBacklightFactor`, `Phase7AODBrightnessMultiplier`, and `Phase7DimmedBacklightFactor` respectively.
