class_name WebRewardedAds
extends RewardedAdProvider

const AdCfg := preload("res://scripts/ads/ad_config.gd")

# JavaScriptBridge + real web ad provider go here later.
# Do not hardcode publisher IDs, placement URLs, or ad networks.


func is_available() -> bool:
	if AdCfg.web_placement_id().is_empty():
		return false
	if not OS.has_feature("web"):
		return false
	return false


func show() -> void:
	if not OS.has_feature("web"):
		ad_unavailable.emit()
		return
	if AdCfg.web_placement_id().is_empty():
		ad_unavailable.emit()
		return
	ad_unavailable.emit()
