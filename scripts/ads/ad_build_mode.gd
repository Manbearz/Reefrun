class_name AdBuildMode
extends Object

## Explicit monetization mode packed into this build.
## Live rewarded units are requested only when MODE is exactly "production".
## Any other value, including an empty one, keeps Google's test rewarded units.
## Debug versus release does not select the mode.
const MODE := "test"
## Plain marker an exported package can be scanned for. It must name the same mode as MODE.
const OUTPUT_MARKER := "REEFRUN_AD_MODE=test"
