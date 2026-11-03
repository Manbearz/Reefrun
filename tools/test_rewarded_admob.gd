extends SceneTree

# Real post-run offer driven by the editor mock ad bridge.
# Mobile SDK callbacks are exercised only where they do not touch a native plugin.
# Godot --headless --path . --script res://tools/test_rewarded_admob.gd

const Mock := preload("res://scripts/ads/mock_rewarded_ads.gd")
const AdCfg := preload("res://scripts/ads/ad_config.gd")
const MobileScript := preload("res://scripts/ads/mobile_rewarded_ads.gd")

var _passed := 0
var _failed := 0
var _warnings: PackedStringArray = PackedStringArray()
var _dead: DeadNet
var _live_http := 0


func _initialize() -> void:
	ProjectSettings.set_setting("network/http_proxy/host", "127.0.0.1")
	ProjectSettings.set_setting("network/http_proxy/port", 9)
	var session := ConfigFile.new()
	session.set_value("session", "access_token", "offline-test-token")
	session.set_value("session", "refresh_token", "")
	session.set_value("session", "user_id", "11111111-1111-4111-8111-111111111111")
	session.set_value("session", "expires_at", int(Time.get_unix_time_from_system()) + 86400)
	session.save("user://supabase_session.cfg")
	call_deferred("_seal_network")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var version := Engine.get_version_info()
	var version_text := "%s.%s.%s" % [version.major, version.minor, version.patch]
	print("[admob-test] godot=%s status=%s" % [version_text, str(version.get("status", ""))])
	_seal_network()
	await process_frame
	_seal_network()
	var ads := root.get_node_or_null("RewardedAds")
	if ads == null:
		print("[admob-test] FAIL ads_missing")
		quit(1)
		return
	_check("godot_version", version_text == "4.7.2", version_text)
	_check("editor_uses_mock", ads._provider != null and ads._provider.get_script() == Mock)
	await _test_success(ads)
	await _test_cancel_and_failure(ads)
	await _test_callback_order(ads)
	await _test_old_ad_and_timeout(ads)
	_test_mobile_guards()
	_test_platforms()
	await _test_ui_notes(ads)
	_check("network_blocked", _live_http == 0, "live_completions=%d blocked_calls=%d" % [_live_http, _dead.calls if _dead != null else -1])
	print("[admob-test] scenarios=%d passed=%d failed=%d warnings=%d" % [_passed + _failed, _passed, _failed, _warnings.size()])
	for warning in _warnings:
		print("[admob-test] WARN %s" % warning)
	print("[admob-test] ok=%s" % (_failed == 0))
	quit(0 if _failed == 0 else 1)


func _check(name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[admob-test] %s=pass" % name)
	else:
		_failed += 1
		print("[admob-test] %s=FAIL %s" % [name, detail])


func _warn(text: String) -> void:
	_warnings.append(text)


func _session():
	return root.get_node("GameSession")


func _seal_network() -> void:
	var backend := root.get_node_or_null("Backend")
	if backend == null:
		return
	if _dead == null:
		_dead = DeadNet.new()
	backend._client = _dead
	var pending: Array = []
	for child in backend.get_children():
		if child is HTTPRequest:
			pending.append(child)
	for child in pending:
		var http := child as HTTPRequest
		if not http.request_completed.is_connected(_on_live_http):
			http.request_completed.connect(_on_live_http)
		http.cancel_request()
		http.queue_free()
	backend._busy = false
	backend._followup_busy = false
	backend._share_reward_busy = false
	backend._mission_busy = false


func _on_live_http(result: int, status: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and status >= 200:
		_live_http += 1


func _drop(game: Node) -> void:
	if is_instance_valid(game) and game.has_method("_unbind_rewarded_ads"):
		game._unbind_rewarded_ads()
	if is_instance_valid(game):
		game.queue_free()
	await process_frame


func _boot() -> Node:
	var game = load("res://scenes/game/game.gd").new()
	game.debug_skip_ready = true
	root.add_child(game)
	game._bind_rewarded_ads()
	var session = _session()
	session.match_mode = session.MODE_UNLIMITED
	session.practice_daily = false
	return game


func _offer(game: Node, run_coins: int, rank := 4) -> void:
	game._run_coins = run_coins
	game._over_rank = rank
	game._over_remaining = 90
	game.score = run_coins
	game._show_coin_ad()


func _note(game: Node) -> String:
	if game._coin_ad_note == null:
		return ""
	return str(game._coin_ad_note._text)


func _test_success(ads: Node) -> void:
	var session = _session()
	session.coins = 0
	session.add_coins(10)
	var game := _boot()
	ads.set_mock_outcome(Mock.Outcome.SUCCESS, false, 0.0)
	_offer(game, 10)
	var watch: Button = game._coin_ad_watch
	_check("success_offer_visible", game._coin_offer_open and watch != null and not watch.disabled and game.overlay != null and game.overlay.visible)
	watch.pressed.emit()
	watch.pressed.emit()
	await process_frame
	await process_frame
	_check("success_one_show", ads.mock_show_count() == 1, "shows=%d" % ads.mock_show_count())
	_check("success_bonus_once", int(session.coins) == 20 and game._run_coins == 0 and game._coin_reward_claimed, "wallet=%d" % int(session.coins))
	_check("success_excludes_other_rewards", int(session.coins) != 20 + 25 and int(session.coins) != 20 + 100)
	_check("success_post_run", game._wipe_again != null and not game._wipe_again.disabled and game._wipe_menu != null and not game._coin_offer_open)
	game._watch_coin_ad()
	game._on_rewarded_ad_earned(0)
	_check("success_second_redeem_ignored", int(session.coins) == 20)
	session.coins = 0
	session._load()
	_check("success_persists_restart", int(session.coins) == 20, "wallet=%d" % int(session.coins))
	await _drop(game)
	await process_frame


func _test_cancel_and_failure(ads: Node) -> void:
	var session = _session()
	session.coins = 0
	session.add_coins(9)
	var game := _boot()
	ads.set_mock_outcome(Mock.Outcome.SUCCESS, false, 0.0)
	_offer(game, 9)
	var skip: Button = null
	for child in game.overlay.get_children():
		if child is Button and child != game._coin_ad_watch:
			skip = child
	_check("cancel_no_button", skip != null)
	if skip != null:
		skip.pressed.emit()
	_check("cancel_keeps_base", int(session.coins) == 9 and game._wipe_again != null and not game._coin_offer_open, "wallet=%d" % int(session.coins))
	await _drop(game)
	session.coins = 0
	session.add_coins(8)
	game = _boot()
	ads.set_mock_outcome(Mock.Outcome.CLOSED_NO_REWARD, false, 0.0)
	_offer(game, 8)
	game._coin_ad_watch.pressed.emit()
	await process_frame
	await process_frame
	_check("close_no_bonus", int(session.coins) == 8 and game._coin_offer_open and not game._coin_reward_claimed and game.overlay.visible)
	_check("close_can_skip_after", not game._reward_request_active)
	var skip_again: Button = null
	for child in game.overlay.get_children():
		if child is Button and child != game._coin_ad_watch:
			skip_again = child
	if skip_again != null:
		skip_again.pressed.emit()
	_check("close_then_continue", int(session.coins) == 8 and game._wipe_again != null)
	await _drop(game)
	for outcome in [Mock.Outcome.FAILED, Mock.Outcome.UNAVAILABLE]:
		session.coins = 0
		session.add_coins(5)
		game = _boot()
		ads.set_mock_outcome(outcome, false, 0.0)
		_offer(game, 5)
		var before_shows: int = ads.mock_show_count()
		game._coin_ad_watch.pressed.emit()
		var attempt_session: int = game._reward_session
		await process_frame
		await process_frame
		ads.reward_earned.emit(attempt_session)
		var label := "fail" if outcome == Mock.Outcome.FAILED else "unavailable"
		_check("%s_no_bonus" % label, int(session.coins) == 5 and not game._coin_reward_claimed and game._coin_offer_open, "wallet=%d" % int(session.coins))
		_check("%s_note" % label, _note(game) == "NO AD AVAILABLE" and not game._coin_ad_watch.disabled, _note(game))
		if outcome == Mock.Outcome.UNAVAILABLE:
			_check("unavailable_no_show", ads.mock_show_count() == before_shows)
		await _drop(game)
	_check("sdk_missing_stays_unavailable", not _mobile_available_without_plugin())
	_warn("A disconnect is safe when the SDK emits ad_failed or ad_closed. A disconnect that emits nothing uses the same 45s watchdog as any other stalled show.")


func _mobile_available_without_plugin() -> bool:
	if Engine.has_singleton("PoingGodotAdMob") or Engine.has_singleton("PoingGodotAdMobRewardedAd"):
		_warn("A native AdMob singleton is present. This run did not call initialize, load, or show on it.")
		return false
	var mobile = load("res://scripts/ads/mobile_rewarded_ads.gd").new()
	root.add_child(mobile)
	var available: bool = mobile.is_available()
	mobile.show_session(1)
	mobile.queue_free()
	return available


func _test_callback_order(ads: Node) -> void:
	var session = _session()
	session.coins = 0
	session.add_coins(4)
	var game := _boot()
	ads.set_mock_outcome(Mock.Outcome.SUCCESS, true, 0.0)
	_offer(game, 4)
	game._coin_ad_watch.pressed.emit()
	await process_frame
	await process_frame
	_check("duplicate_reward_once", int(session.coins) == 8, "wallet=%d" % int(session.coins))
	await _drop(game)
	session.coins = 0
	session.add_coins(3)
	game = _boot()
	ads.set_mock_outcome(Mock.Outcome.STALL, false, 0.0)
	_offer(game, 3)
	game._coin_ad_watch.pressed.emit()
	game._coin_ad_watch.pressed.emit()
	var rapid_session: int = game._reward_session
	_check("rapid_yes_one_show", ads.mock_show_count() == 1 and rapid_session > 0, "shows=%d session=%d" % [ads.mock_show_count(), rapid_session])
	ads.reward_earned.emit(rapid_session)
	ads.ad_closed.emit(rapid_session)
	_check("reward_then_close_once", int(session.coins) == 6 and game._wipe_again != null)
	ads.reward_earned.emit(rapid_session)
	_check("late_reward_after_finish_ignored", int(session.coins) == 6)
	await _drop(game)
	session.coins = 0
	session.add_coins(2)
	game = _boot()
	ads.set_mock_outcome(Mock.Outcome.STALL, false, 0.0)
	_offer(game, 2)
	game._coin_ad_watch.pressed.emit()
	var close_session: int = game._reward_session
	ads.ad_closed.emit(close_session)
	var after_close := int(session.coins)
	ads.reward_earned.emit(close_session)
	_check("close_alone_pays_nothing", after_close == 2)
	_check("reward_after_close_pays_once", int(session.coins) == 4, "wallet=%d" % int(session.coins))
	await _drop(game)
	session.coins = 0
	session.add_coins(7)
	game = _boot()
	ads.set_mock_outcome(Mock.Outcome.STALL, false, 0.0)
	_offer(game, 7)
	game._watch_coin_ad()
	var leave_session: int = game._reward_session
	var skip: Button = null
	for child in game.overlay.get_children():
		if child is Button and child != game._coin_ad_watch:
			skip = child
	ads.ad_closed.emit(leave_session)
	if skip != null:
		skip.pressed.emit()
	var left := int(session.coins)
	ads.reward_earned.emit(leave_session)
	_check("late_reward_after_leave_ignored", int(session.coins) == left and left == 7 and game._wipe_again != null, "wallet=%d" % int(session.coins))
	await _drop(game)
	await process_frame


func _test_old_ad_and_timeout(ads: Node) -> void:
	var session = _session()
	session.coins = 0
	session.add_coins(5)
	var first := _boot()
	ads.set_mock_outcome(Mock.Outcome.STALL, false, 0.0)
	_offer(first, 5)
	first._coin_ad_watch.pressed.emit()
	var old_session: int = first._reward_session
	await _drop(first)
	await process_frame
	var second := _boot()
	_offer(second, 8)
	var before_yes := int(session.coins)
	ads.reward_earned.emit(old_session)
	_check("old_reward_before_yes_pays_nothing", int(session.coins) == before_yes and before_yes == 5 and second._coin_offer_open, "wallet=%d" % int(session.coins))
	second._coin_ad_watch.pressed.emit()
	var current_session: int = second._reward_session
	_check("new_yes_has_new_session", current_session > 0 and current_session != old_session, "old=%d current=%d" % [old_session, current_session])
	ads.reward_earned.emit(old_session)
	_check("old_reward_after_new_yes_pays_nothing", int(session.coins) == 5 and second._run_coins == 8, "wallet=%d" % int(session.coins))
	ads.reward_earned.emit(current_session)
	_check("current_session_pays_once", int(session.coins) == 13 and second._coin_reward_claimed and second._wipe_again != null, "wallet=%d" % int(session.coins))
	ads.reward_earned.emit(current_session)
	_check("current_session_duplicate_ignored", int(session.coins) == 13)
	await _drop(second)
	session.coins = 0
	session.add_coins(6)
	var stalled := _boot()
	stalled._reward_show_timeout = 0.2
	ads.set_mock_outcome(Mock.Outcome.STALL, false, 0.0)
	_offer(stalled, 6)
	stalled._coin_ad_watch.pressed.emit()
	var stalled_session: int = stalled._reward_session
	var shows_after_yes: int = ads.mock_show_count()
	stalled.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	stalled.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check("background_does_not_grant", int(session.coins) == 6 and stalled._wipe_again == null and not stalled.overlay.visible)
	await create_timer(0.35).timeout
	_check("timeout_restores_offer", stalled._coin_offer_open and stalled.overlay.visible and not stalled._reward_request_active and _note(stalled) == "AD TIMED OUT" and ads.mock_show_count() == shows_after_yes, _note(stalled))
	_check("timeout_keeps_base", int(session.coins) == 6 and stalled._run_coins == 6)
	ads.reward_earned.emit(stalled_session)
	_check("timeout_late_reward_pays_once", int(session.coins) == 12 and stalled._coin_reward_claimed and stalled._wipe_again != null, "wallet=%d" % int(session.coins))
	ads.reward_earned.emit(stalled_session)
	_check("timeout_late_reward_not_twice", int(session.coins) == 12)
	await _drop(stalled)
	session.coins = 0
	session.add_coins(6)
	var active := _boot()
	active._reward_show_timeout = 0.12
	active._reward_hard_cap = 0.4
	ads.set_mock_outcome(Mock.Outcome.STALL, false, 0.0)
	_offer(active, 6)
	active._coin_ad_watch.pressed.emit()
	ads._provider.show_active = true
	var active_session: int = active._reward_session
	await create_timer(0.2).timeout
	_check(
		"active_timeout_keeps_yes_disabled",
		active._coin_ad_watch.disabled and not active.overlay.visible and int(session.coins) == 6 and active._reward_session == active_session,
		"disabled=%s visible=%s wallet=%d" % [active._coin_ad_watch.disabled, active.overlay.visible, int(session.coins)]
	)
	active._watch_coin_ad()
	_check("active_timeout_second_yes_ignored", ads.mock_show_count() == 1 and active._reward_session == active_session, "shows=%d" % ads.mock_show_count())
	ads.reward_earned.emit(active_session)
	_check("active_timeout_late_reward_pays_once", int(session.coins) == 12 and active._coin_reward_claimed, "wallet=%d" % int(session.coins))
	ads._provider.show_active = false
	await _drop(active)
	session.coins = 0
	session.add_coins(4)
	var crossed := _boot()
	crossed._reward_show_timeout = 0.2
	ads.set_mock_outcome(Mock.Outcome.STALL, false, 0.0)
	_offer(crossed, 4)
	crossed._coin_ad_watch.pressed.emit()
	var crossed_old: int = crossed._reward_session
	_offer(crossed, 4)
	await create_timer(0.35).timeout
	_check("old_watchdog_ignores_new_offer", crossed._coin_offer_open and crossed.overlay.visible and crossed._reward_session == 0 and int(session.coins) == 4 and _note(crossed) == "", _note(crossed))
	crossed._coin_ad_watch.pressed.emit()
	var crossed_new: int = crossed._reward_session
	ads.reward_earned.emit(crossed_old)
	_check("old_timeout_reward_misses_new_show", int(session.coins) == 4 and crossed_new != crossed_old and crossed._coin_offer_open)
	await _drop(crossed)
	session.coins = 0
	session._save()


func _test_mobile_guards() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ads/mobile_rewarded_ads.gd")
	var bridge := FileAccess.get_file_as_string("res://addons/admob/gdscript/src/api/RewardedAd.gd")
	_check("mobile_callbacks_wired", source.contains("on_user_earned_reward") and source.contains("on_ad_dismissed_full_screen_content") and source.contains("on_ad_failed_to_show_full_screen_content") and source.contains("on_ad_failed_to_load") and source.contains("on_initialization_complete") and bridge.contains("on_rewarded_ad_user_earned_reward") and bridge.contains("on_rewarded_ad_dismissed_full_screen_content"))
	var dismiss_body := source.substr(source.find("func _on_ad_dismissed("), 400)
	_check("mobile_close_does_not_emit_reward", dismiss_body.contains("_emit_closed(") and not dismiss_body.contains("_emit_reward(") and not dismiss_body.contains("reward_earned.emit("))
	if Engine.has_singleton("PoingGodotAdMob") or Engine.has_singleton("PoingGodotAdMobRewardedAd"):
		_warn("Native rewarded plugin is loaded, so initialize/load/show were not called. Callback guards below use the GDScript handlers only.")
	var mobile = load("res://scripts/ads/mobile_rewarded_ads.gd").new()
	root.add_child(mobile)
	var rewards := [0]
	var closes := [0]
	var fails := [0]
	mobile.reward_earned.connect(func(_session_id: int) -> void: rewards[0] += 1)
	mobile.ad_closed.connect(func(_session_id: int) -> void: closes[0] += 1)
	mobile.ad_failed.connect(func(_reason: String, _session_id: int) -> void: fails[0] += 1)
	mobile._showing = true
	mobile._on_user_earned_reward(null, 4)
	mobile._on_user_earned_reward(null, 4)
	_check("mobile_duplicate_reward_ignored", int(rewards[0]) == 1, "rewards=%d" % int(rewards[0]))
	mobile._on_user_earned_reward(null, 5)
	_check("mobile_other_session_still_emits", int(rewards[0]) == 2)
	mobile._on_ad_dismissed(4)
	_check("mobile_dismiss_closes_without_second_reward", int(closes[0]) == 1 and int(rewards[0]) == 2)
	mobile._on_ad_failed_to_show(null, 4)
	_check("mobile_show_failure_signal", int(fails[0]) == 1 and int(rewards[0]) == 2)
	mobile._on_ad_failed_to_load(null)
	mobile._on_ad_failed_to_load(null)
	_check("mobile_load_retries_once", int(mobile._load_failures) == 2 and int(rewards[0]) == 2)
	if not Engine.has_singleton("PoingGodotAdMob"):
		mobile._start_sdk()
	else:
		_warn("PoingGodotAdMob is present. _start_sdk was not called, so this process did not initialize the SDK.")
	mobile._on_consent_failure(null)
	_check("consent_error_does_not_start_ads", not mobile._sdk_started and not mobile._ads_request_allowed and not mobile.is_available())
	_check("consent_obtained_allows", MobileScript.consent_status_allows(1) and MobileScript.consent_status_allows(3))
	_check("consent_unknown_or_required_blocks", not MobileScript.consent_status_allows(0) and not MobileScript.consent_status_allows(2) and not MobileScript.consent_status_allows(-1))
	_check("mobile_missing_plugin_does_not_init", not mobile._sdk_started and not mobile.is_available())
	mobile.queue_free()
	var web = load("res://scripts/ads/web_rewarded_ads.gd").new()
	root.add_child(web)
	var web_unavailable := [0]
	web.ad_unavailable.connect(func(_session_id: int) -> void: web_unavailable[0] += 1)
	var web_ready: bool = web.is_available()
	web.show_session(1)
	_check("web_and_desktop_unavailable", not web_ready and int(web_unavailable[0]) == 1)
	web.queue_free()


func _test_platforms() -> void:
	var ios := FileAccess.get_file_as_string("res://scripts/ads/ios_rewarded_ads.gd")
	var android := FileAccess.get_file_as_string("res://scripts/ads/android_rewarded_ads.gd")
	var project := FileAccess.get_file_as_string("res://project.godot")
	_check("platforms_share_mobile_provider", ios.contains("extends MobileRewardedAds") and android.contains("extends MobileRewardedAds"))
	_check("desktop_stays_on_test", AdCfg.monetization_mode() == "test" and not AdCfg.is_production_ads())
	_check("packed_ios_mode_is_production", AdCfg.mode_for_platform("ios") == "production")
	_check("packed_android_mode_is_test", AdCfg.mode_for_platform("android") == "test")
	_check("packed_ios_unit_is_live", AdCfg.rewarded_unit_for("ios", AdCfg.mode_for_platform("ios")) == AdCfg.IOS_REWARDED_UNIT_ID)
	_check("packed_android_unit_is_google_test", AdCfg.rewarded_unit_for("android", AdCfg.mode_for_platform("android")) == AdCfg.ANDROID_TEST_REWARDED_UNIT_ID and AdCfg.is_google_test_rewarded_unit(AdCfg.rewarded_unit_for("android", AdCfg.mode_for_platform("android"))))
	_check("android_test_unit", AdCfg.rewarded_unit_for("android", "test") == AdCfg.ANDROID_TEST_REWARDED_UNIT_ID)
	_check("ios_test_unit", AdCfg.rewarded_unit_for("ios", "test") == AdCfg.IOS_TEST_REWARDED_UNIT_ID)
	_check("ambiguous_mode_is_test", AdCfg.rewarded_unit_for("android", "") == AdCfg.ANDROID_TEST_REWARDED_UNIT_ID and AdCfg.rewarded_unit_for("ios", "release") == AdCfg.IOS_TEST_REWARDED_UNIT_ID)
	_check("android_production_unit_not_requested", AdCfg.rewarded_unit_for("android", "production") == AdCfg.ANDROID_REWARDED_UNIT_ID and AdCfg.rewarded_unit_for("android", "production") != AdCfg.ANDROID_TEST_REWARDED_UNIT_ID)
	_check("ios_production_unit_not_requested", AdCfg.rewarded_unit_for("ios", "production") == AdCfg.IOS_REWARDED_UNIT_ID and AdCfg.rewarded_unit_for("ios", "production") != AdCfg.IOS_TEST_REWARDED_UNIT_ID)
	_check("desktop_production_unit_empty", AdCfg.rewarded_unit_for("windows", "production").is_empty() and AdCfg.rewarded_unit_id().is_empty())
	_check("test_units_are_google", AdCfg.is_google_test_rewarded_unit(AdCfg.IOS_TEST_REWARDED_UNIT_ID) and AdCfg.is_google_test_rewarded_unit(AdCfg.ANDROID_TEST_REWARDED_UNIT_ID) and AdCfg.IOS_TEST_REWARDED_UNIT_ID != AdCfg.ANDROID_TEST_REWARDED_UNIT_ID)
	_check("production_units_distinct", AdCfg.IOS_REWARDED_UNIT_ID.contains("/") and AdCfg.ANDROID_REWARDED_UNIT_ID.contains("/") and not AdCfg.IOS_REWARDED_UNIT_ID.contains("~") and AdCfg.IOS_REWARDED_UNIT_ID != AdCfg.ANDROID_REWARDED_UNIT_ID)
	_check("app_ids_match_project", project.contains(AdCfg.IOS_APP_ID) and project.contains(AdCfg.ANDROID_APP_ID))
	_check("editor_mock_allowed", AdCfg.use_mock_provider())
	var mobile_source := FileAccess.get_file_as_string("res://scripts/ads/mobile_rewarded_ads.gd")
	_check("consent_missing_plugin_blocks", mobile_source.contains("consent plugin is missing. Ads will not be requested."))
	_check("privacy_options_api", mobile_source.contains("func show_privacy_options") and mobile_source.contains("PrivacyOptionsRequirementStatus.REQUIRED"))
	_test_att_policy(mobile_source)
	_warn("iOS and Android use one GDScript provider. The native PoingGodotAdMob singletons are not in this Windows run, so load, show, consent forms, and real callbacks were not executed. No ad request was made. The packed iOS mode selects the live iOS unit. The packed Android mode stays on Google's test unit.")
	_warn("Headless mode cannot confirm the offer artwork's spacing. The Yes and No hotspots, the failure note, and the post-run buttons were exercised. A phone screenshot is still needed for alignment.")


func _test_att_policy(mobile_source: String) -> void:
	var Att := preload("res://scripts/ads/att_authorization.gd")
	_check("att_first_launch_presents_form", Att.next_step(true, false, false, Att.Status.NOT_DETERMINED) == "present_form" and not Att.idfa_allowed(Att.Status.NOT_DETERMINED))
	_check("att_allow_requests_ad_with_idfa", Att.next_step(false, true, true, Att.Status.AUTHORIZED) == "request_ad" and Att.idfa_allowed(Att.Status.AUTHORIZED))
	_check("att_deny_still_requests_nontracking_ad", Att.next_step(false, true, true, Att.Status.DENIED) == "request_ad" and not Att.idfa_allowed(Att.Status.DENIED) and Att.ads_allowed(true, Att.Status.RESTRICTED))
	_check("att_already_determined_does_not_repeat", Att.next_step(false, false, true, Att.Status.DENIED) == "request_ad" and Att.next_step(true, true, true, Att.Status.AUTHORIZED) == "request_ad")
	_check("ump_required_presents_form_before_ads", Att.next_step(true, false, false, Att.Status.NOT_DETERMINED) == "present_form")
	_check("ump_not_required_requests_ad", Att.next_step(false, false, true, Att.Status.UNAVAILABLE) == "request_ad" and not Att.idfa_allowed(Att.Status.UNAVAILABLE))
	_check("ump_denied_holds_ads", Att.next_step(false, false, false, Att.Status.DENIED) == "hold_ads" and Att.next_step(false, true, false, Att.Status.AUTHORIZED) == "hold_ads")
	_check("consent_update_failure_is_not_authorization", Att.next_step(false, false, false, Att.Status.UNAVAILABLE) == "hold_ads" and not Att.idfa_allowed(Att.Status.UNAVAILABLE) and Att.next_step(false, false, true, Att.Status.UNAVAILABLE) == "request_ad")
	_check("resume_does_not_repeat_form", Att.next_step(true, true, true, Att.Status.NOT_DETERMINED) == "request_ad")
	_check("att_status_names", Att.status_name(Att.Status.NOT_DETERMINED) == "not_determined" and Att.status_name(Att.Status.AUTHORIZED) == "authorized" and Att.status_name(Att.Status.DENIED) == "denied" and Att.status_name(Att.Status.RESTRICTED) == "restricted" and Att.status_name(99) == "unavailable")
	var loaded := mobile_source.substr(mobile_source.find("func _on_consent_form_loaded"), 420)
	_check("ump_form_is_not_limited_to_gdpr_required", mobile_source.contains("should_present_ump_form") and mobile_source.contains("NOTIFICATION_APPLICATION_RESUMED") and not loaded.contains("ConsentStatus.REQUIRED"))
	_check("ump_form_does_not_grant_att", not mobile_source.contains("Status.AUTHORIZED") and mobile_source.contains("The form result is UMP consent, not Apple's tracking decision.") and not Att.idfa_allowed(Att.Status.UNAVAILABLE) and not Att.idfa_allowed(Att.Status.NOT_DETERMINED))
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var ios_plugin := FileAccess.get_file_as_string("res://addons/admob/ios/bin/ads/poing_godot_admob_ads.gd")
	_check("ios_tracking_declaration_present", preset.contains("NSUserTrackingUsageDescription") and preset.contains("privacy/tracking_enabled=true") and preset.contains("privacy/collected_data/device_id/used_for_tracking=true") and preset.contains("privacy/collected_data/advertising_data/used_for_tracking=true") and ios_plugin.contains("AppTrackingTransparency.framework") and ios_plugin.contains("SKAdNetworkItems"))


func _test_ui_notes(ads: Node) -> void:
	var session = _session()
	session.coins = 0
	session.add_coins(1)
	var game := _boot()
	ads.set_mock_outcome(Mock.Outcome.FAILED, false, 0.0)
	_offer(game, 1)
	var buttons := 0
	for child in game.overlay.get_children():
		if child is Button:
			buttons += 1
	_check("ui_two_choices", buttons == 2 and game.overlay.visible)
	game._coin_ad_watch.pressed.emit()
	await process_frame
	_check("ui_failure_restores_yes", game.overlay.visible and not game._coin_ad_watch.disabled and _note(game) == "NO AD AVAILABLE")
	game._coin_ad_watch.pressed.emit()
	_check("ui_retry_after_failure_keeps_base", ads.mock_show_count() == 2 and int(session.coins) == 1, "shows=%d wallet=%d" % [ads.mock_show_count(), int(session.coins)])
	await _drop(game)
	session.coins = 0
	session._save()


class DeadNet:
	var calls := 0

	func cancel() -> void:
		pass

	func is_ready() -> bool:
		return true

	func auth_headers(_access_token: String = "") -> PackedStringArray:
		return PackedStringArray()

	func request_json(_method: String, _url: String, _headers: PackedStringArray, _body: String = "") -> Dictionary:
		calls += 1
		return {
			"ok": false,
			"status": 0,
			"data": null,
			"error": "blocked",
			"godot_http_result": HTTPRequest.RESULT_CANT_CONNECT,
		}

	func request_json_independent(method: String, url: String, headers: PackedStringArray, body: String = "") -> Dictionary:
		return request_json(method, url, headers, body)
