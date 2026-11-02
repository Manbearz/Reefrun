class_name MobileRewardedAds
extends RewardedAdProvider

signal privacy_options_changed(required: bool)

const AdCfg := preload("res://scripts/ads/ad_config.gd")

var _ad: RewardedAd
var _loader: RewardedAdLoader
var _load_callback: RewardedAdLoadCallback
var _fullscreen: FullScreenContentCallback
var _reward_listener: OnUserEarnedRewardListener
var _loading := false
var _showing := false
var _sdk_started := false
var _ads_request_allowed := false
var _privacy_options_required := false
var _load_failures := 0
# RewardedItem has no ad id. Each show stamps its own session, and a repeat
# of that same session is ignored. Entries are not cleared when a new show
# starts, so a late callback cannot be counted as the new show's reward.
var _rewarded_sessions := {}


func _ready() -> void:
	if not _native_mobile():
		return
	_log("provider ready. mode=%s app_id=%s" % [AdCfg.monetization_mode(), AdCfg.app_id()])
	_request_consent()


func is_available() -> bool:
	return _ads_request_allowed and _native_mobile() and _ad != null and not _showing and not AdCfg.rewarded_unit_id().is_empty()


func is_show_active() -> bool:
	return _showing


func privacy_options_required() -> bool:
	return _privacy_options_required


func show_privacy_options() -> void:
	if not _privacy_options_required or not Engine.has_singleton("PoingGodotAdMobConsentInformation"):
		return
	UserMessagingPlatform.show_privacy_options_form(_on_privacy_options_dismissed)


func show_session(session_id: int) -> void:
	if not _ads_request_allowed or not _native_mobile() or _ad == null or _showing or AdCfg.rewarded_unit_id().is_empty():
		_log("show skipped. loaded=%s showing=%s" % [_ad != null, _showing])
		_emit_unavailable(session_id)
		return
	_showing = true
	_reward_listener = OnUserEarnedRewardListener.new()
	# The native listener receives only RewardedItem. RewardedAd.gd drops the
	# plugin uid before this runs, and the reward dictionary has no response id.
	# bind() keeps this show's session even if a later show replaces _ad.
	_reward_listener.on_user_earned_reward = _on_user_earned_reward.bind(session_id)
	if _fullscreen != null:
		_fullscreen.on_ad_dismissed_full_screen_content = _on_ad_dismissed.bind(session_id)
		_fullscreen.on_ad_failed_to_show_full_screen_content = _on_ad_failed_to_show.bind(session_id)
	_log("showing rewarded ad session=%d" % session_id)
	_ad.show(_reward_listener)


func _native_mobile() -> bool:
	return OS.has_feature("ios") or OS.has_feature("android")


static func consent_status_allows(status: int) -> bool:
	# Matches UMP canRequestAds: only a finished "not required" or "obtained"
	# state may request ads. Unknown, required, and an error are not permission.
	return (
		status == ConsentInformation.ConsentStatus.NOT_REQUIRED
		or status == ConsentInformation.ConsentStatus.OBTAINED
	)


func _request_consent() -> void:
	if not Engine.has_singleton("PoingGodotAdMobConsentInformation"):
		_log("consent plugin is missing. Ads will not be requested.")
		_apply_consent_gate()
		return
	_log("requesting consent info")
	var request := ConsentRequestParameters.new()
	request.tag_for_under_age_of_consent = false
	UserMessagingPlatform.consent_information.update(request, _on_consent_success, _on_consent_failure)


func _on_consent_success() -> void:
	var info := UserMessagingPlatform.consent_information
	_log("consent updated. status=%s form_available=%s" % [info.get_consent_status(), info.get_is_consent_form_available()])
	var required := info.get_consent_status() == info.ConsentStatus.REQUIRED
	if required and info.get_is_consent_form_available():
		UserMessagingPlatform.load_consent_form(_on_consent_form_loaded, _on_consent_form_failed)
		return
	_apply_consent_gate()


func _on_consent_failure(error: FormError) -> void:
	var message := error.message if error != null else "unknown"
	_log("consent update failed: %s" % message)
	# A previous session can still leave status as obtained or not required.
	# The error itself does not grant permission.
	_apply_consent_gate()


func _on_consent_form_loaded(form: ConsentForm) -> void:
	var info := UserMessagingPlatform.consent_information
	if info.get_consent_status() == info.ConsentStatus.REQUIRED:
		_log("showing consent form")
		form.show(_on_consent_form_dismissed)
		return
	_log("consent form loaded but not required")
	_apply_consent_gate()


func _on_consent_form_failed(error: FormError) -> void:
	var message := error.message if error != null else "unknown"
	_log("consent form failed to load: %s" % message)
	_apply_consent_gate()


func _on_consent_form_dismissed(error: FormError) -> void:
	if error != null:
		_log("consent form dismissed with error: %s" % error.message)
	else:
		_log("consent form dismissed. status=%s" % UserMessagingPlatform.consent_information.get_consent_status())
	_apply_consent_gate()


func _on_privacy_options_dismissed(error: FormError) -> void:
	if error != null:
		_log("privacy options dismissed with error: %s" % error.message)
	_apply_consent_gate()


func _consent_allows_request() -> bool:
	if not Engine.has_singleton("PoingGodotAdMobConsentInformation"):
		return false
	var info := UserMessagingPlatform.consent_information
	return consent_status_allows(int(info.get_consent_status()))


func _refresh_privacy_options() -> void:
	var required := false
	if Engine.has_singleton("PoingGodotAdMobConsentInformation"):
		var info := UserMessagingPlatform.consent_information
		required = (
			int(info.get_privacy_options_requirement_status())
			== int(info.PrivacyOptionsRequirementStatus.REQUIRED)
		)
	if required == _privacy_options_required:
		return
	_privacy_options_required = required
	privacy_options_changed.emit(required)


func _apply_consent_gate() -> void:
	_refresh_privacy_options()
	if _consent_allows_request():
		_ads_request_allowed = true
		_start_sdk()
		return
	_ads_request_allowed = false
	_loading = false
	if _showing:
		_log("consent no longer allows a new ad. The ad already on screen can finish.")
		return
	_release_ad()
	_log("ads will not be requested until consent allows them")


func _start_sdk() -> void:
	if not _ads_request_allowed:
		return
	if _sdk_started:
		if _ad == null and not _loading and not _showing:
			_load_rewarded()
		return
	if not Engine.has_singleton("PoingGodotAdMob"):
		_log("Mobile Ads native plugin is missing. Rewarded ads stay unavailable.")
		return
	_sdk_started = true
	var unit := AdCfg.rewarded_unit_id()
	_log("initializing Mobile Ads SDK. mode=%s unit=%s" % [AdCfg.monetization_mode(), unit])
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = _on_sdk_initialized
	MobileAds.set_request_configuration(RequestConfiguration.new())
	MobileAds.initialize(listener)


func _on_sdk_initialized(_status: InitializationStatus) -> void:
	_log("Mobile Ads SDK initialized")
	_load_rewarded()


func _load_rewarded() -> void:
	if not _ads_request_allowed or not _native_mobile() or _loading or _showing or _ad != null:
		return
	var unit := AdCfg.rewarded_unit_id()
	if unit.is_empty():
		_log("rewarded load skipped because no unit id is allowed")
		return
	if not Engine.has_singleton("PoingGodotAdMobRewardedAd"):
		_log("rewarded ad plugin is missing. Rewarded ads stay unavailable.")
		return
	if not AdCfg.is_production_ads() and not AdCfg.is_google_test_rewarded_unit(unit):
		_log("blocked a non-test unit while test ads are required")
		return
	if AdCfg.is_production_ads() and AdCfg.is_google_test_rewarded_unit(unit):
		_log("blocked a Google test unit while production ads are required")
		return
	_loading = true
	_log("loading rewarded ad %s" % unit)
	_load_callback = RewardedAdLoadCallback.new()
	_load_callback.on_ad_loaded = _on_ad_loaded
	_load_callback.on_ad_failed_to_load = _on_ad_failed_to_load
	_loader = RewardedAdLoader.new()
	_loader.load(unit, AdRequest.new(), _load_callback)


func _on_ad_loaded(ad: RewardedAd) -> void:
	_loading = false
	_load_failures = 0
	_ad = ad
	_fullscreen = FullScreenContentCallback.new()
	_fullscreen.on_ad_showed_full_screen_content = func() -> void: _log("rewarded ad showed")
	_fullscreen.on_ad_impression = func() -> void: _log("rewarded impression")
	_fullscreen.on_ad_clicked = func() -> void: _log("rewarded ad clicked")
	# Show replaces these with session-bound callables. A dismiss before show
	# has no reward session and must not grant anything.
	_fullscreen.on_ad_dismissed_full_screen_content = func() -> void:
		_log("rewarded ad dismissed before show")
	_fullscreen.on_ad_failed_to_show_full_screen_content = func(error: AdError) -> void:
		var message := error.message if error != null else "show_failed"
		_log("rewarded ad failed before show: %s" % message)
	_ad.full_screen_content_callback = _fullscreen
	_log("rewarded ad loaded")


func _on_ad_failed_to_load(error: LoadAdError) -> void:
	_loading = false
	_load_failures += 1
	var message := error.message if error != null else "unknown"
	_log("rewarded load failed: %s" % message)
	if _load_failures > 1 or not is_inside_tree():
		return
	_log("retrying rewarded load once")
	get_tree().create_timer(8.0).timeout.connect(_load_rewarded)


func _on_user_earned_reward(item: RewardedItem, session_id: int) -> void:
	if session_id <= 0 or _rewarded_sessions.has(session_id):
		_log("duplicate reward callback ignored")
		return
	_rewarded_sessions[session_id] = true
	var amount := item.amount if item != null else 0
	var kind := item.type if item != null else ""
	_log("reward earned. session=%d amount=%s type=%s" % [session_id, amount, kind])
	_emit_reward(session_id)


func _on_ad_dismissed(session_id: int) -> void:
	_log("rewarded ad dismissed. session=%d earned=%s" % [session_id, _rewarded_sessions.has(session_id)])
	_release_ad()
	_emit_closed(session_id)
	_load_rewarded()


func _on_ad_failed_to_show(error: AdError, session_id: int) -> void:
	var message := error.message if error != null else "show_failed"
	_log("rewarded ad failed to show: %s" % message)
	_release_ad()
	_emit_failed(message, session_id)
	_load_rewarded()


func _release_ad() -> void:
	_showing = false
	if _ad != null:
		_ad.destroy()
		_ad = null
	_fullscreen = null
	_reward_listener = null


func _log(message: String) -> void:
	print("[ReefRun ads] " + message)
