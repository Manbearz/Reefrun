class_name AdConfig
extends Object

# TestFlight and local development stay on Google's test rewarded units.
# Set this to false only for a store release that should request the live units.
const USE_TEST_ADS := true

# App IDs identify the AdMob app. They contain "~" and are not ad unit IDs.
const IOS_APP_ID := "ca-app-pub-5190108736982657~5175195159"
const ANDROID_APP_ID := "ca-app-pub-5190108736982657~2452653885"

# Live rewarded units. Used only when USE_TEST_ADS is false.
const IOS_REWARDED_UNIT_ID := "ca-app-pub-5190108736982657/2549031818"
const ANDROID_REWARDED_UNIT_ID := "ca-app-pub-5190108736982657/3355591884"

# Official Google test rewarded units. These never serve a live ad.
const IOS_TEST_REWARDED_UNIT_ID := "ca-app-pub-3940256099942544/1712485313"
const ANDROID_TEST_REWARDED_UNIT_ID := "ca-app-pub-3940256099942544/5224354917"

# Filled when a real web ad account/placement exists. Leave empty until then.
const WEB_PLACEMENT_ID := ""
const WEB_TEST_PLACEMENT_ID := ""


static func web_placement_id() -> String:
	return WEB_TEST_PLACEMENT_ID if USE_TEST_ADS else WEB_PLACEMENT_ID


static func ios_placement_id() -> String:
	return rewarded_unit_id() if OS.has_feature("ios") else ""


static func app_id() -> String:
	if OS.has_feature("ios"):
		return IOS_APP_ID
	if OS.has_feature("android"):
		return ANDROID_APP_ID
	return ""


static func is_google_test_rewarded_unit(unit_id: String) -> bool:
	return unit_id == IOS_TEST_REWARDED_UNIT_ID or unit_id == ANDROID_TEST_REWARDED_UNIT_ID


static func rewarded_unit_id() -> String:
	var production := ""
	var test_unit := ""
	if OS.has_feature("ios"):
		production = IOS_REWARDED_UNIT_ID
		test_unit = IOS_TEST_REWARDED_UNIT_ID
	elif OS.has_feature("android"):
		production = ANDROID_REWARDED_UNIT_ID
		test_unit = ANDROID_TEST_REWARDED_UNIT_ID
	else:
		return ""
	if USE_TEST_ADS:
		if not is_google_test_rewarded_unit(test_unit):
			push_error("[ReefRun ads] Refusing to load because the test unit is not a Google test rewarded unit.")
			return ""
		return test_unit
	if is_google_test_rewarded_unit(production) or production.contains("~") or not production.contains("/"):
		push_error("[ReefRun ads] Production mode does not have a rewarded ad unit id.")
		return ""
	return production


static func use_mock_provider() -> bool:
	# The mock provider can grant a reward. Keep it in the editor binary only.
	# A debug iOS export is still an exported build, and TestFlight must not
	# treat a missing ad SDK as a completed rewarded ad.
	return OS.has_feature("editor") and not OS.has_feature("template")


static func simulator_allowed(features: PackedStringArray) -> bool:
	# Export templates, TestFlight, store builds, and phones never qualify.
	# Custom feature tags cannot remove "template", "release", "ios", or "android"
	# once the export binary defines them.
	var has := {}
	for feature in features:
		has[str(feature)] = true
	if not bool(has.get("editor", false)) or not bool(has.get("windows", false)):
		return false
	if bool(has.get("template", false)):
		return false
	if bool(has.get("template_debug", false)) or bool(has.get("template_release", false)):
		return false
	if bool(has.get("release", false)):
		return false
	if bool(has.get("ios", false)) or bool(has.get("android", false)) or bool(has.get("web", false)):
		return false
	return true


static func development_reward_simulator() -> bool:
	return simulator_allowed(_runtime_features())


static func _runtime_features() -> PackedStringArray:
	var tags: PackedStringArray = PackedStringArray([
		"editor", "windows", "ios", "android", "web",
		"template", "template_debug", "template_release", "release",
	])
	var found := PackedStringArray()
	for tag in tags:
		if OS.has_feature(tag):
			found.append(tag)
	return found
