extends SceneTree

const Missions := preload("res://scripts/daily_missions.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _check(_test_catalog(), "catalog") and ok
	ok = _check(_test_same_rotation(), "same rotation") and ok
	ok = _check(_test_recent_and_family(), "recent and family") and ok
	ok = _check(_test_utc_midnight(), "utc midnight") and ok
	ok = _check(_test_progress_rules(), "progress") and ok
	ok = _check(_test_rewards(), "rewards") and ok
	ok = _check(_test_auto_claim(), "auto claim") and ok
	ok = _check(_test_runs(), "runs") and ok
	ok = _check(_test_countdown(), "countdown") and ok
	ok = _check(_test_overlay_mapping(), "overlay mapping") and ok
	ok = _check(_test_separation(), "separation") and ok
	ok = _check(_test_widget_layout(), "widget layout") and ok
	ok = _check(_test_lobby_clock(), "lobby clock") and ok
	ok = _check(await _test_shade_fold(), "shade fold") and ok
	ok = _check(_test_screen_board(), "screen board") and ok
	ok = _check(_test_claim_marks(), "claim marks") and ok
	ok = _check(_test_board_chrome(), "board chrome") and ok
	ok = _check(_test_deep_dive_missions(), "deep dive missions") and ok
	ok = _check(_test_mission_icons(), "mission icons") and ok
	print("[missions] ok=%s" % ok)
	quit(0 if ok else 1)


func _test_catalog() -> bool:
	var rows: Array = Missions.catalog()
	if rows.size() != 90:
		return false
	var enabled := 0
	var seen := {}
	for mission in rows:
		var mission_id := int(mission.get("id", 0))
		var tier := str(mission.get("tier", ""))
		var reward := int(mission.get("reward", 0))
		if Missions.EXCLUDED.has(mission_id):
			if bool(mission.get("enabled", true)):
				return false
		elif not bool(mission.get("enabled", false)):
			return false
		else:
			enabled += 1
		if tier == "easy" and reward != 5:
			return false
		if tier == "medium" and reward != 10:
			return false
		if tier == "hard" and reward != 20:
			return false
		if str(mission.get("rule", "")) == "pipes_best" and int(mission.get("goal", 0)) > Missions.MAX_PIPES_PER_RUN and bool(mission.get("enabled", false)):
			return false
		var key := "%s|%d|%d" % [str(mission.get("rule", "")), int(mission.get("goal", 0)), int(mission.get("goal_b", 0))]
		if bool(mission.get("enabled", false)):
			if seen.has(key):
				return false
			seen[key] = mission_id
	return enabled == 84


func _test_deep_dive_missions() -> bool:
	var regular := {"easy": 0, "medium": 0, "hard": 0}
	var added := {"easy": 0, "medium": 0, "hard": 0}
	var slots := {"easy": 0, "medium": 0, "hard": 0}
	for mission in Missions.catalog():
		var mission_id := int(mission.get("id", 0))
		var tier := str(mission.get("tier", ""))
		if mission_id <= 45:
			regular[tier] = int(regular[tier]) + 1
		else:
			added[tier] = int(added[tier]) + 1
			if str(mission.get("description", "")).length() > 56:
				return false
			if not bool(mission.get("enabled", false)):
				return false
	if regular.easy != 15 or regular.medium != 15 or regular.hard != 15:
		return false
	if added.easy != 15 or added.medium != 15 or added.hard != 15:
		return false
	var board: Dictionary = Missions.preview_rotation("2026-10-19", [])
	for tier in ["easy", "medium", "hard"]:
		slots[tier] = int(board.get(tier, 0))
		if int(Missions.REWARDS.get(tier, 0)) != (5 if tier == "easy" else 10 if tier == "medium" else 20):
			return false
	if slots.easy == 0 or slots.medium == 0 or slots.hard == 0:
		return false
	if board.size() != 6:
		return false
	var edge := Missions.count_lane_change(1, 1)
	var left := Missions.count_lane_change(3, 2)
	var right := Missions.count_lane_change(2, 3)
	if int(edge.lanes) != 0 or int(left.left) != 1 or int(left.right) != 0 or int(right.right) != 1:
		return false
	var dive := {
		"dives_entered": 1,
		"dives_completed": 1,
		"dive_seconds": 20,
		"lane_changes": 4,
		"lanes_left": 2,
		"lanes_right": 2,
		"obstacles": 6,
		"mines": 1,
	}
	if Missions.accept_dive(20, dive) or not Missions.accept_dive(30, dive):
		return false
	if Missions.accept_dive(30, {"dives_entered": 1, "dives_completed": 0, "obstacles": 2, "mines": 3}):
		return false
	var first: Array = Missions.enqueue([], "dive-run-1", 40, 80, 4, dive)
	var again: Array = Missions.enqueue(first, "dive-run-1", 40, 80, 4, dive)
	var second: Array = Missions.enqueue(again, "dive-run-2", 70, 160, 8, {
		"dives_entered": 2,
		"dives_completed": 1,
		"dive_seconds": 20,
		"lane_changes": 1,
		"lanes_left": 1,
		"lanes_right": 0,
		"obstacles": 4,
		"mines": 0,
	})
	if first.size() != 1 or again.size() != 1 or second.size() != 2:
		return false
	if int(second[0].get("obstacles", 0)) != 6 or int(second[1].get("dives_completed", 0)) != 1:
		return false
	if Missions.accept_run(40, 110, 4, 0):
		return false
	if not Missions.accept_run(40, 110, 4, 1):
		return false
	var daily_game := _read_project("res://scenes/game/game.gd")
	var resume := _function_body(daily_game, "_enter_swim_resume")
	var halt := _function_body(daily_game, "_halt_dive")
	var play := _function_body(daily_game, "_enter_dive_play")
	if not resume.contains("_mission_dives_completed += 1"):
		return false
	if halt.contains("_mission_dives_completed"):
		return false
	if not play.contains("_mission_dives_entered += 1"):
		return false
	if not daily_game.contains("_mission_dives_entered = 0"):
		return false
	var repo = load("res://scripts/backend/daily_mission_repository.gd").new()
	var extended := str(repo.record_body("dive-run-1", 40, 80, 4, dive))
	var legacy := str(repo.legacy_record_body("dive-run-1", 40, 80, 4))
	if not extended.contains("p_dives_entered") or legacy.contains("p_dives_entered"):
		return false
	return Missions.should_report("unlimited", false) and not Missions.should_report("daily", false)


func _function_body(source: String, function_name: String) -> String:
	var start := source.find("func %s" % function_name)
	if start < 0:
		return ""
	var next := source.find("\nfunc ", start + 5)
	if next < 0:
		return source.substr(start)
	return source.substr(start, next - start)


func _test_same_rotation() -> bool:
	var first: Dictionary = Missions.preview_rotation("2026-10-16", [])
	var second: Dictionary = Missions.preview_rotation("2026-10-16", [])
	if first != second:
		return false
	for tier in ["easy", "medium", "hard"]:
		var mission: Dictionary = Missions.mission_by_id(int(first.get(tier, 0)))
		if mission.is_empty() or not bool(mission.get("enabled", false)):
			return false
		if str(mission.get("tier", "")) != tier:
			return false
	if first.easy_family == first.medium_family or first.medium_family == first.hard_family or first.easy_family == first.hard_family:
		return false
	return true


func _test_recent_and_family() -> bool:
	var easy_ids: Array = []
	for mission in Missions.catalog():
		if str(mission.get("tier", "")) == "easy" and bool(mission.get("enabled", false)):
			easy_ids.append(int(mission.get("id", 0)))
	var keep: int = easy_ids[0]
	var recent: Array = []
	for mission_id in easy_ids:
		if mission_id != keep:
			recent.append(mission_id)
	var picked: Dictionary = Missions.preview_rotation("2026-10-16", recent)
	if int(picked.get("easy", 0)) != keep:
		return false
	var all_recent: Array = []
	for mission in Missions.catalog():
		if bool(mission.get("enabled", false)):
			all_recent.append(int(mission.get("id", 0)))
	var fallback: Dictionary = Missions.preview_rotation("2026-10-16", all_recent)
	for tier in ["easy", "medium", "hard"]:
		if Missions.EXCLUDED.has(int(fallback.get(tier, 0))):
			return false
	return true


func _test_utc_midnight() -> bool:
	var before := int(Time.get_unix_time_from_datetime_dict({
		"year": 2026, "month": 10, "day": 16, "hour": 23, "minute": 59, "second": 59,
	}))
	var after := int(Time.get_unix_time_from_datetime_dict({
		"year": 2026, "month": 10, "day": 17, "hour": 0, "minute": 0, "second": 0,
	}))
	var before_key := Missions.utc_date_key(before)
	var after_key := Missions.utc_date_key(after)
	if before_key != "2026-10-16" or after_key != "2026-10-17":
		return false
	var late: Dictionary = Missions.preview_rotation(before_key, [])
	var early: Dictionary = Missions.preview_rotation(after_key, [late.easy, late.medium, late.hard])
	return (
		int(early.easy) != int(late.easy)
		and int(early.medium) != int(late.medium)
		and int(early.hard) != int(late.hard)
	)


func _test_progress_rules() -> bool:
	var total: Dictionary = Missions.evaluate("pipes_total", 10, 0, {"pipes_total": 10})
	if not bool(total.complete) or int(total.progress) != 10:
		return false
	var best: Dictionary = Missions.evaluate("pipes_best", 25, 0, {"best_pipes": 24})
	if bool(best.complete):
		return false
	var runs: Dictionary = Missions.evaluate("runs", 3, 0, {"runs": 3})
	if not bool(runs.complete):
		return false
	var survived: Dictionary = Missions.evaluate("survive_best", 30, 0, {"best_seconds": 30})
	if not bool(survived.complete):
		return false
	var coins: Dictionary = Missions.evaluate("coins_total", 50, 0, {"gameplay_coins": 49})
	if bool(coins.complete):
		return false
	var multi: Dictionary = Missions.evaluate("runs_at_least", 5, 3, {"run_pipes": [5, 4, 9, 5]})
	if int(multi.progress) != 3 or not bool(multi.complete):
		return false
	var window: Dictionary = Missions.evaluate("window_sum", 50, 3, {"run_pipes": [10, 40, 5, 30]})
	if int(window.progress) != 75 or not bool(window.complete):
		return false
	var sparse: Dictionary = Missions.evaluate("window_sum", 50, 3, {"run_pipes": [30, 0, 30]})
	if int(sparse.progress) != 60:
		return false
	var entered: Dictionary = Missions.evaluate("dives_entered", 2, 0, {"dives_entered": 2})
	var one_run: Dictionary = Missions.evaluate("dives_best", 2, 0, {"dives_completed": 4, "best_dives": 1})
	var mines: Dictionary = Missions.evaluate("mines_total", 5, 0, {"mines_passed": 5})
	return bool(entered.complete) and not bool(one_run.complete) and bool(mines.complete)


func _test_rewards() -> bool:
	if Missions.REWARDS.easy != 5 or Missions.REWARDS.medium != 10 or Missions.REWARDS.hard != 20 or Missions.REWARDS.bonus != 25:
		return false
	if Missions.REWARDS.easy + Missions.REWARDS.medium + Missions.REWARDS.hard + Missions.REWARDS.bonus != Missions.MAX_DAILY_REWARD:
		return false
	var claimed := {}
	var easy := Missions.claim_payout(claimed, "easy", true, false)
	claimed.easy = true
	var easy_again := Missions.claim_payout(claimed, "easy", true, false)
	var medium := Missions.claim_payout(claimed, "medium", true, false)
	claimed.medium = true
	var hard := Missions.claim_payout(claimed, "hard", true, false)
	claimed.hard = true
	var early_bonus := Missions.claim_payout({"easy": true}, "bonus", true, false)
	var bonus := Missions.claim_payout(claimed, "bonus", true, true)
	claimed.bonus = true
	var extra := Missions.claim_payout(claimed, "bonus", true, true)
	if easy != 5 or medium != 10 or hard != 20 or bonus != 25:
		return false
	if easy_again != 0 or early_bonus != 0 or extra != 0:
		return false
	if easy + medium + hard + bonus != 60:
		return false
	return Missions.reward_delta(0, 5) == 5 and Missions.reward_delta(5, 5) == 0 and Missions.reward_delta(5, 15) == 10


func _test_auto_claim() -> bool:
	var waiting := {
		"ok": true,
		"mission_date": "2026-10-18",
		"slots": [
			{"slot": "easy", "complete": true, "claimed": false},
			{"slot": "medium", "complete": true, "claimed": false},
			{"slot": "hard", "complete": false, "claimed": false},
		],
		"bonus": {"unlocked": false, "claimed": false, "complete": true},
	}
	if Missions.next_auto_claim(waiting) != "easy":
		return false
	if Missions.next_auto_claim(waiting, "easy") != "medium":
		return false
	if Missions.next_auto_claim({"ok": false, "slots": waiting.slots}) != "":
		return false
	waiting.slots[0].claimed = true
	if Missions.next_auto_claim(waiting) != "medium":
		return false
	waiting.slots[1].claimed = true
	waiting.slots[2].complete = true
	if Missions.next_auto_claim(waiting) != "hard":
		return false
	if Missions.next_auto_claim(waiting, "hard") != "":
		return false
	waiting.slots[2].claimed = true
	waiting.bonus.unlocked = true
	waiting.bonus.complete = true
	if Missions.next_auto_claim(waiting) != "bonus":
		return false
	waiting.bonus.claimed = true
	if Missions.next_auto_claim(waiting) != "":
		return false
	var same_day := Missions.reward_delta(15, 15) == 0 and Missions.reward_delta(15, 40) == 25
	return same_day


func _test_runs() -> bool:
	if Missions.should_report("daily", false) or Missions.should_report("unlimited", true):
		return false
	if not Missions.should_report("unlimited", false):
		return false
	if Missions.gameplay_payload(2, 2) != 2:
		return false
	if Missions.accept_run(100, 200, 0):
		return false
	if Missions.accept_run(10, 20, 4):
		return false
	if not Missions.accept_run(10, 20, 2):
		return false
	if not Missions.accept_run(80, 180, 16):
		return false
	if not Missions.accept_run(60, 122, 12):
		return false
	if Missions.accept_run(60, 400, 0):
		return false
	var once: Array = Missions.enqueue([], "run-0001", 10, 20, 2)
	var twice: Array = Missions.enqueue(once, "run-0001", 10, 20, 2)
	return once.size() == 1 and twice.size() == 1


func _test_overlay_mapping() -> bool:
	if not is_equal_approx(Missions.progress_ratio(25, 50), 0.5):
		return false
	if not is_equal_approx(Missions.progress_ratio(7, 10), 0.7):
		return false
	if not is_equal_approx(Missions.progress_ratio(45, 60), 0.75):
		return false
	if Missions.progress_ratio(0, 50) != 0.0 or Missions.progress_ratio(80, 50) != 1.0 or Missions.progress_ratio(3, 0) != 0.0:
		return false
	if Missions.display_text("Pass 50 pipes total.") != "Pass 50 pipes total":
		return false
	var kinds := {
		"pipe": 0,
		"fish": 0,
		"stopwatch": 0,
		"coin": 0,
		"flag": 0,
		"medal": 0,
	}
	for mission in Missions.catalog():
		var mission_id := int(mission.get("id", 0))
		var description := str(mission.get("description", ""))
		var kind := Missions.icon_kind(mission_id, description)
		if not kinds.has(kind):
			return false
		kinds[kind] = int(kinds[kind]) + 1
		var expected := ""
		if description.to_lower().contains("checkpoint"):
			expected = "flag"
		else:
			match str(mission.get("family", "")):
				"total_pipes", "one_run_pipes":
					expected = "pipe"
				"run_count":
					expected = "fish"
				"survive":
					expected = "stopwatch"
				"earn_coins", "coin_runs":
					expected = "coin"
				"multi_threshold", "window_sum", "dive_lanes", "dive_left", "dive_right", "dive_dodge", "dive_mines":
					expected = "medal"
				"dive_enter", "dive_complete", "dive_one_run":
					expected = "fish"
				"dive_time":
					expected = "stopwatch"
		if kind != expected:
			return false
		var tier := str(mission.get("tier", ""))
		if int(mission.get("reward", 0)) != int(Missions.REWARDS.get(tier, -1)):
			return false
	return int(kinds.pipe) > 0 and int(kinds.fish) > 0 and int(kinds.stopwatch) > 0 and int(kinds.coin) > 0 and int(kinds.flag) > 0 and int(kinds.medal) > 0


func _test_countdown() -> bool:
	var left := Missions.remaining_seconds(100, 160, 1000, 1010)
	if left != 50:
		return false
	return Missions.format_countdown(3661) == "RESETS IN 01:01:01"


func _test_separation() -> bool:
	if Missions.should_report("daily", false) or Missions.should_report("daily", true):
		return false
	if Missions.should_report("unlimited", true) or not Missions.should_report("unlimited", false):
		return false
	var mission_sql := _strip_sql_comments(_read_project("res://tools/supabase/daily_missions.sql"))
	var game := _read_project("res://scenes/game/game.gd")
	var session := _read_project("res://autoload/game_session.gd")
	if mission_sql == "" or game == "" or session == "":
		return false
	for forbidden in ["daily_attempts", "daily_challenges", "leaderboard_scores", "ghost_runs", "finalize_daily_attempt", "submit_leaderboard_score", "claim_daily_attempt"]:
		if mission_sql.contains(forbidden):
			return false
	if game.count("remember_mission_run(") != 1 or not game.contains("if _mission_track:"):
		return false
	if not game.contains("_mission_track = (") or not game.contains("MODE_UNLIMITED"):
		return false
	var record := session.substr(session.find("func record_run"))
	var finalize_at := record.find("finalize_daily_attempt")
	var unlimited_at := record.find("submit_unlimited_score")
	if finalize_at < 0 or unlimited_at < 0 or finalize_at > unlimited_at:
		return false
	if not record.contains("if match_mode == MODE_DAILY:"):
		return false
	return record.find("return", finalize_at) < unlimited_at


func _test_widget_layout() -> bool:
	var Overlay = load("res://scripts/daily_missions_overlay.gd")
	if Overlay == null:
		return false
	var screens: Array[Vector2] = [
		Vector2(540, 960),
		Vector2(540, 1100),
		Vector2(540, 1170),
		Vector2(540, 1300),
		Vector2(480, 960),
	]
	var margins: Array[Vector4] = [
		Vector4(16, 12, 16, 12),
		Vector4(20, 59, 18, 34),
		Vector4(16, 47, 16, 28),
	]
	for screen in screens:
		for margin in margins:
			var rect: Rect2 = Overlay.widget_rect(screen, margin)
			if not Overlay.widget_clears_play(rect, screen):
				push_error("[missions] widget overlaps play %s %s %s" % [screen, margin, rect])
				return false
			if rect.position.y < margin.y - 0.1:
				return false
	var done: Vector2 = Overlay.claimed_progress({
		"easy": {"claimed": true, "complete": true, "progress": 10, "goal": 10},
		"medium": {"claimed": false, "complete": true, "progress": 20, "goal": 20},
		"hard": {"claimed": false, "complete": false, "progress": 5, "goal": 10},
	})
	if int(done.x) != 1 or not is_equal_approx(done.y, (1.0 + 1.0 + 0.5) / 3.0):
		push_error("[missions] widget counted an unclaimed mission %s" % done)
		return false
	var seen := {}
	if not Overlay.should_announce(seen, "2026-10-18", "easy", 5, "claimed"):
		return false
	seen["2026-10-18:easy"] = true
	if Overlay.should_announce(seen, "2026-10-18", "easy", 5, "claimed"):
		return false
	if Overlay.should_announce({}, "2026-10-18", "easy", 5, "already"):
		return false
	if Overlay.should_announce({}, "2026-10-18", "bonus", 0, "claimed"):
		return false
	if not Overlay.should_announce(seen, "2026-10-18", "bonus", 25, "claimed"):
		return false
	var overlay = Overlay.new()
	root.add_child(overlay)
	overlay.present("board", true)
	if overlay.mode() != "board":
		return false
	if overlay.shade_blocks_play() or overlay.shade_alpha() < 0.99 or overlay.board_brightness() < 0.99:
		push_error("[missions] board backdrop blocks taps or darkens the card")
		return false
	overlay.present("widget", true)
	if overlay.mode() != "widget":
		return false
	if _control_blocks_input(overlay):
		push_error("[missions] widget absorbs taps")
		return false
	overlay.announce_reward("easy", 5, "2026-10-18")
	overlay.announce_reward("easy", 5, "2026-10-18")
	if overlay.announced_count() != 1:
		return false
	overlay.present("aside")
	if overlay.mode() != "aside":
		return false
	overlay.set_dismissible(true)
	if overlay.dismiss_catches_taps():
		return false
	overlay.present("board", true)
	if not overlay.dismiss_catches_taps():
		push_error("[missions] menu board does not catch taps")
		return false
	var center := Vector2(overlay.get_viewport().get_visible_rect().size) * 0.5
	if not overlay.card_contains(center):
		push_error("[missions] menu board missed the center")
		return false
	overlay.present("hidden")
	if overlay.dismiss_catches_taps() or overlay.mode() != "hidden":
		return false
	overlay.queue_free()
	return true


func _test_lobby_clock() -> bool:
	var Overlay = load("res://scripts/daily_missions_overlay.gd")
	if Overlay == null or not is_equal_approx(float(Overlay.FOLD_SECS), 0.30):
		return false
	if not is_equal_approx(RR.lobby_length(true), 8.0) or not is_equal_approx(RR.lobby_length(false), 5.0):
		return false
	if RR.lobby_fold_due(2.999, true) or not RR.lobby_fold_due(3.0, true):
		return false
	if RR.lobby_fold_due(8.0, false):
		return false
	if RR.lobby_finished(7.999, 8.0) or not RR.lobby_finished(8.0, 8.0):
		return false
	if RR.lobby_finished(4.999, 5.0) or not RR.lobby_finished(5.0, 5.0):
		return false
	for step in [1.0 / 60.0, 1.0 / 120.0, 1.0 / 240.0, 0.5]:
		var clock := _walk_lobby(step, true, 8.0, 3.0)
		if not bool(clock.folded) or not bool(clock.started):
			push_error("[missions] lobby clock missed a mark step=%s %s" % [step, clock])
			return false
		if float(clock.fold_at) < 3.0 or float(clock.fold_at) >= 3.0 + step + 0.0001:
			push_error("[missions] fold drifted step=%s at=%s" % [step, clock.fold_at])
			return false
		if float(clock.start_at) < 8.0 or float(clock.start_at) >= 8.0 + step + 0.0001:
			push_error("[missions] start drifted step=%s at=%s" % [step, clock.start_at])
			return false
		if not _shade_clears(step):
			push_error("[missions] backdrop fade drifted at step=%s" % step)
			return false
	var daily := _walk_lobby(1.0 / 120.0, false, 5.0, 3.0)
	if bool(daily.folded) or float(daily.start_at) < 5.0 or float(daily.start_at) >= 5.0 + (1.0 / 120.0) + 0.0001:
		return false
	var while_loading := _walk_lobby(0.5, true, 4.0, 3.0)
	if not bool(while_loading.started) or not bool(while_loading.folded) or not bool(while_loading.loading):
		return false
	return true


func _shade_clears(step: float) -> bool:
	var Overlay = load("res://scripts/daily_missions_overlay.gd")
	var mid: float = Overlay.fold_shade_alpha(Overlay.FOLD_SECS * 0.5)
	if mid <= 0.05 or mid >= 0.95:
		return false
	var elapsed := 0.0
	var alpha := 1.0
	while elapsed < Overlay.FOLD_SECS - 0.00001:
		elapsed += step
		alpha = float(Overlay.fold_shade_alpha(elapsed))
	return alpha <= 0.001 and is_equal_approx(float(Overlay.fold_shade_alpha(Overlay.FOLD_SECS * 0.5)), mid)


func _test_shade_fold() -> bool:
	var Overlay = load("res://scripts/daily_missions_overlay.gd")
	var overlay = Overlay.new()
	root.add_child(overlay)
	overlay.present("board", true)
	if overlay.shade_blocks_play():
		overlay.queue_free()
		return false
	overlay.present("widget")
	var guard := 0
	while overlay.shade_alpha() > 0.02 and guard < 120:
		if overlay.shade_blocks_play():
			overlay.queue_free()
			return false
		await process_frame
		guard += 1
	var clear: bool = overlay.shade_alpha() <= 0.02 and not overlay.shade_blocks_play() and overlay.mode() == "widget"
	overlay.queue_free()
	return clear


func _walk_lobby(step: float, missions: bool, length: float, fold_at: float) -> Dictionary:
	var elapsed := 0.0
	var folded := false
	var started := false
	var folded_at := -1.0
	var started_at := -1.0
	var loading := true
	for _i in 20000:
		elapsed += step
		loading = elapsed < 6.0
		if not folded and missions and elapsed >= fold_at:
			folded = true
			folded_at = elapsed
		if elapsed >= length:
			started = true
			started_at = elapsed
			break
	return {
		"folded": folded,
		"started": started,
		"fold_at": folded_at,
		"start_at": started_at,
		"loading": loading,
	}


func _test_screen_board() -> bool:
	var Overlay = load("res://scripts/daily_missions_overlay.gd")
	if Overlay == null:
		return false
	var overlay = Overlay.new()
	overlay.use_screen_board()
	root.add_child(overlay)
	overlay.set_dismissible(true)
	overlay.present("board", true)
	var screen: Vector2 = overlay.get_viewport().get_visible_rect().size
	var placed: Rect2 = overlay.placed_screen_board()
	var fit: float = placed.size.x / float(Overlay.SCREEN_SIZE.x)
	var back_center: Vector2 = placed.position + (Overlay.SCREEN_BACK.position + Overlay.SCREEN_BACK.size * 0.5) * fit
	var ok: bool = overlay.board_fills_screen() and overlay.board_brightness() >= 0.99 and overlay.shade_alpha() <= 0.001 and not overlay.shade_blocks_play()
	var card := Rect2(placed.position + Vector2(Overlay.SCREEN_FOCUS.position.x, Overlay.SCREEN_FOCUS.position.y) * fit, Vector2(Overlay.SCREEN_CARD_RIGHT - Overlay.SCREEN_FOCUS.position.x, Overlay.SCREEN_FOCUS.size.y) * fit)
	var visible := Rect2(Vector2.ZERO, screen)
	ok = ok and visible.grow(1.0).encloses(card)
	ok = ok and visible.has_point(back_center)
	ok = ok and is_equal_approx(placed.size.x / placed.size.y, Overlay.SCREEN_SIZE.x / Overlay.SCREEN_SIZE.y)
	ok = ok and overlay.card_contains(visible.get_center()) and not overlay.card_contains(back_center)
	if not ok:
		push_error("[missions] screen board did not fill the display")
	overlay.queue_free()
	return ok


func _test_claim_marks() -> bool:
	var board := {
		"ok": true,
		"slots": [
			{"slot": "easy", "complete": true, "claimed": false, "goal": 1, "progress": 1, "reward": 5, "description": "Easy"},
			{"slot": "medium", "complete": true, "claimed": true, "goal": 1, "progress": 1, "reward": 10, "description": "Medium"},
			{"slot": "hard", "complete": false, "claimed": false, "goal": 1, "progress": 0, "reward": 20, "description": "Hard"},
		],
		"bonus": {"unlocked": true, "claimed": false, "reward": 25},
	}
	var Overlay = load("res://scripts/daily_missions_overlay.gd")
	var screen = Overlay.new()
	screen.use_screen_board()
	root.add_child(screen)
	screen.present("board", true)
	screen.show_board(board, "")
	var screen_modes: PackedStringArray = _reward_modes(screen)
	screen.queue_free()
	var lobby = Overlay.new()
	root.add_child(lobby)
	lobby.present("board", true)
	lobby.show_board(board, "")
	var lobby_modes: PackedStringArray = _reward_modes(lobby)
	lobby.queue_free()
	var expected_screen := PackedStringArray(["", "done", "", ""])
	var expected_lobby := PackedStringArray(["", "done", "", ""])
	if screen_modes != expected_screen or lobby_modes != expected_lobby:
		push_error("[missions] checkmark before claim screen=%s lobby=%s" % [screen_modes, lobby_modes])
		return false
	return true


func _test_board_chrome() -> bool:
	var Overlay = load("res://scripts/daily_missions_overlay.gd")
	var partial := {
		"ok": true,
		"slots": [
			{"slot": "easy", "complete": false, "claimed": false, "goal": 10, "progress": 0, "reward": 5, "description": "Easy"},
			{"slot": "medium", "complete": false, "claimed": false, "goal": 10, "progress": 5, "reward": 10, "description": "Medium"},
			{"slot": "hard", "complete": true, "claimed": true, "goal": 10, "progress": 10, "reward": 20, "description": "Hard"},
		],
		"bonus": {"unlocked": false, "claimed": false, "reward": 25},
	}
	var finished := {
		"ok": true,
		"slots": [
			{"slot": "easy", "complete": true, "claimed": true, "goal": 10, "progress": 10, "reward": 5, "description": "Easy"},
			{"slot": "medium", "complete": true, "claimed": true, "goal": 10, "progress": 10, "reward": 10, "description": "Medium"},
			{"slot": "hard", "complete": true, "claimed": true, "goal": 10, "progress": 10, "reward": 20, "description": "Hard"},
		],
		"bonus": {"unlocked": true, "claimed": true, "reward": 25},
	}
	if not _assert_chrome(Overlay, true, partial, PackedStringArray(["", "", "done", ""]), [0.0, 0.5, 1.0]):
		return false
	if not _assert_chrome(Overlay, true, finished, PackedStringArray(["done", "done", "done", "done"]), [1.0, 1.0, 1.0]):
		return false
	if not _screen_covers_phones(Overlay):
		return false
	if not _assert_chrome(Overlay, false, partial, PackedStringArray(["", "", "done", ""]), [0.0, 0.5, 1.0]):
		return false
	var ref: Rect2 = Overlay.screen_board_rect(Vector2(540, 960), Vector4(0, 0, 0, 0))
	if ref.position.x > 1.0 or ref.position.y > 1.0 or ref.end.x < 539.0 or ref.end.y < 958.0:
		push_error("[missions] reference board left a gap %s" % ref)
		return false
	if absf(ref.size.x / ref.size.y - Overlay.SCREEN_SIZE.x / Overlay.SCREEN_SIZE.y) > 0.01:
		push_error("[missions] reference board scale is not uniform")
		return false
	return true


func _screen_covers_phones(Overlay) -> bool:
	var phones := [
		{"screen": Vector2(540, 960), "margins": Vector4(0, 0, 0, 0)},
		{"screen": Vector2(540, 960), "margins": Vector4(0, 59, 0, 34)},
		{"screen": Vector2(390, 844), "margins": Vector4(0, 47, 0, 34)},
		{"screen": Vector2(393, 852), "margins": Vector4(0, 59, 0, 34)},
		{"screen": Vector2(360, 780), "margins": Vector4(0, 44, 0, 30)},
		{"screen": Vector2(540, 1169), "margins": Vector4(0, 65, 0, 47)},
		{"screen": Vector2(540, 1171), "margins": Vector4(0, 81, 0, 47)},
		{"screen": Vector2(540, 1170), "margins": Vector4(0, 66, 0, 45)},
	]
	for phone in phones:
		var screen: Vector2 = phone.screen
		var margins: Vector4 = phone.margins
		var cover: Rect2 = Overlay.screen_cover_rect(screen)
		var board: Rect2 = Overlay.screen_board_rect(screen, margins)
		if cover.position != Vector2.ZERO or cover.size != screen:
			push_error("[missions] fill left the viewport %s" % cover)
			return false
		if absf(board.size.x / board.size.y - Overlay.SCREEN_SIZE.x / Overlay.SCREEN_SIZE.y) > 0.01:
			push_error("[missions] board aspect changed %s" % board)
			return false
		var scale: float = board.size.x / Overlay.SCREEN_SIZE.x
		var card := Rect2(board.position + Vector2(Overlay.SCREEN_FOCUS.position.x, Overlay.SCREEN_FOCUS.position.y) * scale, Vector2(Overlay.SCREEN_CARD_RIGHT - Overlay.SCREEN_FOCUS.position.x, Overlay.SCREEN_FOCUS.size.y) * scale)
		if board.position.y > 1.0:
			push_error("[missions] artwork starts below the top %s" % board)
			return false
		if board.position.x > 1.0 or board.end.x < screen.x - 1.0:
			push_error("[missions] artwork left a side gap %s" % board)
			return false
		if not Rect2(Vector2.ZERO, screen).grow(1.0).encloses(card):
			push_error("[missions] mission board left the screen %s" % card)
			return false
		if board.size.x > screen.x + 8.0 and absf(card.end.x - screen.x) > 1.5:
			push_error("[missions] blue card did not meet the screen edge %s" % card)
			return false
		var back := Rect2(board.position + Overlay.SCREEN_BACK.position * scale, Overlay.SCREEN_BACK.size * scale)
		if not Rect2(Vector2.ZERO, screen).grow(1.0).encloses(back):
			push_error("[missions] back button left the screen %s" % back)
			return false
		if not card.grow(8.0).encloses(back):
			push_error("[missions] back button left the board %s" % back)
			return false
		var safe := Rect2(Vector2(margins.x, margins.y), Vector2(screen.x - margins.x - margins.z, screen.y - margins.y - margins.w))
		if safe.size.y + 1.0 >= card.size.y and safe.size.x + 1.0 >= card.size.x and not safe.grow(2.0).encloses(card):
			push_error("[missions] mission board entered the unsafe area %s safe %s" % [card, safe])
			return false
		var art_aspect: float = Overlay.SCREEN_SIZE.x / Overlay.SCREEN_SIZE.y
		if absf(screen.x / screen.y - art_aspect) < 0.01:
			if board.position.x > 1.0 or board.position.y > 1.0 or board.end.x < screen.x - 1.0 or board.end.y < screen.y - 1.0:
				push_error("[missions] artwork left a gap on the reference viewport %s" % board)
				return false
	return true


func _assert_chrome(Overlay, screen_board: bool, board: Dictionary, modes: PackedStringArray, expected: Array) -> bool:
	var overlay = Overlay.new()
	if screen_board:
		overlay.use_screen_board()
	root.add_child(overlay)
	overlay.present("board", true)
	overlay.set("_applied", false)
	overlay.show_board(board, "")
	var fills: Array = overlay.get("_fills")
	var tracks: Array = overlay.get("_track")
	var rewards: Array = overlay.get("_reward")
	var backs: Array = overlay.get("_reward_backs")
	var covers: Array = overlay.get("_coin_covers")
	var marks: Array = overlay.get("_marks")
	var texts: Array = overlay.get("_reward_text")
	var ok := fills.size() == 3 and marks.size() == 3
	for i in fills.size():
		var fill: Control = fills[i]
		var track: Control = fill.get_parent()
		var groove: Rect2 = tracks[i]
		var reward: Rect2 = rewards[i]
		var back: Control = backs[i]
		var mark: Control = marks[i]
		if not track.clip_contents:
			ok = false
		var pad := 2.0
		if fill.position.distance_to(Vector2(pad, pad)) > 0.01:
			ok = false
		var inner := Vector2(maxf(0.0, groove.size.x - pad * 2.0), maxf(0.0, groove.size.y - pad * 2.0))
		if absf(fill.size.y - inner.y) > 0.01:
			ok = false
		if absf(fill.size.x - inner.x * expected[i]) > 0.01:
			ok = false
		if fill.position.x < -0.01 or fill.position.y < -0.01:
			ok = false
		if fill.position.x + fill.size.x > track.size.x + 0.01 or fill.position.y + fill.size.y > track.size.y + 0.01:
			ok = false
		if expected[i] <= 0.001 and fill.visible:
			ok = false
		if expected[i] > 0.001 and not fill.visible:
			ok = false
		if not is_equal_approx(track.size.x, groove.size.x) or not is_equal_approx(track.size.y, groove.size.y):
			ok = false
		var reward_box := Rect2(reward.position, reward.size)
		var mark_box := Rect2(mark.position, mark.size)
		var descs: Array = overlay.get("_desc")
		var desc_box: Rect2 = descs[i]
		var track_box: Rect2 = tracks[i]
		if mark.clip_contents or mark.z_index < 2:
			ok = false
		var rewarded := modes[i] == "done"
		if texts[i].visible == rewarded:
			ok = false
		if covers[i].visible or back.visible:
			ok = false
		var coins: Array = overlay.get("_coin_icons")
		var coin_icon: Control = coins[i]
		if coin_icon.size.x > 1.0 and coin_icon.visible == rewarded:
			ok = false
		if rewarded and mark_box.intersects(desc_box):
			ok = false
		if rewarded and mark_box.intersects(track_box):
			ok = false
		if rewarded and screen_board:
			var coin_rect: Rect2 = Overlay.SCREEN_COIN_ICON[i]
			var cluster_center := Vector2((coin_rect.position.x + reward_box.end.x) * 0.5, coin_rect.position.y + coin_rect.size.y * 0.5)
			var mark_center := mark_box.position + mark_box.size * 0.5
			if mark_center.distance_to(cluster_center) > 4.0:
				ok = false
		if rewarded and not screen_board:
			var mark_center := mark_box.position + mark_box.size * 0.5
			var number_center := reward_box.position + reward_box.size * 0.5
			if mark_center.x > number_center.x:
				ok = false
			if mark_center.distance_to(number_center) > 70.0:
				ok = false
	for i in marks.size():
		for j in range(i + 1, marks.size()):
			var a := Rect2((marks[i] as Control).position, (marks[i] as Control).size)
			var b := Rect2((marks[j] as Control).position, (marks[j] as Control).size)
			if a.intersects(b):
				ok = false
	var seen := _reward_modes(overlay)
	if seen != modes:
		ok = false
	var status: Array = overlay.get("_status")
	var rows: Array = board.get("slots", [])
	var circles: Array = Overlay.SCREEN_STATUS if screen_board else Overlay.STATUS
	if status.size() != 3 or rows.size() < 3:
		ok = false
	else:
		for i in status.size():
			var row: Dictionary = rows[i]
			var want := "done" if bool(row.get("complete", false)) or bool(row.get("claimed", false)) else ""
			if str(status[i].get("_mode")) != want:
				ok = false
			var circle: Rect2 = circles[i]
			var mark_center := (status[i] as Control).position + (status[i] as Control).size * 0.5
			var circle_center := circle.position + circle.size * 0.5
			if mark_center.distance_to(circle_center) > 1.0:
				ok = false
	if not ok:
		push_error("[missions] chrome screen=%s modes=%s" % [screen_board, seen])
	overlay.queue_free()
	return ok


func _reward_modes(overlay) -> PackedStringArray:
	var modes := PackedStringArray()
	var marks: Array = overlay.get("_marks")
	for mark in marks:
		modes.append(str(mark.get("_mode")))
	var bonus: Node = overlay.get("_bonus_mark")
	modes.append("" if bonus == null else str(bonus.get("_mode")))
	return modes


func _control_blocks_input(node: Node) -> bool:
	if node is BaseButton:
		return true
	if node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return true
	for child in node.get_children():
		if _control_blocks_input(child):
			return true
	return false


func _strip_sql_comments(text: String) -> String:
	var kept: PackedStringArray = PackedStringArray()
	for line in text.split("\n"):
		if line.strip_edges().begins_with("--"):
			continue
		kept.append(line)
	return "\n".join(kept)


func _read_project(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _test_mission_icons() -> bool:
	var expected := {
		1: "pipes",
		3: "high_score",
		4: "complete_runs",
		6: "high_score",
		7: "survive_x_seconds",
		8: "collect_x_coins",
		10: "collect_coins",
		11: "pipes",
		30: "pipes",
		46: "enter_deep_dive",
		47: "change_lanes",
		48: "time_in_deep_dive",
		49: "move_left",
		51: "dodge_obstacles",
		52: "move_right",
		55: "complete_deep_dives",
		66: "mine",
		78: "survive_without_hitting",
		89: "dodge_obstacles",
		90: "enter_deep_dive",
	}
	var used := {}
	for mission in Missions.catalog():
		var mission_id := int(mission.get("id", 0))
		var file := Missions.icon_file(mission_id)
		if file == "" or file == "mystery_mission":
			push_error("[missions] mission %d has no icon" % mission_id)
			return false
		if expected.has(mission_id) and str(expected[mission_id]) != file:
			push_error("[missions] mission %d icon %s" % [mission_id, file])
			return false
		var path := "res://assets/ui/mission_icons/%s.png" % file
		if not ResourceLoader.exists(path):
			push_error("[missions] missing %s" % path)
			return false
		var texture: Texture2D = load(path) as Texture2D
		if texture == null or texture.get_width() < 8 or texture.get_height() < 8:
			push_error("[missions] broken texture %s" % path)
			return false
		var image := texture.get_image()
		if image == null or image.is_empty():
			push_error("[missions] empty image %s" % path)
			return false
		if image.get_pixel(0, 0).a > 0.05 and image.get_pixel(image.get_width() - 1, image.get_height() - 1).a > 0.05:
			push_error("[missions] %s still has a solid background" % file)
			return false
		used[file] = true
	if Missions.icon_file(999) != "mystery_mission":
		return false
	if used.size() < 15:
		return false
	var Overlay = load("res://scripts/daily_missions_overlay.gd")
	var iphone: Rect2 = Overlay.screen_board_rect(Vector2(390, 844), Vector4(0, 47, 0, 34))
	var fit: float = iphone.size.x / float(Overlay.SCREEN_SIZE.x)
	var icon_size: Vector2 = Overlay.SCREEN_ICONS[0].size
	for i in Overlay.SCREEN_ICONS.size():
		var icon: Rect2 = Overlay.SCREEN_ICONS[i]
		if icon.size != icon_size or icon.size.x < 64.0:
			return false
		if icon.intersects(Overlay.SCREEN_DESC[i]) or icon.intersects(Overlay.SCREEN_TRACK[i]):
			return false
		if icon.intersects(Overlay.SCREEN_REWARD[i]) or icon.intersects(Overlay.SCREEN_CHECK[i]):
			return false
		if icon.intersects(Overlay.SCREEN_COUNT[i]) or icon.end.x > Overlay.SCREEN_DESC[i].position.x:
			return false
		var placed := Rect2(iphone.position + icon.position * fit, icon.size * fit)
		if not iphone.encloses(placed):
			push_error("[missions] icon leaves the iPhone board %s" % placed)
			return false
	var board := {
		"ok": true,
		"slots": [
			{"slot": "easy", "mission_id": 46, "complete": true, "claimed": true, "goal": 1, "progress": 1, "reward": 5, "description": "Deep Diver: enter a dive."},
			{"slot": "medium", "mission_id": 66, "complete": false, "claimed": false, "goal": 5, "progress": 2, "reward": 10, "description": "Mine Dodger: pass 5 mines."},
			{"slot": "hard", "mission_id": 1, "complete": false, "claimed": false, "goal": 10, "progress": 0, "reward": 20, "description": "Pass 10 pipes total."},
		],
		"bonus": {"unlocked": false, "claimed": false, "reward": 25},
	}
	var overlay = Overlay.new()
	overlay.use_screen_board()
	root.add_child(overlay)
	overlay.present("board", true)
	overlay.show_board(board, "")
	var holders: Array = overlay.get("_icon_holders")
	var marks: Array = overlay.get("_marks")
	var ok := holders.size() == 3 and marks.size() == 3
	var files := ["enter_deep_dive", "mine", "pipes"]
	for i in holders.size():
		var holder: Control = holders[i]
		if holder.get_child_count() != 1:
			ok = false
			continue
		var icon: Control = holder.get_child(0)
		if icon.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
			ok = false
		var shown := icon.get("texture") as Texture2D
		if shown == null or shown.resource_path != "res://assets/ui/mission_icons/%s.png" % files[i]:
			ok = false
		if holder.position.x + holder.size.x > Overlay.SCREEN_DESC[i].position.x:
			ok = false
	if str(marks[0].get("_mode")) != "done":
		ok = false
	overlay.queue_free()
	if not ok:
		push_error("[missions] mission icons did not land on the cards")
	return ok


func _check(ok: bool, label: String) -> bool:
	if not ok:
		print("[missions] FAIL %s" % label)
	return ok
