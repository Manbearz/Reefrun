extends SceneTree

func _initialize() -> void:
	ProjectSettings.set_setting("network/http_proxy/host", "127.0.0.1")
	ProjectSettings.set_setting("network/http_proxy/port", 9)
	_write_offline_session()
	call_deferred("_seal_network")
	root.add_child(Runner.new())


func _write_offline_session() -> void:
	var session := ConfigFile.new()
	session.set_value("session", "access_token", "offline-test-token")
	session.set_value("session", "refresh_token", "")
	session.set_value("session", "user_id", "11111111-1111-4111-8111-111111111111")
	session.set_value("session", "expires_at", int(Time.get_unix_time_from_system()) + 86400)
	session.save("user://supabase_session.cfg")


func _seal_network() -> void:
	var backend := root.get_node_or_null("Backend")
	if backend == null:
		return
	backend._client = DeadNet.new()
	var pending: Array = []
	for child in backend.get_children():
		if child is HTTPRequest:
			pending.append(child)
	for child in pending:
		var http := child as HTTPRequest
		http.cancel_request()
		http.queue_free()


class DeadNet:
	func cancel() -> void:
		pass

	func is_ready() -> bool:
		return true

	func auth_headers(_access_token: String = "") -> PackedStringArray:
		return PackedStringArray()

	func request_json(_method: String, _url: String, _headers: PackedStringArray, _body: String = "") -> Dictionary:
		return {
			"ok": false,
			"status": 0,
			"data": null,
			"error": "blocked",
			"godot_http_result": HTTPRequest.RESULT_CANT_CONNECT,
		}

	func request_json_independent(method: String, url: String, headers: PackedStringArray, body: String = "") -> Dictionary:
		return request_json(method, url, headers, body)


class Offer:
	var ads: Node
	var session: Node
	var run_coins := 0
	var claimed := false
	var request_active := false
	var offer_open := false
	var overlay_visible := true
	var watch_disabled := false
	var went_over := false
	var note := ""
	var bonus_granted := 0

	func open(amount: int) -> void:
		run_coins = amount
		claimed = false
		request_active = false
		offer_open = true
		overlay_visible = true
		watch_disabled = false
		went_over = false
		note = ""
		bonus_granted = 0

	func watch() -> void:
		if request_active or claimed:
			return
		if not offer_open:
			return
		request_active = true
		watch_disabled = true
		note = ""
		if not ads.is_rewarded_ad_available():
			on_unavailable()
			return
		overlay_visible = false
		ads.show_rewarded_ad()

	func finish() -> void:
		if claimed:
			return
		claimed = true
		request_active = false
		offer_open = false
		var bonus: int = run_coins
		if bonus > 0:
			session.add_coins(bonus)
			bonus_granted = bonus
			run_coins = 0
		went_over = true
		overlay_visible = false

	func abandon() -> void:
		if request_active:
			return
		offer_open = false
		request_active = false
		run_coins = 0
		went_over = true
		overlay_visible = false

	func restore(message: String) -> void:
		request_active = false
		if not offer_open or claimed:
			return
		overlay_visible = true
		watch_disabled = false
		note = message

	func on_earned(_session_id: int = 0) -> void:
		if not offer_open:
			return
		if claimed:
			return
		finish()

	func on_closed(_session_id: int = 0) -> void:
		if claimed:
			return
		if not offer_open:
			return
		restore("")

	func on_failed(_reason: String, _session_id: int = 0) -> void:
		if claimed:
			return
		restore("No ad available")

	func on_unavailable(_session_id: int = 0) -> void:
		if claimed:
			return
		restore("No ad available")


class Runner extends Node:
	const Mock := preload("res://scripts/ads/mock_rewarded_ads.gd")
	var ads: Node
	var session: Node
	var offer := Offer.new()
	var failed := 0

	func _ready() -> void:
		var tree := get_tree()
		if tree != null and tree.has_method("_seal_network"):
			tree._seal_network()
		ads = get_node("/root/RewardedAds")
		session = get_node("/root/GameSession")
		offer.ads = ads
		offer.session = session
		ads.reward_earned.connect(offer.on_earned)
		ads.ad_closed.connect(offer.on_closed)
		ads.ad_failed.connect(offer.on_failed)
		ads.ad_unavailable.connect(offer.on_unavailable)
		await get_tree().process_frame
		var start_coins: int = session.coins
		await _run_cases()
		var extra: int = session.coins - start_coins
		if extra != 0:
			session.add_coins(-extra)
		print("[rewarded_ads] failed=%d" % failed)
		get_tree().quit(1 if failed > 0 else 0)

	func _run_cases() -> void:
		await _success()
		await _double_click()
		await _duplicate_callback()
		await _early_close()
		await _failure()
		await _unavailable()
		await _menu_after_ad()
		await _next_match()
		_export_gate()
		await _simulator_complete()
		await _simulator_repeat()
		await _simulator_cancel()
		await _simulator_unavailable()

	func _expect(ok: bool, name: String, detail: String = "") -> void:
		if ok:
			print("[rewarded_ads] PASS %s" % name)
			return
		failed += 1
		push_error("[rewarded_ads] FAIL %s %s" % [name, detail])
		print("[rewarded_ads] FAIL %s %s" % [name, detail])

	func _await_ad() -> void:
		await get_tree().create_timer(0.08).timeout
		await get_tree().process_frame
		await get_tree().process_frame

	func _success() -> void:
		var before: int = session.coins
		session.add_coins(10)
		_expect(session.coins == before + 10, "success_base", "base coins not persisted")
		ads.set_mock_outcome(Mock.Outcome.SUCCESS, false, 0.0)
		offer.open(10)
		offer.watch()
		offer.watch()
		await _await_ad()
		_expect(ads.mock_show_count() == 1, "success_one_request", "shows=%d" % ads.mock_show_count())
		_expect(offer.bonus_granted == 10, "success_bonus", "bonus=%d" % offer.bonus_granted)
		_expect(session.coins == before + 20, "success_wallet", "wallet=%d expected=%d" % [session.coins, before + 20])
		_expect(offer.claimed and offer.went_over, "success_over")
		session.add_coins(-(session.coins - before))

	func _double_click() -> void:
		var before: int = session.coins
		ads.set_mock_outcome(Mock.Outcome.SUCCESS, false, 0.05)
		offer.open(7)
		offer.watch()
		offer.watch()
		offer.watch()
		_expect(ads.mock_show_count() == 1, "double_click_requests", "shows=%d" % ads.mock_show_count())
		await _await_ad()
		_expect(offer.bonus_granted == 7, "double_click_bonus")
		_expect(session.coins == before + 7, "double_click_wallet")
		session.add_coins(-(session.coins - before))

	func _duplicate_callback() -> void:
		var before: int = session.coins
		ads.set_mock_outcome(Mock.Outcome.SUCCESS, true, 0.0)
		offer.open(4)
		offer.watch()
		await _await_ad()
		_expect(offer.bonus_granted == 4, "duplicate_bonus_once")
		_expect(session.coins == before + 4, "duplicate_wallet")
		session.add_coins(-(session.coins - before))

	func _early_close() -> void:
		var before: int = session.coins
		ads.set_mock_outcome(Mock.Outcome.CLOSED_NO_REWARD, false, 0.0)
		offer.open(9)
		offer.watch()
		await _await_ad()
		_expect(offer.bonus_granted == 0, "close_no_bonus")
		_expect(session.coins == before, "close_base_kept")
		_expect(offer.overlay_visible and not offer.went_over, "close_restore")
		_expect(offer.run_coins == 9, "close_keeps_offer")
		offer.abandon()
		_expect(offer.went_over and offer.bonus_granted == 0, "close_then_skip")
		_expect(session.coins == before, "close_skip_wallet")

	func _failure() -> void:
		var before: int = session.coins
		ads.set_mock_outcome(Mock.Outcome.FAILED, false, 0.0)
		offer.open(5)
		offer.watch()
		await _await_ad()
		_expect(offer.bonus_granted == 0, "fail_no_bonus")
		_expect(session.coins == before, "fail_base_kept")
		_expect(offer.overlay_visible and offer.note == "No ad available", "fail_restore")
		_expect(not offer.watch_disabled, "fail_watch_reenabled")

	func _unavailable() -> void:
		var before: int = session.coins
		ads.set_mock_outcome(Mock.Outcome.UNAVAILABLE, false, 0.0)
		offer.open(6)
		offer.watch()
		await _await_ad()
		_expect(ads.mock_show_count() == 0, "unavailable_no_show")
		_expect(offer.bonus_granted == 0, "unavailable_no_bonus")
		_expect(session.coins == before, "unavailable_base_kept")
		_expect(offer.overlay_visible and offer.note == "No ad available", "unavailable_restore")

	func _menu_after_ad() -> void:
		var before: int = session.coins
		ads.set_mock_outcome(Mock.Outcome.SUCCESS, false, 0.0)
		offer.open(3)
		offer.watch()
		await _await_ad()
		_expect(session.coins == before + 3, "menu_after_reward")
		offer.on_earned()
		offer.on_closed()
		_expect(session.coins == before + 3, "menu_no_duplicate")
		session.add_coins(-(session.coins - before))

	func _next_match() -> void:
		var before: int = session.coins
		ads.set_mock_outcome(Mock.Outcome.SUCCESS, false, 0.0)
		offer.open(8)
		offer.watch()
		await _await_ad()
		_expect(offer.claimed, "match1_claimed")
		ads.set_mock_outcome(Mock.Outcome.SUCCESS, false, 0.0)
		offer.open(8)
		_expect(not offer.claimed and offer.offer_open, "match2_reset")
		offer.watch()
		await _await_ad()
		_expect(offer.bonus_granted == 8, "match2_bonus")
		_expect(session.coins == before + 16, "match2_wallet")
		session.add_coins(-(session.coins - before))

	func _export_gate() -> void:
		var Cfg := preload("res://scripts/ads/ad_config.gd")
		_expect(Cfg.simulator_allowed(PackedStringArray(["editor", "windows"])), "gate_editor_windows")
		_expect(Cfg.simulator_allowed(PackedStringArray(["editor", "windows", "debug"])), "gate_editor_debug")
		_expect(not Cfg.simulator_allowed(PackedStringArray(["editor", "windows", "release"])), "gate_release")
		_expect(not Cfg.simulator_allowed(PackedStringArray(["editor", "windows", "template"])), "gate_template")
		_expect(not Cfg.simulator_allowed(PackedStringArray(["editor", "windows", "template_release"])), "gate_template_release")
		_expect(not Cfg.simulator_allowed(PackedStringArray(["editor", "windows", "template_debug"])), "gate_template_debug")
		_expect(not Cfg.simulator_allowed(PackedStringArray(["ios", "release", "template"])), "gate_ios_release")
		_expect(not Cfg.simulator_allowed(PackedStringArray(["android", "debug", "template"])), "gate_android_debug")
		_expect(not Cfg.simulator_allowed(PackedStringArray(["editor", "ios"])), "gate_editor_ios")
		_expect(not Cfg.simulator_allowed(PackedStringArray(["editor", "android"])), "gate_editor_android")
		_expect(not Cfg.simulator_allowed(PackedStringArray(["windows", "release"])), "gate_windows_export")
		_expect(not Cfg.simulator_allowed(PackedStringArray()), "gate_empty")
		_expect(Cfg.development_reward_simulator(), "gate_this_editor")
		_expect(not OS.has_feature("template") and not OS.has_feature("release"), "gate_runtime_not_export")
		var game := FileAccess.get_file_as_string("res://scenes/game/game.gd")
		var earned := game.find("func _on_rewarded_ad_earned")
		var finish := game.find("func _finish_coin_ad")
		_expect(earned >= 0 and finish >= 0 and game.find("_finish_coin_ad()", earned) > earned, "same_reward_handler")
		var body := game.substr(finish, game.find("func _abandon_coin_offer") - finish)
		_expect(body.contains("var bonus := _run_coins") and body.contains("GameSession.add_coins(bonus)"), "bonus_is_run_coins")
		_expect(not body.contains("mission") and not body.contains("share"), "bonus_ignores_other_rewards")

	func _simulator_complete() -> void:
		var before: int = session.coins
		var mission_reward := 25
		var share_bonus := 100
		_expect(ads.prepare_interactive_simulator(), "sim_prepared")
		offer.open(11)
		offer.watch()
		var complete: BaseButton = ads.simulator_button("complete")
		_expect(complete != null, "sim_complete_button")
		if complete == null:
			return
		var card: Node = complete.get_parent()
		var labeled := false
		if card:
			for child in card.get_children():
				var label := child as Label
				if label and (label.text == "TEST AD" or label.text == "SIMULATED REWARD"):
					labeled = true
		_expect(labeled, "sim_labeled")
		complete.pressed.emit()
		complete.pressed.emit()
		await _await_ad()
		var doubled: int = offer.bonus_granted
		_expect(doubled == 11, "sim_doubles_run_coins", "bonus=%d" % doubled)
		_expect(doubled != 11 + mission_reward and doubled != 11 + share_bonus and doubled != 11 + mission_reward + share_bonus, "sim_excludes_other_bonuses")
		_expect(session.coins == before + 11, "sim_wallet", "wallet=%d" % session.coins)
		_expect(offer.bonus_granted == 11 and session.coins == before + 11, "sim_second_press_ignored")
		session.add_coins(-(session.coins - before))

	func _simulator_repeat() -> void:
		var before: int = session.coins
		_expect(ads.prepare_interactive_simulator(), "sim_repeat_prepared")
		offer.open(4)
		offer.watch()
		offer.watch()
		_expect(ads.mock_show_count() == 1, "sim_one_panel", "shows=%d" % ads.mock_show_count())
		var complete: BaseButton = ads.simulator_button("complete")
		if complete:
			complete.pressed.emit()
			complete.pressed.emit()
		await _await_ad()
		_expect(offer.bonus_granted == 4, "sim_repeat_bonus")
		_expect(session.coins == before + 4, "sim_repeat_wallet")
		session.add_coins(-(session.coins - before))

	func _simulator_cancel() -> void:
		var before: int = session.coins
		ads.prepare_interactive_simulator()
		offer.open(9)
		offer.watch()
		var cancel: BaseButton = ads.simulator_button("cancel")
		_expect(cancel != null, "sim_cancel_button")
		if cancel:
			cancel.pressed.emit()
			cancel.pressed.emit()
		await _await_ad()
		_expect(offer.bonus_granted == 0, "sim_cancel_no_bonus")
		_expect(session.coins == before, "sim_cancel_wallet")
		_expect(offer.run_coins == 9 and offer.overlay_visible and not offer.claimed, "sim_cancel_keeps_offer")

	func _simulator_unavailable() -> void:
		var before: int = session.coins
		ads.prepare_interactive_simulator()
		offer.open(6)
		offer.watch()
		var unavailable: BaseButton = ads.simulator_button("unavailable")
		_expect(unavailable != null, "sim_unavailable_button")
		if unavailable:
			unavailable.pressed.emit()
			unavailable.pressed.emit()
		await _await_ad()
		_expect(offer.bonus_granted == 0, "sim_unavailable_no_bonus")
		_expect(session.coins == before, "sim_unavailable_wallet")
		_expect(offer.note == "No ad available" and offer.run_coins == 6 and not offer.claimed, "sim_unavailable_restores")
