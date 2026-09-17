extends Node

signal reward_earned
signal ad_closed
signal ad_failed(reason: String)
signal ad_unavailable

const AdCfg := preload("res://scripts/ads/ad_config.gd")
const MockScript := preload("res://scripts/ads/mock_rewarded_ads.gd")
const WebScript := preload("res://scripts/ads/web_rewarded_ads.gd")
const IosScript := preload("res://scripts/ads/ios_rewarded_ads.gd")

var _provider: RewardedAdProvider


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_provider = _make_provider()
	add_child(_provider)
	_provider.reward_earned.connect(func(): reward_earned.emit())
	_provider.ad_closed.connect(func(): ad_closed.emit())
	_provider.ad_failed.connect(func(reason: String): ad_failed.emit(reason))
	_provider.ad_unavailable.connect(func(): ad_unavailable.emit())


func is_rewarded_ad_available() -> bool:
	return _provider != null and _provider.is_available()


func show_rewarded_ad() -> void:
	if _provider == null:
		ad_unavailable.emit()
		return
	if not _provider.is_available():
		ad_unavailable.emit()
		return
	_provider.show()


func mock_show_count() -> int:
	if _provider == null or _provider.get_script() != MockScript:
		return 0
	return int(_provider.show_calls)


func set_mock_outcome(outcome: int, duplicate_reward := false, delay := 0.0) -> bool:
	if _provider == null or _provider.get_script() != MockScript:
		return false
	_provider.outcome = outcome
	_provider.duplicate_reward_signal = duplicate_reward
	_provider.resolve_delay = delay
	_provider.show_calls = 0
	return true


func _make_provider() -> RewardedAdProvider:
	if AdCfg.use_mock_provider():
		return MockScript.new()
	if OS.has_feature("web"):
		return WebScript.new()
	if OS.has_feature("ios"):
		return IosScript.new()
	return WebScript.new()
