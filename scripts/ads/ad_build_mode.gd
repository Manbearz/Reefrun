class_name AdBuildMode
extends Object

## Platform-specific rewarded-ad mode packed into every export.
## A live unit is requested only when that platform's mode is exactly "production".
## Debug versus release does not select the mode. An empty or unknown value stays on test.
##
## IOS_MODE is the approved TestFlight configuration. It requests the live iOS
## rewarded unit. Register the iPhone as an AdMob test device before opening an ad.
## This constant does not mean the build is earning revenue.
## ANDROID_MODE stays on Google's test rewarded unit.
const IOS_MODE := "production"
const ANDROID_MODE := "test"
## Plain markers an exported package can be scanned for. Each must name the same mode as its constant.
const IOS_OUTPUT_MARKER := "REEFRUN_IOS_AD_MODE=production"
const ANDROID_OUTPUT_MARKER := "REEFRUN_ANDROID_AD_MODE=test"
