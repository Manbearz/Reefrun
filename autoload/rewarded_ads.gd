extends Node

signal reward_earned(session_id: int)
signal ad_closed(session_id: int)
signal ad_failed(reason: String, session_id: int)
signal ad_unavailable(session_id: int)

const AdCfg := preload("res://scripts/ads/ad_config.gd")
const MockScript := preload("res://scripts/ads/mock_rewarded_ads.gd")
const WebScript := preload("res://scripts/ads/web_rewarded_ads.gd")
const IosScript := preload("res://scripts/ads/ios_rewarded_ads.gd")
const AndroidScript := preload("res://scripts/ads/android_rewarded_ads.gd")

var _provider: RewardedAdProvider


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_provider = _make_provider()
	add_child(_provider)
	_provider.reward_earned.connect(func(session_id: int): reward_earned.emit(session_id))
	_provider.ad_closed.connect(func(session_id: int): ad_closed.emit(session_id))
	_provider.ad_failed.connect(func(reason: String, session_id: int): ad_failed.emit(reason, session_id))
	_provider.ad_unavailable.connect(func(session_id: int): ad_unavailable.emit(session_id))


func is_rewarded_ad_available() -> bool:
	return _provider != null and _provider.is_available()


func begin_show_session() -> int:
	if _provider == null:
		return 0
	return _provider.begin_show_session()


func show_session(session_id: int) -> void:
	if _provider == null or session_id <= 0:
		ad_unavailable.emit(session_id)
		return
	if not _provider.is_available():
		ad_unavailable.emit(session_id)
		return
	_provider.show_session(session_id)


func show_rewarded_ad() -> int:
	var session_id := begin_show_session()
	show_session(session_id)
	return session_id


func mock_show_count() -> int:
	if _provider == null or _provider.get_script() != MockScript:
		return 0
	return int(_provider.show_calls)


func set_mock_outcome(outcome: int, duplicate_reward := false, delay := 0.0) -> bool:
	if _provider == null or _provider.get_script() != MockScript:
		return false
	_provider.mark_scripted(outcome, duplicate_reward, delay)
	return true


func prepare_interactive_simulator() -> bool:
	if not AdCfg.development_reward_simulator():
		return false
	if _provider == null or _provider.get_script() != MockScript:
		return false
	_provider.prepare_interactive()
	return true


func simulator_button(action: String) -> BaseButton:
	if _provider == null or _provider.get_script() != MockScript:
		return null
	return _provider.simulator_button(action)


func _make_provider() -> RewardedAdProvider:
	if AdCfg.use_mock_provider():
		return MockScript.new()
	if OS.has_feature("web"):
		return WebScript.new()
	if OS.has_feature("ios"):
		return IosScript.new()
	if OS.has_feature("android"):
		return AndroidScript.new()
	return WebScript.new()
