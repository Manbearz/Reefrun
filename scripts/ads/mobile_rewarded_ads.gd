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
var _last_error_domain := ""
var _last_error_detail := ""
var _last_failure_kind := ""
var _load_generation := 0
var _sdk_initialized := false
var _offer_notice := ""
var _block_reason := ""
var _consent_busy := false
var _consent_resolved := false
var _ump_form_presented := false
var _tracking_status := TrackingPolicy.Status.UNAVAILABLE
var _offer_phase := ""
var _presented_ad: RewardedAd
var _runtime_platform := ""
var _retry_delay_scale := 1.0
const _RETRY_DELAYS: Array[float] = [8.0, 16.0, 30.0]
const IOS_LOAD_ERROR_DOMAIN := "com.google.admob"
const ANDROID_LOAD_ERROR_DOMAIN := "com.google.android.gms.ads"
# RewardedItem has no ad id. Each show stamps its own session, and a repeat
# of that same session is ignored. Entries are not cleared when a new show
# starts, so a late callback cannot be counted as the new show's reward.
var _rewarded_sessions := {}


func _ready() -> void:
	if not _native_mobile():
		return
	_log_rewarded_selection("provider ready")
	_request_consent()


func _exit_tree() -> void:
	# A freed provider must not keep a timer that would start another request.
	_cancel_rewarded_retry()
	_loading = false
	_load_generation += 1


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_RESUMED:
		return
	if not _native_mobile() or _consent_busy or _showing:
		return
	_request_consent()


func is_available() -> bool:
	return _ads_request_allowed and _native_mobile() and _ad != null and not _showing and not _loading and not _rewarded_unit().is_empty()


func is_show_active() -> bool:
	return _showing


func privacy_options_required() -> bool:
	return _privacy_options_required


func show_privacy_options() -> void:
	if not _privacy_options_required or not Engine.has_singleton("PoingGodotAdMobConsentInformation"):
		return
	UserMessagingPlatform.show_privacy_options_form(_on_privacy_options_dismissed)


func show_session(session_id: int) -> void:
	if not _arm_presentation(session_id):
		return
	# The loaded object is consumed above. A second show cannot present it.
	_presented_ad.show(_reward_listener)


func _arm_presentation(session_id: int) -> bool:
	if not is_available():
		_log("show skipped. stage=presentation %s" % _readiness_label())
		_emit_unavailable(session_id)
		return false
	_presented_ad = _ad
	_ad = null
	_showing = true
	_reward_listener = OnUserEarnedRewardListener.new()
	# The native listener receives only RewardedItem. RewardedAd.gd drops the
	# plugin uid before this runs, and the reward dictionary has no response id.
	# bind() keeps this show's session even if a later show replaces the ad.
	_reward_listener.on_user_earned_reward = _on_user_earned_reward.bind(session_id)
	if _fullscreen != null:
		_fullscreen.on_ad_dismissed_full_screen_content = _on_ad_dismissed.bind(session_id)
		_fullscreen.on_ad_failed_to_show_full_screen_content = _on_ad_failed_to_show.bind(session_id)
	_log("showing rewarded ad. stage=presentation session=%d %s" % [session_id, _readiness_label()])
	return true


func _platform_name() -> String:
	if _runtime_platform == "ios" or _runtime_platform == "android":
		return _runtime_platform
	if OS.has_feature("ios"):
		return "ios"
	if OS.has_feature("android"):
		return "android"
	return ""


func _native_mobile() -> bool:
	var name := _platform_name()
	return name == "ios" or name == "android"


func _rewarded_unit() -> String:
	var name := _platform_name()
	if name.is_empty():
		return ""
	return AdCfg.rewarded_unit_for(name, AdCfg.mode_for_platform(name))


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
	# The same integer is a different error on each platform. iOS GADErrorNoFill
	# is 1 and GADErrorServerError is 3. Android ERROR_CODE_NO_FILL is 3.
	# A code without one of those domains is an internal miss, not no-fill.
	var which := domain.strip_edges()
	if which == IOS_LOAD_ERROR_DOMAIN:
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
	if which == ANDROID_LOAD_ERROR_DOMAIN:
		match code:
			1:
				return "invalid_request"
			2:
				return "network"
			3:
				return "no_fill"
			_:
				return "other"
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


static func _redact(text: String) -> String:
	# Advertising identifiers are UUIDs. Response ids and placement ids are not.
	var pattern := RegEx.new()
	if pattern.compile("(?i)\\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\b") != OK:
		return text
	return pattern.sub(text, "[redacted]", true)


static func _text_field(source, key: String) -> String:
	var value = _field(source, key)
	if value == null:
		return ""
	return _redact(str(value))


static func describe_response_info(info) -> String:
	if info == null:
		return "response_id= adapter="
	var response_id := _text_field(info, "response_id")
	var adapter := _text_field(info, "mediation_adapter_class_name")
	var adapter_errors := ""
	var responses = _field(info, "adapter_responses")
	if responses != null:
		for item in responses:
			if item == null:
				continue
			var item_error = _field(item, "ad_error")
			var item_code := "" if item_error == null else str(_field(item_error, "code"))
			var item_domain := "" if item_error == null else _text_field(item_error, "domain")
			var item_message := "" if item_error == null else _text_field(item_error, "message")
			# Source name and adapter class only. Source ids and extras can identify a device.
			adapter_errors += " source=%s adapter=%s code=%s domain=%s message=%s" % [
				_text_field(item, "ad_source_name"),
				_text_field(item, "adapter_class_name"),
				item_code,
				item_domain,
				item_message,
			]
	return "response_id=%s adapter=%s%s" % [response_id, adapter, adapter_errors]


static func _cause_text(error, depth: int = 0) -> String:
	if error == null or depth >= 3:
		return ""
	var cause = _field(error, "cause")
	if cause == null:
		return ""
	return " cause_code=%s cause_domain=%s cause_message=%s%s" % [
		_field(cause, "code"),
		_text_field(cause, "domain"),
		_text_field(cause, "message"),
		_cause_text(cause, depth + 1),
	]


static func describe_load_error(error) -> String:
	if error == null:
		return "code=unknown domain= message=unknown kind=unknown response_id= adapter="
	var code_value = _field(error, "code")
	if code_value == null:
		code_value = "unknown"
	var code := int(code_value) if str(code_value).is_valid_int() else -1
	var domain := _text_field(error, "domain")
	var message := _text_field(error, "message")
	if message.is_empty():
		message = "unknown"
	var info = _field(error, "response_info")
	return "code=%s domain=%s message=%s kind=%s %s%s" % [
		code_value,
		domain,
		message,
		load_failure_kind(code, domain),
		describe_response_info(info),
		_cause_text(error),
	]


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
		not _rewarded_unit().is_empty() and _block_reason != "unit",
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
	# "NO FILL" is only the classified SDK result. A request that is still
	# inside the SDK says "AD LOADING". The backoff between those requests
	# keeps the SDK result so a no-fill is not relabeled as a local miss.
	return status_text(offer_phase(), _last_failure_kind, _loading)


func log_unready_press() -> void:
	_log("yes pressed with no ad to show. own_message=ad_not_ready sdk_no_fill=%s sdk_initialized=%s %s detail=%s" % [
		_last_failure_kind == "no_fill",
		_sdk_initialized,
		_readiness_label(),
		_last_error_detail,
	])


func _note_offer_phase() -> void:
	var phase := offer_phase()
	var notice := offer_status_text()
	if phase == _offer_phase and notice == _offer_notice:
		return
	_offer_phase = phase
	_offer_notice = notice
	_log("rewarded readiness=%s notice=%s sdk_initialized=%s %s detail=%s" % [
		phase,
		notice,
		_sdk_initialized,
		_readiness_label(),
		_last_error_detail,
	])
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
	# The card is on screen. Start the first request when consent allows it
	# and nothing is loaded. A no-fill or network backoff keeps its timer.
	if not _ads_request_allowed or not _native_mobile() or _showing or _loading or _ad != null or _retry_pending:
		return
	if not _sdk_started or not _sdk_initialized:
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
		if _sdk_initialized and _ad == null and not _loading and not _showing and not _retry_pending:
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
	_log_rewarded_selection("initializing Mobile Ads SDK")
	# An empty list adds no programmatic test devices and does not remove
	# devices registered in the AdMob console.
	_log("request configuration does not add test-device identifiers")
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
	_sdk_initialized = true
	_log("Mobile Ads SDK initialized. adapters=%s" % ",".join(adapters))
	_load_rewarded()


func _load_rewarded() -> void:
	if _load_hold:
		_load_after_hold = true
		_note_death("load_deferred")
		return
	if not _ads_request_allowed or not _native_mobile() or _loading or _showing or _ad != null:
		return
	if not _sdk_initialized:
		return
	var unit := _rewarded_unit()
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
	# Drop any backoff timer before this request. A late timer must not start
	# a second load, and a late callback from an older request is ignored.
	_cancel_rewarded_retry()
	_load_generation += 1
	var generation := _load_generation
	_loading = true
	_log_rewarded_selection("rewarded request started")
	_mark_timing("ad_request_started")
	_note_offer_phase()
	_load_callback = RewardedAdLoadCallback.new()
	_load_callback.on_ad_loaded = _on_ad_loaded.bind(generation)
	_load_callback.on_ad_failed_to_load = _on_ad_failed_to_load.bind(generation)
	_loader = RewardedAdLoader.new()
	_loader.load(unit, AdRequest.new(), _load_callback)


func _on_ad_loaded(ad: RewardedAd, generation: int = -1) -> void:
	if generation >= 0 and generation != _load_generation:
		_log("ignored late rewarded load. generation=%d current=%d" % [generation, _load_generation])
		if ad != null:
			ad.destroy()
		return
	_loading = false
	_load_failures = 0
	_last_error_code = -1
	_last_error_domain = ""
	_last_error_detail = ""
	_last_failure_kind = ""
	_cancel_rewarded_retry()
	if _ad != null and _ad != ad:
		_ad.destroy()
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
	var loaded_info := ""
	if ad != null and ad.has_method("get_response_info"):
		loaded_info = describe_response_info(ad.get_response_info())
	_log("rewarded ad loaded. %s" % loaded_info)
	_mark_timing("ad_load_callback")
	_note_death("ad_loaded")
	if _load_hold:
		_phase_after_hold = true
		return
	_note_offer_phase()


func _on_ad_failed_to_load(error, generation: int = -1) -> void:
	if generation >= 0 and generation != _load_generation:
		_log("ignored late rewarded load failure. %s" % describe_load_error(error))
		return
	_loading = false
	_load_failures += 1
	_remember_ad_error(error)
	_log("rewarded load failed. stage=load sdk_initialized=%s %s %s" % [_sdk_initialized, describe_load_error(error), _readiness_label()])
	_mark_timing("ad_load_callback")
	_note_death("ad_failed")
	_schedule_rewarded_retry()
	if _load_hold:
		_phase_after_hold = true
		return
	_note_offer_phase()


func _remember_ad_error(error) -> void:
	var domain := ""
	var code := -1
	if error != null:
		domain = _text_field(error, "domain")
		if str(_field(error, "code")).is_valid_int():
			code = int(_field(error, "code"))
	_last_error_code = code
	_last_error_domain = domain
	_last_failure_kind = load_failure_kind(code, domain)
	_last_error_detail = describe_load_error(error)


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
	var delay := retry_delay_for_failure(_load_failures) * maxf(_retry_delay_scale, 0.0)
	_log("retrying rewarded load in %.0fs. failures=%d kind=%s" % [delay, _load_failures, _last_failure_kind])
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if not is_instance_valid(self) or not is_inside_tree() or token != _retry_token:
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


func _on_ad_failed_to_show(error, session_id: int) -> void:
	_remember_ad_error(error)
	var message := "show_failed"
	if error != null:
		message = str(error.message)
	_log("rewarded show failed. stage=presentation %s %s" % [describe_load_error(error), _readiness_label()])
	_release_ad()
	_emit_failed(message, session_id)
	_load_rewarded()


func _release_ad() -> void:
	_showing = false
	if _presented_ad != null and _presented_ad != _ad:
		_presented_ad.destroy()
	_presented_ad = null
	if _ad != null:
		_ad.destroy()
		_ad = null
	_fullscreen = null
	_reward_listener = null


func _consent_label() -> String:
	if not Engine.has_singleton("PoingGodotAdMobConsentInformation"):
		return "plugin_missing allowed=%s" % _ads_request_allowed
	var status := int(UserMessagingPlatform.consent_information.get_consent_status())
	return "%s allowed=%s" % [ump_status_name(status), _ads_request_allowed]


func _readiness_label() -> String:
	# Placement id, consent, and load state only. No advertising id or device id.
	return "unit=%s consent=%s consent_satisfied=%s sdk_initialized=%s loaded=%s loading=%s retry=%s showing=%s failures=%d code=%s domain=%s kind=%s phase=%s" % [
		_rewarded_unit(),
		_consent_label(),
		_ads_request_allowed,
		_sdk_initialized,
		_ad != null,
		_loading,
		_retry_pending,
		_showing,
		_load_failures,
		_last_error_code,
		_last_error_domain,
		_last_failure_kind,
		offer_phase(),
	]


func _note_death(what: String) -> void:
	var host = get_parent()
	if host != null and host.has_method("note_death"):
		host.note_death(what)


func _mark_timing(event: String) -> void:
	var host = get_parent()
	if host != null and host.has_method("mark_timing"):
		host.mark_timing(event)


func _log_rewarded_selection(where: String) -> void:
	var name := _platform_name()
	var mode := AdCfg.mode_for_platform(name) if not name.is_empty() else AdCfg.monetization_mode()
	var unit := _rewarded_unit()
	_log("%s. %s" % [where, AdCfg.describe_rewarded_selection(mode, unit)])
	var note := AdCfg.rewarded_selection_note(mode, unit)
	if not note.is_empty():
		_log(note)
	if name == "ios" and AdCfg.normalize_mode(mode) == "production" and not TrackingPolicy.idfa_allowed(_tracking_status):
		_log("test_device_match=unconfirmed tracking=%s. A console test device matches only after the system allows tracking. This request does not include an advertising identifier." % TrackingPolicy.status_name(_tracking_status))


func _log(message: String) -> void:
	print("[ReefRun ads] " + message)
