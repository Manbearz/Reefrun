class_name AdConfig
extends Object

# Flip to false for shipping once a real provider is wired and approved.
const USE_TEST_ADS := true

# Filled when a real web ad account/placement exists. Leave empty until then.
const WEB_PLACEMENT_ID := ""
const WEB_TEST_PLACEMENT_ID := ""

# Filled when a native iOS rewarded-ad unit exists. Leave empty until then.
const IOS_PLACEMENT_ID := ""
const IOS_TEST_PLACEMENT_ID := ""


static func web_placement_id() -> String:
	return WEB_TEST_PLACEMENT_ID if USE_TEST_ADS else WEB_PLACEMENT_ID


static func ios_placement_id() -> String:
	return IOS_TEST_PLACEMENT_ID if USE_TEST_ADS else IOS_PLACEMENT_ID


static func use_mock_provider() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build()
