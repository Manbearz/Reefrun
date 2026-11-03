extends SceneTree

const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")
const DailyAttemptScript := preload("res://scripts/daily_attempt.gd")
const DailyMissionsScript := preload("res://scripts/daily_missions.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _initialize() -> void:
	ProjectSettings.set_setting("network/http_proxy/host", "127.0.0.1")
	ProjectSettings.set_setting("network/http_proxy/port", 9)


func _run() -> void:
	var save_path := "user://reefrun.cfg"
	var had_save := FileAccess.file_exists(save_path)
	var saved_bytes := FileAccess.get_file_as_bytes(save_path) if had_save else PackedByteArray()
	_check("phone_forward_one_day", _forward(86400))
	_check("phone_forward_one_week", _forward(7 * 86400))
	_check("phone_backward_one_day", _backward())
	_check("phone_timezone", _timezone())
	_check("missions_survive_clock", _missions_survive_clock())
	_check("rewards_survive_clock", _rewards_survive_clock())
	_check("attempt_survives_clock", _attempt_survives_clock())
	_check("restart_keeps_period", _restart_keeps_period())
	_check("same_identity_reinstall", _same_identity())
	_check("offline_clock", _offline_clock())
	_check("reconnect_keeps_then_rolls", _reconnect())
	_check("server_boundary", _server_boundary())
	_check("simultaneous_attempts", _simultaneous_attempts())
	_check("duplicate_rewards", _duplicate_rewards())
	_check("score_stays_on_attempt", _score_stays_on_attempt())
	_check("countdown_ignores_wall_clock", _countdown_ignores_wall())
	_check("ui_does_not_read_phone_clock", _ui_sources())
	if had_save:
		var out := FileAccess.open(save_path, FileAccess.WRITE)
		if out:
			out.store_buffer(saved_bytes)
			out.close()
	elif FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("[clock] failed=%d" % _failed)
	quit(1 if _failed else 0)


func _check(name: String, ok: bool) -> void:
	if not ok:
		_failed += 1
		push_error("[clock] %s failed" % name)
	print("[clock] %s=%s" % [name, str(ok)])


func _anchor(as_of: int, elapsed_sec: int) -> int:
	var ticks := 1_000_000
	return DailyChallengeScript.monotonic_server_unix(as_of, ticks, ticks + elapsed_sec * 1000)


func _forward(seconds: int) -> bool:
	var as_of := DailyChallengeScript.unix_utc(2026, 10, 20, 18, 0, 0)
	var held := _anchor(as_of, 0)
	var date := DailyChallengeScript.challenge_date_from_unix(held)
	var cached := DailyChallengeScript.make(date, true, as_of)
	var chosen := DailyChallengeScript.choose_for_new_match(cached, as_of, as_of, held)
	var backend := get_root().get_node_or_null("Backend")
	if backend == null:
		return false
	backend._server_as_of = as_of
	backend._clock_ticks = Time.get_ticks_msec()
	var estimated := int(backend.estimated_server_unix())
	var phone := int(Time.get_unix_time_from_system()) + seconds
	return (
		held == as_of
		and date == "2026-10-20"
		and DailyChallengeScript.may_submit(chosen)
		and str(chosen.get("challenge_date", "")) == date
		and absi(estimated - as_of) < 2
		and absi(phone - estimated) > seconds - 5
	)


func _backward() -> bool:
	var as_of := DailyChallengeScript.unix_utc(2026, 10, 20, 18, 0, 0)
	var ticks := 5_000_000
	var estimated := DailyChallengeScript.monotonic_server_unix(as_of, ticks, ticks - 86400 * 1000)
	var board := _mission_board("2026-10-20", as_of, as_of + 6 * 3600, true, true)
	board["fetched_ticks"] = ticks
	var left := DailyMissionsScript.anchored_remaining(board, ticks - 86400 * 1000)
	return estimated == as_of and left == 6 * 3600


func _timezone() -> bool:
	var instant := DailyChallengeScript.unix_utc(2026, 10, 13, 3, 30, 0)
	var backend := get_root().get_node_or_null("Backend")
	var session := get_root().get_node_or_null("GameSession")
	if backend == null or session == null:
		return false
	backend._server_as_of = instant
	backend._clock_ticks = Time.get_ticks_msec()
	var day := str(session.current_day_key())
	var week := str(session.current_week_key())
	var month := str(session.current_month_key())
	var utc := DailyChallengeScript.utc_date_from_unix(instant)
	return (
		day == "2026-10-12"
		and day != utc
		and week == DailyChallengeScript.week_key(utc)
		and month == utc.substr(0, 7)
	)


func _missions_survive_clock() -> bool:
	var as_of := DailyChallengeScript.unix_utc(2026, 10, 20, 18, 0, 0)
	var reset := DailyChallengeScript.eastern_midnight_unix(2026, 10, 21)
	var current := _mission_board("2026-10-20", as_of, reset, true, true)
	var incoming := _mission_board("2026-10-27", as_of + 7 * 86400, reset + 7 * 86400, false, false)
	incoming["server_now"] = reset - 60
	var kept := DailyMissionsScript.settle_board(current, incoming)
	var easy: Dictionary = _slot(kept, "easy")
	return (
		str(kept.get("mission_date", "")) == "2026-10-20"
		and int(easy.get("mission_id", 0)) == 1
		and bool(easy.get("complete", false))
		and bool(easy.get("claimed", false))
		and int(kept.get("server_now", 0)) == reset - 60
	)


func _rewards_survive_clock() -> bool:
	var session := get_root().get_node_or_null("GameSession")
	if session == null:
		return false
	session.coins = 0
	session.applied_mission_reward_coins = 0
	session.mission_board = {}
	var as_of := DailyChallengeScript.unix_utc(2026, 10, 20, 18, 0, 0)
	var board := _mission_board("2026-10-20", as_of, as_of + 3600, true, true)
	board["mission_reward_coins"] = 60
	var first := int(session.apply_mission_board(board))
	board["fetched_at"] = int(Time.get_unix_time_from_system()) + 7 * 86400
	var second := int(session.apply_mission_board(board))
	var easy: Dictionary = _slot(session.mission_board, "easy")
	return first == 60 and second == 0 and int(session.coins) == 60 and bool(easy.get("claimed", false))


func _attempt_survives_clock() -> bool:
	var as_of := DailyChallengeScript.unix_utc(2026, 10, 20, 18, 0, 0)
	var challenge := DailyChallengeScript.make("2026-10-20", true, as_of)
	var store := DailyAttemptScript.empty_store()
	var first: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-1", challenge, "2026-10-27")
	DailyAttemptScript.start(store, "player-a", str(first.get("attempt_id", "")))
	var again: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-2", challenge, "2026-10-21")
	var chosen := DailyChallengeScript.choose_for_new_match(challenge, as_of, as_of, _anchor(as_of, 0))
	return (
		bool(first.get("claimed", false))
		and bool(again.get("already_used", false))
		and int(again.get("attempt_count", 0)) == 1
		and DailyChallengeScript.may_submit(chosen)
		and str(chosen.get("challenge_date", "")) == "2026-10-20"
	)


func _restart_keeps_period() -> bool:
	var as_of := DailyChallengeScript.unix_utc(2026, 10, 20, 18, 0, 0)
	var reset := as_of + 6 * 3600
	var board := _mission_board("2026-10-20", as_of, reset, true, true)
	board["fetched_ticks"] = Time.get_ticks_msec() + 86_400_000
	var left := DailyMissionsScript.anchored_remaining(board)
	var session := get_root().get_node_or_null("GameSession")
	if session == null:
		return false
	session.pending_finalizes = [{"attempt_id": "attempt-0", "score": 9, "name": "REEF"}]
	session.day_key = "2026-10-20"
	session.daily = [{"name": "REEF", "score": 9}]
	var backend := get_root().get_node("Backend")
	backend._server_as_of = 0
	backend._clock_ticks = 0
	var rolled := bool(session.refresh_boards())
	return left == 6 * 3600 and not rolled and session.pending_finalizes.size() == 1 and session.daily.size() == 1


func _same_identity() -> bool:
	var challenge := DailyChallengeScript.make("2026-10-20", true)
	var store := DailyAttemptScript.empty_store()
	var book := {"rows": []}
	var first: Dictionary = DailyAttemptScript.claim(store, "same-player", "key-1", challenge, "")
	DailyAttemptScript.start(store, "same-player", str(first.get("attempt_id", "")))
	DailyAttemptScript.finalize(store, book, "same-player", str(first.get("attempt_id", "")), 8, "REEF", 1)
	var replay: Dictionary = DailyAttemptScript.claim(store, "same-player", "fresh-install-key", challenge, "2026-11-03")
	var other: Dictionary = DailyAttemptScript.claim(store, "other-player", "key-9", challenge, "")
	return (
		bool(first.get("claimed", false))
		and bool(replay.get("already_used", false))
		and not bool(replay.get("claimed", false))
		and int(replay.get("attempt_count", 0)) == 1
		and bool(other.get("claimed", false))
	)


func _offline_clock() -> bool:
	var session := get_root().get_node_or_null("GameSession")
	var backend := get_root().get_node_or_null("Backend")
	if session == null or backend == null:
		return false
	backend._server_as_of = 0
	backend._clock_ticks = 0
	session.day_key = "2026-10-20"
	session.week_key = "2026-10-19"
	session.month_key = "2026-10"
	session.daily = [{"name": "REEF", "score": 4}]
	session.mission_board = _mission_board("2026-10-20", 1_000, 1_000 + 3600, true, true)
	session.mission_board["fetched_ticks"] = Time.get_ticks_msec()
	var changed := bool(session.refresh_boards())
	var left := DailyMissionsScript.anchored_remaining(session.mission_board)
	var fresh: Dictionary = backend.challenge_for_new_match()
	return (
		not changed
		and session.daily.size() == 1
		and session.current_day_key() == "2026-10-20"
		and left == 3600
		and fresh.is_empty()
	)


func _reconnect() -> bool:
	var as_of := DailyChallengeScript.unix_utc(2026, 10, 20, 18, 0, 0)
	var reset := DailyChallengeScript.eastern_midnight_unix(2026, 10, 21)
	var current := _mission_board("2026-10-20", as_of, reset, true, true)
	var early := _mission_board("2026-10-21", reset - 30, reset + 86400, false, false)
	var held := DailyMissionsScript.settle_board(current, early)
	var opened := _mission_board("2026-10-21", reset, reset + 86400, false, false)
	var rolled := DailyMissionsScript.settle_board(held, opened)
	return str(held.get("mission_date", "")) == "2026-10-20" and str(rolled.get("mission_date", "")) == "2026-10-21"


func _server_boundary() -> bool:
	var as_of := DailyChallengeScript.unix_utc(2026, 10, 13, 3, 50, 0)
	var cached := DailyChallengeScript.make("2026-10-12", true, as_of)
	var before := DailyChallengeScript.choose_for_new_match(cached, as_of, as_of, as_of)
	var after_unix := _anchor(as_of, 20 * 60)
	var after := DailyChallengeScript.choose_for_new_match(cached, as_of, as_of, after_unix)
	return (
		DailyChallengeScript.may_submit(before)
		and str(before.get("challenge_date", "")) == "2026-10-12"
		and not DailyChallengeScript.may_submit(after)
		and str(after.get("challenge_date", "")) == "2026-10-13"
	)


func _simultaneous_attempts() -> bool:
	var challenge := DailyChallengeScript.make("2026-10-20", true)
	var store := DailyAttemptScript.empty_store()
	var first: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-a", challenge, "2026-11-03")
	var second: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-b", challenge, "2026-11-04")
	var started: Dictionary = DailyAttemptScript.start(store, "player-a", str(first.get("attempt_id", "")))
	var repeat: Dictionary = DailyAttemptScript.start(store, "player-a", str(first.get("attempt_id", "")))
	return (
		bool(first.get("claimed", false))
		and bool(second.get("already_used", false))
		and int(second.get("attempt_count", 0)) == 1
		and bool(started.get("started", false))
		and bool(repeat.get("already_started", false))
	)


func _duplicate_rewards() -> bool:
	var claimed := {"easy": true, "medium": true, "hard": true, "bonus": true}
	var again := DailyMissionsScript.claim_payout(claimed, "easy", true, true)
	var bonus := DailyMissionsScript.claim_payout(claimed, "bonus", true, true)
	var first := DailyMissionsScript.claim_payout({}, "easy", true, false)
	return again == 0 and bonus == 0 and first == 5 and DailyMissionsScript.reward_delta(60, 60) == 0


func _score_stays_on_attempt() -> bool:
	var day := "2026-10-20"
	var during := DailyChallengeScript.eastern_midnight_unix(2026, 10, 20) + 3600
	var after := DailyChallengeScript.eastern_midnight_unix(2026, 10, 21) + 3600
	var challenge := DailyChallengeScript.make(day, true, during)
	var store := DailyAttemptScript.empty_store()
	var book := {"rows": []}
	var claim: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-1", challenge, day)
	DailyAttemptScript.start(store, "player-a", str(claim.get("attempt_id", "")))
	var saved: Dictionary = DailyAttemptScript.finalize(store, book, "player-a", str(claim.get("attempt_id", "")), 15, "REEF", after)
	var original: Array = DailyChallengeScript.visible_board(book, "daily", during)
	var later: Array = DailyChallengeScript.visible_board(book, "daily", after)
	var replay: Dictionary = DailyAttemptScript.finalize(store, book, "player-a", str(claim.get("attempt_id", "")), 40, "REEF", after)
	var after_replay: Array = DailyChallengeScript.visible_board(book, "daily", during)
	return (
		bool(saved.get("accepted", false))
		and original.size() == 1
		and int(original[0].get("score", 0)) == 15
		and later.is_empty()
		and bool(replay.get("duplicate", false))
		and after_replay.size() == 1
		and int(after_replay[0].get("score", 0)) == 15
	)


func _countdown_ignores_wall() -> bool:
	var now := int(Time.get_unix_time_from_system())
	var board := {
		"server_now": 1_700_000_000,
		"resets_at": 1_700_003_661,
		"fetched_at": now - 7 * 86400,
		"fetched_ticks": 80_000,
	}
	var left := DailyMissionsScript.anchored_remaining(board, 80_000)
	var text := DailyMissionsScript.format_countdown(left)
	board["fetched_ticks"] = 80_000
	var ended := DailyMissionsScript.anchored_remaining(board, 80_000 + 3661 * 1000)
	return left == 3661 and text == "RESETS IN 01:01:01" and ended == 0 and DailyMissionsScript.WAITING_LABEL == "CONNECTING"


func _ui_sources() -> bool:
	var overlay := FileAccess.get_file_as_string("res://scripts/daily_missions_overlay.gd")
	var panel := FileAccess.get_file_as_string("res://scripts/daily_missions_panel.gd")
	var menu := FileAccess.get_file_as_string("res://scenes/menu/main_menu.gd")
	var session := FileAccess.get_file_as_string("res://autoload/game_session.gd")
	return (
		not overlay.contains("get_unix_time_from_system")
		and not panel.contains("get_unix_time_from_system")
		and not menu.contains("get_unix_time_from_system")
		and not menu.contains("get_datetime_dict_from_system")
		and not session.contains("get_datetime_dict_from_system")
	)


func _mission_board(date: String, server_now: int, resets_at: int, complete: bool, claimed: bool) -> Dictionary:
	var progress := 10 if complete else 0
	return {
		"ok": true,
		"mission_date": date,
		"server_now": server_now,
		"resets_at": resets_at,
		"mission_reward_coins": 60 if claimed else 0,
		"slots": [
			{"slot": "easy", "mission_id": 1, "goal": 10, "progress": progress, "complete": complete, "claimed": claimed, "reward": 5},
			{"slot": "medium", "mission_id": 16, "goal": 60, "progress": 60 if complete else 0, "complete": complete, "claimed": claimed, "reward": 10},
			{"slot": "hard", "mission_id": 31, "goal": 120, "progress": 120 if complete else 0, "complete": complete, "claimed": claimed, "reward": 20},
		],
		"bonus": {"reward": 25, "unlocked": complete, "claimed": claimed, "progress": 3 if complete else 0},
	}


func _slot(board: Dictionary, name: String) -> Dictionary:
	for row in board.get("slots", []):
		if typeof(row) == TYPE_DICTIONARY and str(row.get("slot", "")) == name:
			return row
	return {}
