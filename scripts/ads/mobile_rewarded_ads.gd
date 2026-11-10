class_name MobileRewardedAds
extends RewardedAdProvider

signal privacy_options_changed(required: bool)
signal availability_changed

const AdCfg := preload("res://scripts/ads/ad_config.gd")
const TrackingPolicy := preload("res://scripts/ads/att_authorization.gd")

var _ad: RewardedAd
var _loader: RewardedAdLoader
var _load_callback: RewardedAdLoadCallback
var _fullscreen: FullScreenContentCallback
var _reward_listener: OnUserEarnedRewardListener
var _loading := false
var _showing := false
var _load_hold := false
var _load_after_hold := false
var _phase_after_hold := false
var _sdk_started := false
var _ads_request_allowed := false
var _privacy_options_required := false
var _load_failures := 0
var _retry_pending := false
var _retry_token := 0
var _last_error_code := -1
var _last_failure_kind := ""
var _offer_notice := ""
var _block_reason := ""
var _consent_busy := false
var _consent_resolved := false
var _ump_form_presented := false
var _tracking_status := TrackingPolicy.Status.UNAVAILABLE
var _offer_phase := ""
const _RETRY_DELAYS: Array[float] = [8.0, 16.0, 30.0]
const IOS_LOAD_ERROR_DOMAIN := "com.google.admob"
# RewardedItem has no ad id. Each show stamps its own session, and a repeat
# of that same session is ignored. Entries are not cleared when a new show
# starts, so a late callback cannot be counted as the new show's reward.
var _rewarded_sessions := {}


func _ready() -> void:
	if not _native_mobile():
		return
	_log("provider ready. mode=%s app_id=%s" % [AdCfg.monetization_mode(), AdCfg.app_id()])
	_request_consent()


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_RESUMED:
		return
	if not _native_mobile() or _consent_busy or _showing:
		return
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


static func ump_status_name(status: int) -> String:
	match status:
		ConsentInformation.ConsentStatus.NOT_REQUIRED:
			return "not_required"
		ConsentInformation.ConsentStatus.REQUIRED:
			return "required"
		ConsentInformation.ConsentStatus.OBTAINED:
			return "obtained"
		_:
			return "unknown"


static func classify_offer(native_mobile: bool, unit_ready: bool, ad_ready: bool, consent_resolved: bool, consent_busy: bool, ads_allowed: bool, loading: bool, load_failures: int, sdk_present: bool, retry_pending: bool = false, blocked: bool = false) -> String:
	if ad_ready:
		return "ready"
	if not native_mobile or not unit_ready:
		return "hidden"
	if not consent_resolved or consent_busy:
		return "loading"
	if not ads_allowed or not sdk_present or blocked:
		return "unavailable"
	# A failed response stays in the loading state while another request is
	# queued. Two failures do not retire the placement for the rest of the session.
	if loading or retry_pending or load_failures == 0:
		return "loading"
	return "unavailable"


static func load_failure_kind(code: int, domain: String = "") -> String:
	# iOS GADErrorCode values belong only to com.google.admob. Android uses
	# different numbers in a different domain, so an unknown domain stays unlabeled.
	if domain.strip_edges() != IOS_LOAD_ERROR_DOMAIN:
		return "other"
	match code:
		0:
			return "invalid_request"
		1:
			return "no_fill"
		2:
			return "network"
		3:
			return "server"
		_:
			return "other"


static func status_text(phase: String, failure_kind: String, request_in_flight: bool) -> String:
	if phase == "ready" or phase == "hidden":
		return ""
	if request_in_flight:
		return "AD LOADING"
	match failure_kind:
		"no_fill":
			return "NO FILL"
		"network":
			return "NO NETWORK"
		"invalid_request":
			return "INVALID REQUEST"
		"server":
			return "SERVER ERROR"
		_:
			if phase == "loading":
				return "AD LOADING"
			return "NO AD AVAILABLE"


static func retry_delay_for_failure(load_failures: int) -> float:
	var index := maxi(load_failures - 1, 0)
	if index >= _RETRY_DELAYS.size():
		index = _RETRY_DELAYS.size() - 1
	return _RETRY_DELAYS[index]


static func _field(source, key: String):
	if source == null:
		return null
	if source is Dictionary:
		return source.get(key, null)
	return source.get(key)


static func describe_load_error(error) -> String:
	if error == null:
		return "code=unknown domain= message=unknown kind=unknown response_id= adapter="
	var code_value = _field(error, "code")
	if code_value == null:
		code_value = "unknown"
	var code := int(code_value) if str(code_value).is_valid_int() else -1
	var domain_value = _field(error, "domain")
	var message_value = _field(error, "message")
	var domain := "" if domain_value == null else str(domain_value)
	var message := "" if message_value == null else str(message_value)
	var cause := ""
	var cause_value = _field(error, "cause")
	if cause_value != null:
		cause = " cause_code=%s cause_message=%s" % [_field(cause_value, "code"), _field(cause_value, "message")]
	var response_id := ""
	var adapter := ""
	var adapter_errors := ""
	var info = _field(error, "response_info")
	if info != null:
		var response_value = _field(info, "response_id")
		var adapter_value = _field(info, "mediation_adapter_class_name")
		response_id = "" if response_value == null else str(response_value)
		adapter = "" if adapter_value == null else str(adapter_value)
		var responses = _field(info, "adapter_responses")
		if responses != null:
			for item in responses:
				if item == null:
					continue
				var item_error = _field(item, "ad_error")
				var item_code := "" if item_error == null else str(_field(item_error, "code"))
				var item_message := "" if item_error == null else str(_field(item_error, "message"))
				adapter_errors += " source=%s adapter=%s code=%s message=%s" % [str(_field(item, "ad_source_name")), str(_field(item, "adapter_class_name")), item_code, item_message]
	return "code=%s domain=%s message=%s kind=%s response_id=%s adapter=%s%s%s" % [code_value, domain, message, load_failure_kind(code, domain), response_id, adapter, cause, adapter_errors]


static func describe_form_error(error) -> String:
	if error == null:
		return "code=unknown message=unknown"
	var code = _field(error, "error_code")
	var message = _field(error, "message")
	if code == null:
		code = "unknown"
	if message == null:
		message = ""
	return "code=%s message=%s" % [code, message]


static func consent_status_allows(status: int) -> bool:
	# Matches UMP canRequestAds: only a finished "not required" or "obtained"
	# state may request ads. Unknown, required, and an error are not permission.
	return (
		status == ConsentInformation.ConsentStatus.NOT_REQUIRED
		or status == ConsentInformation.ConsentStatus.OBTAINED
	)


func _request_consent() -> void:
	if _consent_busy:
		return
	if not Engine.has_singleton("PoingGodotAdMobConsentInformation"):
		_log("consent plugin is missing. Ads will not be requested.")
		_tracking_status = TrackingPolicy.Status.UNAVAILABLE
		_apply_consent_gate()
		return
	_consent_busy = true
	_log("requesting consent info")
	var request := ConsentRequestParameters.new()
	request.tag_for_under_age_of_consent = false
	UserMessagingPlatform.consent_information.update(request, _on_consent_success, _on_consent_failure)


func _on_consent_success() -> void:
	var info := UserMessagingPlatform.consent_information
	var form_available := info.get_is_consent_form_available()
	var status := int(info.get_consent_status())
	var present_form := TrackingPolicy.should_present_ump_form(form_available, _ump_form_presented)
	_log("consent updated. ump_status=%s idfa_form_available=%s form_presented=%s tracking=%s" % [ump_status_name(status), form_available, _ump_form_presented, TrackingPolicy.status_name(_tracking_status)])
	# UMP 3.1.0 calls Apple's tracking request only while presenting a published
	# IDFA explainer, and only while the system status is not determined. A
	# GDPR form, the privacy-options form, or a missing explainer is not that
	# request. Players outside GDPR can still have a form available while
	# consent status is not required.
	if present_form:
		_log("loading consent form before the rewarded request")
		UserMessagingPlatform.load_consent_form(_on_consent_form_loaded, _on_consent_form_failed)
	# A published IDFA form must not hold the rewarded load forever. When UMP
	# already allows a request, start a non-tracking load while that form is open.
	if consent_status_allows(status):
		if present_form:
			_log("UMP allows a non-tracking rewarded load while the form is open")
		else:
			_consent_busy = false
		_apply_consent_gate()
		return
	if present_form:
		_note_offer_phase()
		return
	_consent_busy = false
	_apply_consent_gate()


func _on_consent_failure(error: FormError) -> void:
	_consent_busy = false
	_log("consent update failed: %s" % describe_form_error(error))
	# A previous session can still leave status as obtained or not required.
	# The error itself does not grant consent or tracking permission.
	_tracking_status = TrackingPolicy.Status.UNAVAILABLE
	_apply_consent_gate()


func _on_consent_form_loaded(form: ConsentForm) -> void:
	if not TrackingPolicy.should_present_ump_form(true, _ump_form_presented):
		_consent_busy = false
		_apply_consent_gate()
		return
	_ump_form_presented = true
	_log("consent form presented. idfa_form_available=true")
	_note_offer_phase()
	form.show(_on_consent_form_dismissed)


func _on_consent_form_failed(error: FormError) -> void:
	_consent_busy = false
	_log("consent form failed to load: %s" % describe_form_error(error))
	_tracking_status = TrackingPolicy.Status.UNAVAILABLE
	_apply_consent_gate()


func _on_consent_form_dismissed(error: FormError) -> void:
	_consent_busy = false
	if error != null:
		_log("consent form dismissed with error: %s" % describe_form_error(error))
		_tracking_status = TrackingPolicy.Status.UNAVAILABLE
	else:
		_log("consent form dismissed. status=%s" % UserMessagingPlatform.consent_information.get_consent_status())
		# The form result is UMP consent, not Apple's tracking decision.
		_tracking_status = TrackingPolicy.Status.UNAVAILABLE
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


func offer_phase() -> String:
	return classify_offer(
		_native_mobile(),
		not AdCfg.rewarded_unit_id().is_empty() and _block_reason != "unit",
		is_available(),
		_consent_resolved,
		_consent_busy,
		_ads_request_allowed,
		_loading,
		_load_failures,
		Engine.has_singleton("PoingGodotAdMob") and _block_reason != "plugin",
		_retry_pending,
		_block_reason != ""
	)


func offer_status_text() -> String:
	return status_text(offer_phase(), _last_failure_kind, _loading)


func _note_offer_phase() -> void:
	var phase := offer_phase()
	var notice := offer_status_text()
	if phase == _offer_phase and notice == _offer_notice:
		return
	_offer_phase = phase
	_offer_notice = notice
	_log("rewarded readiness=%s notice=%s" % [phase, notice])
	availability_changed.emit()


func offer_failure_code() -> String:
	var phase := offer_phase()
	if phase == "ready" or phase == "hidden":
		return ""
	if _block_reason == "plugin":
		return "plugin"
	if _consent_resolved and not _consent_busy and not _ads_request_allowed:
		return "consent"
	if _last_error_code >= 0:
		return str(_last_error_code)
	return ""


func set_load_hold(hold: bool) -> void:
	# The death tumble is a few tenths of a second. A retry or the reload
	# started when the previous ad closed can call into AdMob on that exact
	# frame. Keep the loaded ad, and start the next request once the card is up.
	if _load_hold == hold:
		return
	_load_hold = hold
	_note_death("load_hold_%s" % ("on" if hold else "off"))
	if hold:
		return
	if _phase_after_hold:
		_phase_after_hold = false
		_note_offer_phase()
	if _load_after_hold:
		_load_after_hold = false
		_load_rewarded()


func nudge_offer_load() -> void:
	# The wiped-out card is on screen. If consent already allows a request and
	# nothing is in flight, ask again instead of waiting out the backoff.
	if not _ads_request_allowed or not _native_mobile() or _showing or _loading or _ad != null:
		return
	_cancel_rewarded_retry()
	if not _sdk_started:
		_start_sdk()
		return
	_load_rewarded()


func _apply_consent_gate() -> void:
	_consent_resolved = true
	_refresh_privacy_options()
	var consent_allows := _consent_allows_request()
	if TrackingPolicy.ads_allowed(consent_allows, _tracking_status):
		_block_reason = ""
		if _last_failure_kind == "consent":
			_last_failure_kind = ""
		_ads_request_allowed = true
		if OS.has_feature("ios") and not TrackingPolicy.idfa_allowed(_tracking_status):
			_log("this process did not confirm IDFA access. Mobile Ads includes it only after Apple authorizes tracking.")
		_start_sdk()
		_note_offer_phase()
		return
	_ads_request_allowed = false
	_block_reason = "consent"
	_last_failure_kind = "consent"
	_loading = false
	_cancel_rewarded_retry()
	if _showing:
		_log("consent no longer allows a new ad. The ad already on screen can finish.")
		return
	_release_ad()
	_log("ads will not be requested until consent allows them")
	_note_offer_phase()


func _start_sdk() -> void:
	if not _ads_request_allowed:
		return
	if _sdk_started:
		if _ad == null and not _loading and not _showing:
			_load_rewarded()
		return
	if not Engine.has_singleton("PoingGodotAdMob"):
		_block_reason = "plugin"
		_last_failure_kind = "plugin"
		_log("Mobile Ads native plugin is missing. Rewarded ads stay unavailable.")
		_note_offer_phase()
		return
	_block_reason = ""
	_sdk_started = true
	var unit := AdCfg.rewarded_unit_id()
	_log("initializing Mobile Ads SDK. mode=%s unit=%s" % [AdCfg.monetization_mode(), unit])
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = _on_sdk_initialized
	MobileAds.set_request_configuration(RequestConfiguration.new())
	MobileAds.initialize(listener)


func _on_sdk_initialized(status: InitializationStatus) -> void:
	var adapters := PackedStringArray()
	if status != null:
		for key in status.adapter_status_map.keys():
			var adapter = status.adapter_status_map[key]
			var state := -1
			if adapter != null:
				state = int(adapter.initialization_state)
			adapters.append("%s:%s" % [str(key), state])
	_log("Mobile Ads SDK initialized. adapters=%s" % ",".join(adapters))
	_load_rewarded()


func _load_rewarded() -> void:
	if _load_hold:
		_load_after_hold = true
		_note_death("load_deferred")
		return
	if not _ads_request_allowed or not _native_mobile() or _loading or _showing or _ad != null:
		return
	var unit := AdCfg.rewarded_unit_id()
	if unit.is_empty():
		_block_reason = "unit"
		_log("rewarded load skipped because no unit id is allowed")
		_note_offer_phase()
		return
	if not Engine.has_singleton("PoingGodotAdMobRewardedAd"):
		_block_reason = "plugin"
		_last_failure_kind = "plugin"
		_log("rewarded ad plugin is missing. Rewarded ads stay unavailable.")
		_note_offer_phase()
		return
	if not AdCfg.is_production_ads() and not AdCfg.is_google_test_rewarded_unit(unit):
		_block_reason = "unit"
		_log("blocked a non-test unit while test ads are required")
		_note_offer_phase()
		return
	if AdCfg.is_production_ads() and AdCfg.is_google_test_rewarded_unit(unit):
		_block_reason = "unit"
		_log("blocked a Google test unit while production ads are required")
		_note_offer_phase()
		return
	_block_reason = ""
	_loading = true
	_retry_pending = false
	_log("rewarded request started. unit=%s" % unit)
	_mark_timing("ad_request_started")
	_note_offer_phase()
	_load_callback = RewardedAdLoadCallback.new()
	_load_callback.on_ad_loaded = _on_ad_loaded
	_load_callback.on_ad_failed_to_load = _on_ad_failed_to_load
	_loader = RewardedAdLoader.new()
	_loader.load(unit, AdRequest.new(), _load_callback)


func _on_ad_loaded(ad: RewardedAd) -> void:
	_loading = false
	_load_failures = 0
	_last_error_code = -1
	_last_failure_kind = ""
	_cancel_rewarded_retry()
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
	_mark_timing("ad_load_callback")
	_note_death("ad_loaded")
	if _load_hold:
		_phase_after_hold = true
		return
	_note_offer_phase()


func _on_ad_failed_to_load(error: LoadAdError) -> void:
	_loading = false
	_load_failures += 1
	var domain := ""
	if error != null:
		domain = str(_field(error, "domain"))
		if str(_field(error, "code")).is_valid_int():
			_last_error_code = int(_field(error, "code"))
	_last_failure_kind = load_failure_kind(_last_error_code, domain)
	_log("rewarded load failed: %s" % describe_load_error(error))
	_mark_timing("ad_load_callback")
	_note_death("ad_failed")
	_schedule_rewarded_retry()
	if _load_hold:
		_phase_after_hold = true
		return
	_note_offer_phase()


func _cancel_rewarded_retry() -> void:
	_retry_token += 1
	_retry_pending = false


func _schedule_rewarded_retry() -> void:
	if not is_inside_tree() or not _ads_request_allowed:
		_retry_pending = false
		return
	_retry_pending = true
	_retry_token += 1
	var token := _retry_token
	var delay := retry_delay_for_failure(_load_failures)
	_log("retrying rewarded load in %.0fs. failures=%d" % [delay, _load_failures])
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if not is_instance_valid(self) or token != _retry_token:
			return
		_retry_pending = false
		_load_rewarded()
	)


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


func _note_death(what: String) -> void:
	var host = get_parent()
	if host != null and host.has_method("note_death"):
		host.note_death(what)


func _mark_timing(event: String) -> void:
	var host = get_parent()
	if host != null and host.has_method("mark_timing"):
		host.mark_timing(event)


func _log(message: String) -> void:
	print("[ReefRun ads] " + message)
