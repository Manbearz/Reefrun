class_name AdBuildMode
extends Object

## Platform-specific rewarded-ad mode packed into every export.
## A live unit is requested only when that platform's mode is exactly "production".
## Debug versus release does not select the mode. An empty or unknown value stays on test.
##
## IOS_MODE is the current export selection. "production" requests the live iOS
## rewarded unit. The iPhone must stay registered as an AdMob test device, and
## the served ad must show Google's test-ad label. "test" requests Google's
## official iOS rewarded test unit and leaves IOS_REWARDED_UNIT_ID unchanged.
## ANDROID_MODE stays on Google's test rewarded unit.
const IOS_MODE := "production"
const ANDROID_MODE := "test"
## Plain markers an exported package can be scanned for. Each must name the same mode as its constant.
const IOS_OUTPUT_MARKER := "REEFRUN_IOS_AD_MODE=production"
const ANDROID_OUTPUT_MARKER := "REEFRUN_ANDROID_AD_MODE=test"
