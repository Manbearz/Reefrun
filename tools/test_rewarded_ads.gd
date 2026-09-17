extends SceneTree

func _initialize() -> void:
	root.add_child(Runner.new())


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

	func on_earned() -> void:
		if not offer_open:
			return
		if claimed:
			return
		finish()

	func on_closed() -> void:
		if claimed:
			return
		if not offer_open:
			return
		restore("")

	func on_failed(_reason: String) -> void:
		if claimed:
			return
		restore("No ad available")

	func on_unavailable() -> void:
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
