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
	print("[missions] ok=%s" % ok)
	quit(0 if ok else 1)


func _test_catalog() -> bool:
	var rows: Array = Missions.catalog()
	if rows.size() != 45:
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
	return enabled == 39


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
	return int(sparse.progress) == 60


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
				"multi_threshold", "window_sum":
					expected = "medal"
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
	var back_center: Vector2 = (Overlay.SCREEN_BACK.position + Overlay.SCREEN_BACK.size * 0.5) * Vector2(screen.x / Overlay.SCREEN_SIZE.x, screen.y / Overlay.SCREEN_SIZE.y)
	var ok: bool = overlay.board_fills_screen() and overlay.board_brightness() >= 0.99 and overlay.shade_alpha() <= 0.001 and not overlay.shade_blocks_play()
	ok = ok and overlay.card_contains(screen * 0.5) and not overlay.card_contains(back_center)
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
	var expected := PackedStringArray(["pending", "done", "", "pending"])
	if screen_modes != expected or lobby_modes != expected:
		push_error("[missions] checkmark before claim screen=%s lobby=%s" % [screen_modes, lobby_modes])
		return false
	return true


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


func _check(ok: bool, label: String) -> bool:
	if not ok:
		print("[missions] FAIL %s" % label)
	return ok
