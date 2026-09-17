class_name IosRewardedAds
extends RewardedAdProvider

const AdCfg := preload("res://scripts/ads/ad_config.gd")

# Native iOS rewarded-ad SDK goes here later.
# Do not install an unverified plugin or invent placement IDs.


func is_available() -> bool:
	if AdCfg.ios_placement_id().is_empty():
		return false
	if not OS.has_feature("ios"):
		return false
	return false


func show() -> void:
	if not OS.has_feature("ios"):
		ad_unavailable.emit()
		return
	if AdCfg.ios_placement_id().is_empty():
		ad_unavailable.emit()
		return
	ad_unavailable.emit()
