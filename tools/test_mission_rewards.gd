extends SceneTree

# Local mock of Daily Missions, coin rewards, and the Eastern/UTC date contract.
# Never opens a live Supabase socket and never awards production coins.
# Godot --headless --path . --script res://tools/test_mission_rewards.gd

const Missions := preload("res://scripts/daily_missions.gd")
const Daily := preload("res://scripts/daily_challenge.gd")
const Repo := preload("res://scripts/backend/daily_mission_repository.gd")
const ClientScript := preload("res://scripts/backend/supabase_client.gd")
const RR := preload("res://scripts/rr.gd")

const PLAYER_A := "11111111-1111-4111-8111-111111111111"
const PLAYER_B := "22222222-2222-4222-8222-222222222222"
const TOKEN_A := "test-token-player-a"
const TOKEN_B := "test-token-player-b"

var mock: MissionMock
var _passed := 0
var _failed := 0
var _warnings: PackedStringArray = PackedStringArray()
var _reward_signals: Array = []


func _initialize() -> void:
	ProjectSettings.set_setting("network/http_proxy/host", "127.0.0.1")
	ProjectSettings.set_setting("network/http_proxy/port", 9)
	var session := ConfigFile.new()
	session.set_value("session", "access_token", TOKEN_A)
	session.set_value("session", "refresh_token", "")
	session.set_value("session", "user_id", PLAYER_A)
	session.set_value("session", "expires_at", int(Time.get_unix_time_from_system()) + 86400)
	session.save("user://supabase_session.cfg")
	if FileAccess.file_exists("user://reefrun.cfg"):
		var cfg := ConfigFile.new()
		if cfg.load("user://reefrun.cfg") == OK:
			cfg.set_value("pending", "attempt_id", "")
			cfg.set_value("pending", "score", 0)
			cfg.set_value("pending", "name", "")
			cfg.set_value("pending", "unlimited_score", 0)
			cfg.set_value("pending", "unlimited_name", "")
			cfg.set_value("pending", "claim_key", "")
			cfg.save("user://reefrun.cfg")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var version := Engine.get_version_info()
	var version_text := "%s.%s.%s" % [version.major, version.minor, version.patch]
	print("[mission-test] godot=%s status=%s" % [version_text, str(version.get("status", ""))])
	var backend := root.get_node_or_null("Backend")
	if backend == null:
		print("[mission-test] FAIL backend_missing")
		quit(1)
		return
	mock = MissionMock.new(backend)
	if backend.has_method("cancel_pre_match_requests"):
		backend.call("cancel_pre_match_requests")
	_drop_live_http(backend)
	backend._client = mock
	for _i in 8:
		await process_frame
	_drop_live_http(backend)
	if not await _wait_quiet(backend, 1500):
		_warn("Bootstrap left followup=%s share=%s mission=%s. Live HTTP was cancelled. This is the harness, not a mission failure." % [backend._followup_busy, backend._share_reward_busy, backend._mission_busy])
		_force_idle(backend)
	if not backend.mission_reward_granted.is_connected(_on_reward):
		backend.mission_reward_granted.connect(_on_reward)
	_install(backend, TOKEN_A, PLAYER_A)
	_check("godot_version", version_text == "4.7.2", version_text)
	_check("configured_rewards", _rewards_match(), "%s" % Missions.REWARDS)
	await _test_generation(backend)
	await _test_progress(backend)
	await _test_claims(backend)
	await _test_bonus_orders(backend)
	await _test_reset(backend)
	await _test_network(backend)
	await _test_rpc_compatibility(backend)
	await _test_cross_client(backend)
	await _test_coins(backend)
	await _test_ui(backend)
	_test_contract()
	print("[mission-test] scenarios=%d passed=%d failed=%d warnings=%d" % [_passed + _failed, _passed, _failed, _warnings.size()])
	for warning in _warnings:
		print("[mission-test] WARN %s" % warning)
	print("[mission-test] ok=%s" % (_failed == 0))
	quit(0 if _failed == 0 else 1)


func _on_reward(slot: String, coins: int, mission_date: String) -> void:
	_reward_signals.append({"slot": slot, "coins": coins, "date": mission_date})


func _check(name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[mission-test] %s=pass" % name)
	else:
		_failed += 1
		print("[mission-test] %s=FAIL %s" % [name, detail])


func _warn(text: String) -> void:
	_warnings.append(text)


func _gs():
	return root.get_node("GameSession")


func _install(backend, token: String, uid: String) -> void:
	mock.tokens[token] = uid
	backend.auth.access_token = token
	backend.auth.refresh_token = ""
	backend.auth.user_id = uid
	backend.auth.expires_at = int(Time.get_unix_time_from_system()) + 7200


func _force_idle(backend) -> void:
	backend._followup_busy = false
	backend._mission_busy = false
	backend._mission_flush_again = false
	backend._mission_auto_claim = false
	backend._share_reward_busy = false
	backend._lb_busy = false
	backend._lb_needs_refresh = false
	backend._finalize_running = false
	backend._daily_busy = false
	backend._busy = false
	backend._refresh_busy = false


func _drop_live_http(backend: Node) -> void:
	var pending: Array = []
	for child in backend.get_children():
		if child is HTTPRequest:
			pending.append(child)
	for child in pending:
		var http := child as HTTPRequest
		http.cancel_request()
		http.queue_free()


func _wait_quiet(backend, limit_ms: int = 8000) -> bool:
	var started := Time.get_ticks_msec()
	var calm := 0
	while Time.get_ticks_msec() - started < limit_ms:
		var quiet: bool = (
			not bool(backend._mission_busy)
			and not bool(backend._mission_flush_again)
			and not bool(backend._followup_busy)
			and not bool(backend._share_reward_busy)
			and not mock.stalled
		)
		if quiet:
			calm += 1
			if calm >= 3:
				return true
		else:
			calm = 0
		await process_frame
	print("[mission-test] still_busy mission=%s flush=%s followup=%s stalled=%s" % [backend._mission_busy, backend._mission_flush_again, backend._followup_busy, mock.stalled])
	return false


func _reset_client(backend) -> void:
	_force_idle(backend)
	backend._mission_claim_blocked = ""
	backend._mission_claim_date = ""
	backend._mission_legacy_record = false
	backend.mission_note = ""
	_reward_signals.clear()
	var session = _gs()
	session.match_mode = session.MODE_UNLIMITED
	session.practice_daily = false
	session.pending_mission_runs = []
	session.mission_board = {}
	session.applied_mission_reward_coins = 0
	session.coins = 0
	session.owned_fish = PackedInt32Array()
	session.owned_hats = PackedInt32Array()
	session.fish_index = 0
	session.hat_index = -1
	mock.requests.clear()
	mock.unexpected = 0
	mock.fault = ""
	mock.fault_once = false
	mock.commit_on_fault = false
	mock.fault_url = ""
	mock.delay = 0.0
	mock.stall_board_once = false
	mock.release_stall = false
	mock.legacy_only = false
	mock.bad_json = false


func _rewards_match() -> bool:
	return int(Missions.REWARDS.easy) == 5 and int(Missions.REWARDS.medium) == 10 and int(Missions.REWARDS.hard) == 20 and int(Missions.REWARDS.bonus) == 25 and Missions.MAX_DAILY_REWARD == 60


func _slot(board: Dictionary, slot: String) -> Dictionary:
	var rows: Variant = board.get("slots", [])
	if typeof(rows) != TYPE_ARRAY:
		return {}
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and str(row.get("slot", "")) == slot:
			return row
	return {}


func _await_flush(backend) -> void:
	await backend.flush_daily_missions()
	await _wait_quiet(backend)


func _test_generation(backend) -> void:
	_reset_client(backend)
	mock.zone = "eastern"
	mock.now_unix = Daily.unix_utc(2026, 10, 20, 18, 0, 0)
	await _await_flush(backend)
	var board: Dictionary = _gs().mission_board
	var date := str(board.get("mission_date", ""))
	var easy := _slot(board, "easy")
	var medium := _slot(board, "medium")
	var hard := _slot(board, "hard")
	_check("generation_three_tiers", not easy.is_empty() and not medium.is_empty() and not hard.is_empty(), date)
	_check("generation_rewards", int(easy.get("reward", 0)) == 5 and int(medium.get("reward", 0)) == 10 and int(hard.get("reward", 0)) == 20)
	_check("generation_starts_zero", int(easy.get("progress", -1)) == 0 and int(medium.get("progress", -1)) == 0 and int(hard.get("progress", -1)) == 0 and not bool(easy.get("complete", true)))
	var described := true
	for row in [easy, medium, hard]:
		var mission: Dictionary = Missions.mission_by_id(int(row.get("mission_id", 0)))
		if mission.is_empty() or str(mission.get("description", "")) != str(row.get("description", "")):
			described = false
		if str(mission.get("tier", "")) != str(row.get("slot", "")):
			described = false
		if not bool(mission.get("enabled", false)):
			described = false
		var shown := Missions.display_text(str(row.get("description", "")), int(row.get("mission_id", 0)))
		if not shown.contains(str(int(mission.get("goal", 0)))) and not shown.contains(str(int(mission.get("goal_b", 0)))):
			described = false
	_check("generation_descriptions_match", described)
	var first_ids := [int(easy.get("mission_id", 0)), int(medium.get("mission_id", 0)), int(hard.get("mission_id", 0))]
	await _await_flush(backend)
	var again: Dictionary = _gs().mission_board
	var same: bool = int(_slot(again, "easy").get("mission_id", 0)) == first_ids[0] and int(_slot(again, "medium").get("mission_id", 0)) == first_ids[1] and int(_slot(again, "hard").get("mission_id", 0)) == first_ids[2] and str(again.get("mission_date", "")) == date
	_check("generation_same_day", same)
	var challenge := Daily.challenge_date_from_unix(mock.now_unix)
	_check("generation_matches_daily_challenge_date", date == challenge, "mission=%s challenge=%s" % [date, challenge])
	var achievable := _all_enabled_achievable()
	_check("generation_requirements_achievable", achievable.is_empty(), achievable)


func _all_enabled_achievable() -> String:
	var missing := ""
	for mission in Missions.catalog():
		if not bool(mission.get("enabled", false)):
			continue
		var runs: Array = _plan(mission)
		if runs.is_empty():
			return "no plan %s" % mission.get("id", 0)
		var stats := _fold(runs)
		var judged: Dictionary = Missions.evaluate(str(mission.get("rule", "")), int(mission.get("goal", 0)), int(mission.get("goal_b", 0)), stats)
		if not bool(judged.get("complete", false)):
			missing = "id=%s rule=%s progress=%s goal=%s" % [mission.get("id", 0), mission.get("rule", ""), judged.get("progress", 0), judged.get("goal", 0)]
			return missing
		for run in runs:
			var dive: Dictionary = run
			if not Missions.accept_run(int(run.pipes), int(run.seconds), int(run.coins), int(dive.get("dives_entered", 0))):
				return "rejected run id=%s" % mission.get("id", 0)
			if not Missions.accept_dive(int(run.pipes), dive):
				return "rejected dive id=%s" % mission.get("id", 0)
	return missing


func _plan(mission: Dictionary) -> Array:
	var rule := str(mission.get("rule", ""))
	var goal := int(mission.get("goal", 0))
	var extra := int(mission.get("goal_b", 0))
	var runs: Array = []
	match rule:
		"pipes_total":
			var left := goal
			while left > 0:
				var pipes := mini(left, 80)
				runs.append(_plain(pipes, pipes + 5, 0))
				left -= pipes
		"pipes_best":
			runs.append(_plain(goal, goal + 5, 0))
		"runs":
			for _i in goal:
				runs.append(_plain(1, 2, 0))
		"survive_best":
			var pipes := _pipes_for_seconds(goal)
			runs.append(_plain(pipes, goal, 0))
		"coins_total":
			var left_coins := goal
			while left_coins > 0:
				var taken := mini(16, left_coins)
				runs.append(_plain(80, 100, taken))
				left_coins -= taken
		"coin_runs":
			for _i in goal:
				runs.append(_plain(5, 8, 1))
		"runs_at_least":
			for _i in extra:
				runs.append(_plain(goal, goal + 5, 0))
		"window_sum":
			var each := int(ceil(float(goal) / float(maxi(1, extra))))
			each = mini(each, 80)
			var have := 0
			var guard := 0
			while have < goal and guard < extra:
				var pipes := mini(each, goal - have)
				if guard == extra - 1:
					pipes = mini(80, goal - have)
				runs.append(_plain(pipes, pipes + 5, 0))
				have += pipes
				guard += 1
		"dives_entered":
			var left_in := goal
			while left_in > 0:
				var entered := mini(2, left_in)
				var pipes := 60 if entered > 1 else 30
				runs.append(_dive_run(pipes, 80, entered, 0, 0, 0, 0, 0, 0))
				left_in -= entered
		"dives_completed":
			var left_done := goal
			while left_done > 0:
				var done := mini(2, left_done)
				var pipes_done := 60 if done > 1 else 30
				runs.append(_dive_run(pipes_done, 80, done, done, 10, 0, 0, 0, 0))
				left_done -= done
		"dives_best":
			runs.append(_dive_run(60, 80, goal, goal, 10, 0, 0, 0, 0))
		"dive_seconds":
			var left_sec := goal
			while left_sec > 0:
				var slice := mini(20, left_sec)
				runs.append(_dive_run(30, 50, 1, 0, slice, 0, 0, 0, 0))
				left_sec -= slice
		"lanes_total":
			runs.append(_dive_run(30, 50, 1, 0, 0, goal, goal, 0, 0))
		"lanes_left":
			runs.append(_dive_run(30, 50, 1, 0, 0, goal, goal, 0, 0))
		"lanes_right":
			runs.append(_dive_run(30, 50, 1, 0, 0, goal, 0, goal, 0))
		"obstacles_total", "obstacles_best":
			runs.append(_dive_run(30, 50, 1, 0, 0, 0, 0, 0, goal, 0))
		"mines_total":
			runs.append(_dive_run(30, 50, 1, 0, 0, 0, 0, 0, goal, goal))
		_:
			return []
	return runs


func _pipes_for_seconds(seconds: int) -> int:
	for pipes in [20, 40, 50, 70, 80]:
		if pipes - 1 <= seconds and seconds <= _survival_limit(pipes, 0):
			return pipes
	return 80


func _survival_limit(pipes: int, dives: int) -> int:
	var slack := 12 * int(pipes / 20.0)
	return int(floor(1.8 + float(pipes) * 1.5 + 12.0 + float(slack))) + 28 * dives


func _make_overlay():
	var script = load("res://scripts/daily_missions_overlay.gd")
	return script.new()


func _queued(run_id: String, pipes: int, seconds: int, coins: int) -> Dictionary:
	return {
		"id": run_id,
		"pipes": pipes,
		"seconds": seconds,
		"coins": coins,
		"dives_entered": 0,
		"dives_completed": 0,
		"dive_seconds": 0,
		"lane_changes": 0,
		"lanes_left": 0,
		"lanes_right": 0,
		"obstacles": 0,
		"mines": 0,
	}


func _plain(pipes: int, seconds: int, coins: int) -> Dictionary:
	return _dive_run(pipes, seconds, 0, 0, 0, 0, 0, 0, 0, 0, coins)


func _dive_run(pipes: int, seconds: int, entered: int, completed: int, dive_seconds: int, lanes: int, left: int, right: int, obstacles: int, mines: int = 0, coins: int = 0) -> Dictionary:
	return {
		"pipes": pipes,
		"seconds": seconds,
		"coins": coins,
		"dives_entered": entered,
		"dives_completed": completed,
		"dive_seconds": dive_seconds,
		"lane_changes": lanes,
		"lanes_left": left,
		"lanes_right": right,
		"obstacles": obstacles,
		"mines": mines,
	}


func _fold(runs: Array) -> Dictionary:
	var stats := {
		"pipes_total": 0,
		"runs": 0,
		"best_pipes": 0,
		"best_seconds": 0,
		"gameplay_coins": 0,
		"coin_runs": 0,
		"run_pipes": [],
		"dives_entered": 0,
		"dives_completed": 0,
		"best_dives": 0,
		"dive_seconds": 0,
		"lane_changes": 0,
		"lanes_left": 0,
		"lanes_right": 0,
		"obstacles_dodged": 0,
		"best_obstacles": 0,
		"mines_passed": 0,
	}
	for run in runs:
		stats.pipes_total += int(run.pipes)
		stats.runs += 1
		stats.best_pipes = maxi(int(stats.best_pipes), int(run.pipes))
		stats.best_seconds = maxi(int(stats.best_seconds), int(run.seconds))
		stats.gameplay_coins += int(run.coins)
		if int(run.coins) > 0:
			stats.coin_runs += 1
		stats.run_pipes.append(int(run.pipes))
		stats.dives_entered += int(run.dives_entered)
		stats.dives_completed += int(run.dives_completed)
		stats.best_dives = maxi(int(stats.best_dives), int(run.dives_completed))
		stats.dive_seconds += int(run.dive_seconds)
		stats.lane_changes += int(run.lane_changes)
		stats.lanes_left += int(run.lanes_left)
		stats.lanes_right += int(run.lanes_right)
		stats.obstacles_dodged += int(run.obstacles)
		stats.best_obstacles = maxi(int(stats.best_obstacles), int(run.obstacles))
		stats.mines_passed += int(run.mines)
	return stats


func _test_progress(backend) -> void:
	_reset_client(backend)
	mock.zone = "eastern"
	mock.now_unix = Daily.unix_utc(2026, 10, 20, 18, 0, 0)
	mock.force_today(1, 24, 78)
	var session = _gs()
	session.match_mode = session.MODE_DAILY
	session.remember_mission_run("daily-run-1", 20, 30, 0)
	_check("progress_daily_ignored", session.pending_mission_runs.is_empty())
	session.match_mode = session.MODE_UNLIMITED
	session.practice_daily = true
	session.remember_mission_run("practice-run-1", 20, 30, 0)
	_check("progress_practice_ignored", session.pending_mission_runs.is_empty())
	session.practice_daily = false
	session.remember_mission_run("short", 10, 20, 0)
	session.remember_mission_run("pipe-run-1", 100, 50, 0)
	_check("progress_invalid_not_queued", session.pending_mission_runs.is_empty())
	var queued: Array = Missions.enqueue([], "pipe-run-1", 12, 20, 2)
	var queued_again: Array = Missions.enqueue(queued, "pipe-run-1", 12, 20, 2)
	_check("progress_duplicate_not_queued", queued.size() == 1 and queued_again.size() == 1)
	session.remember_mission_run("pipe-run-1", 12, 20, 2)
	session.remember_mission_run("pipe-run-1", 12, 20, 2)
	await _await_flush(backend)
	var easy := _slot(session.mission_board, "easy")
	_check("progress_pipes_recorded", int(easy.get("progress", 0)) == 12 and bool(easy.get("complete", false)), str(easy.get("progress", "")))
	_check("progress_pending_cleared", session.pending_mission_runs.is_empty())
	var before_rows := mock.run_count(PLAYER_A)
	session.remember_mission_run("pipe-run-1", 12, 20, 2)
	await _await_flush(backend)
	easy = _slot(session.mission_board, "easy")
	_check("progress_duplicate_request_once", int(easy.get("progress", 0)) == 12 and mock.run_count(PLAYER_A) == before_rows)
	session.remember_mission_run("pipe-run-2", 8, 16, 0)
	await _await_flush(backend)
	easy = _slot(session.mission_board, "easy")
	_check("progress_pipes_accumulate", int(easy.get("progress", 0)) == 20)
	var shown := mini(int(easy.get("progress", 0)), int(easy.get("goal", 0)))
	_check("progress_display_caps_at_goal", shown == int(easy.get("goal", 0)) and int(easy.get("progress", 0)) > int(easy.get("goal", 0)))
	var medium := _slot(session.mission_board, "medium")
	_check("progress_survive_not_met", int(medium.get("progress", 0)) == 20 and not bool(medium.get("complete", true)))
	session.remember_mission_run("survive-run-1", 40, 60, 0)
	await _await_flush(backend)
	medium = _slot(session.mission_board, "medium")
	_check("progress_survive_best", int(medium.get("progress", 0)) == 60 and bool(medium.get("complete", false)))
	session.remember_mission_run("survive-run-2", 20, 30, 0)
	await _await_flush(backend)
	medium = _slot(session.mission_board, "medium")
	_check("progress_lower_run_keeps_best", int(medium.get("progress", 0)) == 60)
	var hard_before := int(_slot(session.mission_board, "hard").get("progress", 0))
	session.remember_mission_run("dive-run-001", 60, 90, 0, {
		"dives_entered": 2,
		"dives_completed": 2,
		"dive_seconds": 20,
		"lane_changes": 4,
		"lanes_left": 3,
		"lanes_right": 1,
		"obstacles": 8,
		"mines": 2,
	})
	await _await_flush(backend)
	var hard := _slot(session.mission_board, "hard")
	_check("progress_dive_best", int(hard.get("progress", 0)) == 2 and bool(hard.get("complete", false)) and int(hard.get("progress", 0)) != hard_before)
	var stats: Dictionary = mock.progress_of(PLAYER_A, str(session.mission_board.get("mission_date", "")))
	_check("progress_dive_fields", int(stats.get("dives_entered", 0)) == 2 and int(stats.get("dive_seconds", 0)) == 20 and int(stats.get("lane_changes", 0)) == 4 and int(stats.get("lanes_left", 0)) == 3 and int(stats.get("lanes_right", 0)) == 1 and int(stats.get("obstacles_dodged", 0)) == 8 and int(stats.get("mines_passed", 0)) == 2)
	var rules_ok := await _exercise_rules(backend)
	_check("progress_every_rule", rules_ok.is_empty(), rules_ok)
	var game := FileAccess.get_file_as_string("res://scenes/game/game.gd")
	var deaths := game.count("remember_mission_run(")
	var death_at := game.find("remember_mission_run(")
	var died_at := game.find("func _on_player_died")
	var next_fn := game.find("\nfunc ", death_at)
	_check("progress_only_on_death", deaths == 1 and death_at > died_at and (next_fn < 0 or death_at < next_fn))
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.force_today(4, 21, 38)
	session = _gs()
	session.match_mode = session.MODE_UNLIMITED
	for i in 3:
		session.remember_mission_run("count-run-%02d" % i, 1, 2, 0)
		await _await_flush(backend)
	var runs_row := _slot(session.mission_board, "easy")
	_check("progress_run_count", int(runs_row.get("progress", 0)) == 3 and bool(runs_row.get("complete", false)))
	session.pending_mission_runs = [{
		"id": "rejected-run-1",
		"pipes": 20001,
		"seconds": 30000,
		"coins": 0,
		"dives_entered": 0,
		"dives_completed": 0,
		"dive_seconds": 0,
		"lane_changes": 0,
		"lanes_left": 0,
		"lanes_right": 0,
		"obstacles": 0,
		"mines": 0,
	}]
	var pipes_before := int(mock.progress_of(PLAYER_A, mock.today()).get("pipes_total", 0))
	await _await_flush(backend)
	_check("progress_server_rejects_over_cap", session.pending_mission_runs.is_empty() and int(mock.progress_of(PLAYER_A, mock.today()).get("pipes_total", 0)) == pipes_before)


func _exercise_rules(backend) -> String:
	var seen := {}
	for mission in Missions.catalog():
		if not bool(mission.get("enabled", false)):
			continue
		var rule := str(mission.get("rule", ""))
		if seen.has(rule):
			var previous: Dictionary = seen[rule]
			if int(mission.get("goal", 0)) + int(mission.get("goal_b", 0)) < int(previous.get("goal", 0)) + int(previous.get("goal_b", 0)):
				seen[rule] = mission
		else:
			seen[rule] = mission
	var expected := ["pipes_total", "pipes_best", "runs", "survive_best", "coins_total", "coin_runs", "runs_at_least", "window_sum", "dives_entered", "dives_completed", "dives_best", "dive_seconds", "lanes_total", "lanes_left", "lanes_right", "obstacles_total", "obstacles_best", "mines_total"]
	for rule in expected:
		if not seen.has(rule):
			return "missing %s" % rule
	for rule in expected:
		var mission: Dictionary = seen[rule]
		_reset_client(backend)
		mock.clear_player(PLAYER_A)
		mock.force_today(_filler("easy", mission), _filler("medium", mission), _filler("hard", mission))
		var forced := {"easy": _filler("easy", mission), "medium": _filler("medium", mission), "hard": _filler("hard", mission)}
		forced[str(mission.get("tier", ""))] = int(mission.get("id", 0))
		mock.force_today(int(forced["easy"]), int(forced["medium"]), int(forced["hard"]))
		var runs: Array = _plan(mission)
		var session = _gs()
		session.match_mode = session.MODE_UNLIMITED
		var n := 0
		for run in runs:
			n += 1
			session.remember_mission_run("rule-%s-%02d" % [rule, n], int(run.pipes), int(run.seconds), int(run.coins), run)
			await _await_flush(backend)
		var row := _slot(session.mission_board, str(mission.get("tier", "")))
		if int(row.get("mission_id", 0)) != int(mission.get("id", 0)) or not bool(row.get("complete", false)):
			return "%s id=%s progress=%s goal=%s" % [rule, row.get("mission_id", 0), row.get("progress", 0), row.get("goal", 0)]
		var again := mock.run_count(PLAYER_A)
		session.remember_mission_run("rule-%s-01" % rule, int(runs[0].pipes), int(runs[0].seconds), int(runs[0].coins), runs[0])
		await _await_flush(backend)
		if mock.run_count(PLAYER_A) != again:
			return "%s duplicated" % rule
	return ""


func _filler(tier: String, mission: Dictionary) -> int:
	if str(mission.get("tier", "")) == tier:
		return int(mission.get("id", 0))
	if tier == "easy":
		return 9
	if tier == "medium":
		return 26
	return 42


func _test_claims(backend) -> void:
	_reset_client(backend)
	mock.zone = "eastern"
	mock.now_unix = Daily.unix_utc(2026, 10, 20, 18, 0, 0)
	mock.clear_player(PLAYER_A)
	mock.force_today(1, 16, 31)
	var denied: Dictionary = mock.claim(PLAYER_A, "easy")
	_check("claim_incomplete_denied", str(denied.get("reason", "")) == "incomplete" and int(denied.get("granted_now", 1)) == 0 and mock.profile_coins(PLAYER_A) == 0)
	var session = _gs()
	session.match_mode = session.MODE_UNLIMITED
	session.coins = 3
	session.add_coins(0)
	var wallet_before := int(session.coins)
	session.remember_mission_run("claim-run-01", 10, 20, 0)
	await _await_flush(backend)
	var easy := _slot(session.mission_board, "easy")
	_check("claim_easy_once", bool(easy.get("claimed", false)) and int(session.coins) == wallet_before + 5 and mock.profile_coins(PLAYER_A) == 5 and mock.claim_count(PLAYER_A, mock.today(), "easy") == 1)
	var signaled := false
	for item in _reward_signals:
		if str(item.get("slot", "")) == "easy" and int(item.get("coins", 0)) == 5:
			signaled = true
	_check("claim_easy_announced", signaled)
	var signals_before := _reward_signals.size()
	var coins_before := int(session.coins)
	await backend.claim_daily_mission("easy")
	await _wait_quiet(backend)
	_check("claim_easy_again_noop", int(session.coins) == coins_before and mock.claim_count(PLAYER_A, mock.today(), "easy") == 1 and _reward_signals.size() == signals_before)
	var medium_coins := int(session.coins)
	session.remember_mission_run("claim-run-02", 40, 70, 0)
	await _await_flush(backend)
	_check("claim_medium_independent", bool(_slot(session.mission_board, "medium").get("claimed", false)) and not bool(_slot(session.mission_board, "hard").get("complete", true)) and int(session.coins) == medium_coins + 10)
	var saved_coins := int(session.coins)
	var saved_applied := int(session.applied_mission_reward_coins)
	session.coins = 0
	session.applied_mission_reward_coins = 0
	session.mission_board = {}
	session._load()
	_check("claim_persists_restart", int(session.coins) == saved_coins and int(session.applied_mission_reward_coins) == saved_applied and bool(_slot(session.mission_board, "easy").get("claimed", false)))
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.force_today(1, 16, 31)
	mock.record(PLAYER_A, "parallel-run-1", 10, 20, 0, {})
	var seeded: Dictionary = mock.board(PLAYER_A)
	session = _gs()
	session.mission_board = seeded
	session.applied_mission_reward_coins = 0
	session.coins = 0
	mock.delay = 0.2
	var inflight := mock.claim_hits
	backend.claim_daily_mission("easy")
	backend.claim_daily_mission("easy")
	await _wait_quiet(backend)
	mock.delay = 0.0
	_check("claim_parallel_no_duplicate", mock.claim_hits == inflight + 1 and mock.claim_count(PLAYER_A, mock.today(), "easy") == 1 and int(session.coins) == 5, "hits=%d coins=%d" % [mock.claim_hits - inflight, int(session.coins)])


func _test_bonus_orders(backend) -> void:
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.zone = "eastern"
	mock.now_unix = Daily.unix_utc(2026, 10, 20, 18, 0, 0)
	mock.force_today(1, 19, 33)
	var early: Dictionary = mock.claim(PLAYER_A, "bonus")
	_check("bonus_locked_until_three", str(early.get("reason", "")) == "incomplete" and mock.profile_coins(PLAYER_A) == 0)
	var hard_first: Dictionary = mock.claim_after_ready(PLAYER_A, "hard")
	var easy_second: Dictionary = mock.claim(PLAYER_A, "easy")
	var medium_third: Dictionary = mock.claim(PLAYER_A, "medium")
	var bonus: Dictionary = mock.claim(PLAYER_A, "bonus")
	var bonus_again: Dictionary = mock.claim(PLAYER_A, "bonus")
	_check("bonus_any_slot_order", int(hard_first.get("granted_now", 0)) == 20 and int(easy_second.get("granted_now", 0)) == 5 and int(medium_third.get("granted_now", 0)) == 10 and int(bonus.get("granted_now", 0)) == 25 and int(bonus_again.get("granted_now", 0)) == 0 and mock.profile_coins(PLAYER_A) == 60, "coins=%d" % mock.profile_coins(PLAYER_A))
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.force_today(1, 19, 33)
	var session = _gs()
	session.match_mode = session.MODE_UNLIMITED
	session.remember_mission_run("bonus-run-01", 50, 80, 0)
	await _await_flush(backend)
	var board: Dictionary = session.mission_board
	var bonus_row: Dictionary = board.get("bonus", {})
	_check("bonus_auto_claim_order", bool(_slot(board, "easy").get("claimed", false)) and bool(_slot(board, "medium").get("claimed", false)) and bool(_slot(board, "hard").get("claimed", false)) and bool(bonus_row.get("claimed", false)) and int(session.coins) == 60 and mock.profile_coins(PLAYER_A) == 60)
	var order: PackedStringArray = PackedStringArray()
	for item in _reward_signals:
		order.append(str(item.get("slot", "")))
	_check("bonus_signal_order", order == PackedStringArray(["easy", "medium", "hard", "bonus"]), " ".join(order))
	session._save()
	session.coins = 0
	session.mission_board = {}
	session.applied_mission_reward_coins = 0
	session._load()
	_check("bonus_persists_restart", int(session.coins) == 60 and bool(session.mission_board.get("bonus", {}).get("claimed", false)))
	var next := Daily.eastern_midnight_unix(2026, 10, 21) + 60
	mock.now_unix = next
	mock.force_today(1, 19, 33)
	await _await_flush(backend)
	var rolled: Dictionary = session.mission_board
	_check("bonus_resets_next_day", str(rolled.get("mission_date", "")) == "2026-10-21" and not bool(_slot(rolled, "easy").get("claimed", false)) and not bool(rolled.get("bonus", {}).get("unlocked", true)) and int(session.coins) == 60)


func _test_reset(backend) -> void:
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.zone = "eastern"
	var midnight := Daily.eastern_midnight_unix(2026, 10, 21)
	mock.now_unix = midnight - 60
	mock.force_today(1, 16, 31)
	var session = _gs()
	session.match_mode = session.MODE_UNLIMITED
	session.remember_mission_run("reset-run-01", 10, 20, 0)
	await _await_flush(backend)
	var before_date := str(session.mission_board.get("mission_date", ""))
	var before_reset := int(session.mission_board.get("resets_at", 0))
	_check("reset_one_minute_before", before_date == "2026-10-20" and before_date == Daily.challenge_date_from_unix(mock.now_unix) and before_reset == midnight)
	mock.now_unix = midnight
	await _await_flush(backend)
	_check("reset_exactly", str(session.mission_board.get("mission_date", "")) == "2026-10-21" and int(_slot(session.mission_board, "easy").get("progress", -1)) == 0 and mock.progress_of(PLAYER_A, "2026-10-20").get("pipes_total", 0) == 10)
	mock.now_unix = midnight + 60
	await _await_flush(backend)
	_check("reset_one_minute_after", str(session.mission_board.get("mission_date", "")) == "2026-10-21" and str(session.mission_board.get("mission_date", "")) == Daily.challenge_date_from_unix(mock.now_unix))
	var utc_instant := Daily.unix_utc(2026, 10, 21, 0, 30, 0)
	mock.zone = "utc"
	mock.now_unix = utc_instant
	await _await_flush(backend)
	var utc_date := str(session.mission_board.get("mission_date", ""))
	var eastern_date := Daily.challenge_date_from_unix(utc_instant)
	_check("reset_utc_board_differs_from_daily_challenge", utc_date == "2026-10-21" and eastern_date == "2026-10-20" and utc_date != eastern_date, "mission=%s daily=%s" % [utc_date, eastern_date])
	_warn("Source mismatch: daily_missions.sql and daily_missions_deep_dive.sql publish mission days in UTC. daily_missions_eastern_reset.sql moves them to America/New_York but says not to run until approved. The client displays server mission_date and does not choose the day. Live Supabase was not queried.")
	mock.zone = "eastern"
	mock.now_unix = Daily.unix_utc(2026, 10, 20, 18, 0, 0)
	await _await_flush(backend)
	var kept := int(_slot(session.mission_board, "easy").get("progress", 0))
	session.mission_board["server_now"] = int(Time.get_unix_time_from_system()) - 100000
	session.mission_board["resets_at"] = int(Time.get_unix_time_from_system()) - 10
	session.mission_board["fetched_at"] = int(Time.get_unix_time_from_system()) - 100000
	var overlay = _make_overlay()
	overlay.use_screen_board()
	root.add_child(overlay)
	await process_frame
	overlay.present("board", true)
	overlay._refresh_countdown()
	await _wait_quiet(backend)
	_check("reset_device_clock_keeps_server_day", str(session.mission_board.get("mission_date", "")) == Daily.challenge_date_from_unix(mock.now_unix) and int(_slot(session.mission_board, "easy").get("progress", 0)) == kept)
	mock.now_unix = Daily.eastern_midnight_unix(2026, 10, 21) + 30
	session.mission_board["server_now"] = int(Time.get_unix_time_from_system())
	session.mission_board["resets_at"] = int(Time.get_unix_time_from_system())
	session.mission_board["fetched_at"] = int(Time.get_unix_time_from_system())
	overlay._countdown_refresh = false
	overlay._refresh_countdown()
	await _wait_quiet(backend)
	_check("reset_open_app_refreshes", str(session.mission_board.get("mission_date", "")) == "2026-10-21")
	overlay.queue_free()
	var reopen_coins := int(session.coins)
	session._save()
	session.mission_board = {}
	session.coins = -1
	session._load()
	_check("reset_reopen_keeps_wallet", int(session.coins) == reopen_coins and str(session.mission_board.get("mission_date", "")) == "2026-10-21")


func _test_rpc_compatibility(backend) -> void:
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.zone = "eastern"
	mock.now_unix = Daily.unix_utc(2026, 10, 20, 18, 0, 0)
	mock.force_today(1, 16, 31)
	mock.legacy_only = true
	var session = _gs()
	session.match_mode = session.MODE_UNLIMITED
	session.remember_mission_run("plain-run-01", 10, 20, 2)
	await _await_flush(backend)
	var plain_bodies: Array = []
	for item in mock.requests:
		if str(item.get("url", "")).contains("record_unlimited_mission_run"):
			plain_bodies.append(str(item.get("body", "")))
	_check(
		"rpc_plain_fallback_keeps_run_id",
		plain_bodies.size() == 2
		and plain_bodies[0].contains("p_dives_entered")
		and plain_bodies[0].contains("plain-run-01")
		and not plain_bodies[1].contains("p_dives_entered")
		and plain_bodies[1].contains("plain-run-01")
		and session.pending_mission_runs.is_empty()
		and mock.run_count(PLAYER_A) == 1
	)
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.force_today(1, 16, 31)
	mock.legacy_only = true
	var dive := {
		"dives_entered": 1,
		"dives_completed": 1,
		"dive_seconds": 10,
		"lane_changes": 2,
		"lanes_left": 1,
		"lanes_right": 1,
		"obstacles": 3,
		"mines": 1,
	}
	session.remember_mission_run("dive-run-001", 40, 80, 4, dive)
	await _await_flush(backend)
	var dive_bodies: Array = []
	var stripped := false
	for item in mock.requests:
		if not str(item.get("url", "")).contains("record_unlimited_mission_run"):
			continue
		var body := str(item.get("body", ""))
		dive_bodies.append(body)
		if not body.contains("p_dives_entered"):
			stripped = true
	_check(
		"rpc_dive_mismatch_keeps_pending",
		dive_bodies.size() >= 1
		and not stripped
		and session.pending_mission_runs.size() == 1
		and str(session.pending_mission_runs[0].get("id", "")) == "dive-run-001"
		and str(backend.mission_note) == "error"
		and mock.run_count(PLAYER_A) == 0
	)
	mock.legacy_only = false
	mock.requests.clear()
	backend.flush_daily_missions()
	await _await_flush(backend)
	var stats: Dictionary = mock.progress.get("%s|%s" % [PLAYER_A, mock.today()], {})
	_check(
		"rpc_dive_retry_same_id",
		session.pending_mission_runs.is_empty()
		and mock.run_count(PLAYER_A) == 1
		and int(stats.get("dives_entered", 0)) == 1
		and int(stats.get("obstacles_dodged", 0)) == 3
	)
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.force_today(1, 16, 31)
	mock.legacy_only = true
	session.remember_mission_run("long-plain-5000", 5000, 10000, 1000)
	await _await_flush(backend)
	_check(
		"rpc_old_server_keeps_long_run",
		session.pending_mission_runs.size() == 1
		and str(session.pending_mission_runs[0].get("id", "")) == "long-plain-5000"
		and mock.run_count(PLAYER_A) == 0
		and str(backend.mission_note) == "error"
	)
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.force_today(1, 16, 31)
	var long_dive := {
		"dives_entered": 166,
		"dives_completed": 166,
		"dive_seconds": 3320,
		"lane_changes": 0,
		"lanes_left": 0,
		"lanes_right": 0,
		"obstacles": 0,
		"mines": 0,
	}
	session.remember_mission_run("long-run-5000", 5000, 12000, 1000, long_dive)
	await _await_flush(backend)
	stats = mock.progress.get("%s|%s" % [PLAYER_A, mock.today()], {})
	session.remember_mission_run("long-run-5000", 5000, 12000, 1000, long_dive)
	await _await_flush(backend)
	var again: Dictionary = mock.progress.get("%s|%s" % [PLAYER_A, mock.today()], {})
	_check(
		"rpc_checkpoint_5000_once",
		int(stats.get("pipes_total", 0)) == 5000
		and int(stats.get("gameplay_coins", 0)) == 1000
		and int(stats.get("dives_entered", 0)) == 166
		and int(again.get("pipes_total", 0)) == 5000
		and mock.run_count(PLAYER_A) == 1
	)


func _test_network(backend) -> void:
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.zone = "eastern"
	mock.now_unix = Daily.unix_utc(2026, 10, 20, 18, 0, 0)
	mock.force_today(1, 16, 31)
	var session = _gs()
	session.match_mode = session.MODE_UNLIMITED
	mock.fault = "offline"
	session.pending_mission_runs = [_queued("offline-run-1", 10, 20, 0)]
	await _await_flush(backend)
	_check("network_offline_keeps_pending", session.pending_mission_runs.size() == 1 and mock.run_count(PLAYER_A) == 0 and int(session.coins) == 0 and str(backend.mission_note) == "error")
	mock.fault = "timeout"
	await _await_flush(backend)
	_check("network_timeout_keeps_pending", session.pending_mission_runs.size() == 1 and mock.run_count(PLAYER_A) == 0)
	mock.fault = "429"
	await _await_flush(backend)
	_check("network_429_no_reward", session.pending_mission_runs.size() == 1 and mock.profile_coins(PLAYER_A) == 0 and _reward_signals.is_empty())
	mock.fault = "500"
	await _await_flush(backend)
	_check("network_500_no_reward", session.pending_mission_runs.size() == 1 and mock.profile_coins(PLAYER_A) == 0)
	mock.fault = ""
	mock.bad_json = true
	await _await_flush(backend)
	_check("network_bad_json_no_reward", session.pending_mission_runs.size() == 1 and mock.profile_coins(PLAYER_A) == 0)
	mock.bad_json = false
	await _await_flush(backend)
	_check("network_recovers", session.pending_mission_runs.is_empty() and int(_slot(session.mission_board, "easy").get("progress", 0)) == 10 and bool(_slot(session.mission_board, "easy").get("claimed", false)) and mock.profile_coins(PLAYER_A) == 5 and mock.claim_count(PLAYER_A, mock.today(), "easy") == 1)
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.force_today(1, 16, 31)
	mock.fault = "timeout"
	mock.fault_once = true
	mock.commit_on_fault = true
	mock.fault_url = "record_unlimited_mission_run"
	session = _gs()
	session.match_mode = session.MODE_UNLIMITED
	session.pending_mission_runs = [_queued("lost-run-0001", 10, 20, 0)]
	await _await_flush(backend)
	_check("network_lost_record_retries_once", mock.run_count(PLAYER_A) == 1 and int(_slot(session.mission_board, "easy").get("progress", 0)) == 10 and bool(_slot(session.mission_board, "easy").get("claimed", false)))
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.force_today(1, 16, 31)
	mock.record(PLAYER_A, "ready-run-01", 10, 20, 0, {})
	var seeded: Dictionary = mock.board(PLAYER_A)
	session = _gs()
	session.mission_board = seeded
	session.applied_mission_reward_coins = int(seeded.get("mission_reward_coins", 0))
	session.coins = 0
	mock.fault = "timeout"
	mock.commit_on_fault = true
	mock.fault_url = "claim_daily_mission"
	_reward_signals.clear()
	await backend.claim_daily_mission("easy")
	await _wait_quiet(backend)
	_check("network_lost_claim_not_shown_success", mock.claim_count(PLAYER_A, mock.today(), "easy") == 1 and mock.profile_coins(PLAYER_A) == 5 and int(session.coins) == 0 and _reward_signals.is_empty() and not bool(_slot(session.mission_board, "easy").get("claimed", false)))
	mock.fault = ""
	mock.commit_on_fault = false
	mock.fault_url = ""
	await _await_flush(backend)
	_check("network_lost_claim_recovers_once", int(session.coins) == 5 and bool(_slot(session.mission_board, "easy").get("claimed", false)) and mock.claim_count(PLAYER_A, mock.today(), "easy") == 1 and mock.profile_coins(PLAYER_A) == 5)
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.force_today(2, 17, 32)
	session = _gs()
	session.match_mode = session.MODE_UNLIMITED
	mock.stall_board_once = true
	session.pending_mission_runs = [_queued("stall-run-01", 10, 20, 0)]
	backend.flush_daily_missions()
	var guard := 0
	while not mock.stalled and guard < 80:
		await process_frame
		guard += 1
	_check("network_stalled", mock.stalled)
	var stale_date := mock.today()
	mock.now_unix = Daily.eastern_midnight_unix(2026, 10, 21) + 120
	backend.flush_daily_missions()
	mock.release_stall = true
	await _wait_quiet(backend, 12000)
	_check("network_stale_board_does_not_win", str(session.mission_board.get("mission_date", "")) == "2026-10-21" and stale_date == "2026-10-20", str(session.mission_board.get("mission_date", "")))
	mock.delay = 0.2
	var slow_ok := await _wait_quiet(backend, 1000)
	await _await_flush(backend)
	mock.delay = 0.0
	_check("network_slow_still_returns", slow_ok and str(session.mission_board.get("mission_date", "")) == "2026-10-21")


func _test_cross_client(backend) -> void:
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.clear_player(PLAYER_B)
	mock.zone = "eastern"
	mock.now_unix = Daily.unix_utc(2026, 10, 20, 18, 0, 0)
	mock.force_today(1, 16, 31)
	var session = _gs()
	session.match_mode = session.MODE_UNLIMITED
	session.remember_mission_run("client-a-run-1", 10, 20, 0)
	await _await_flush(backend)
	var date_a := str(session.mission_board.get("mission_date", ""))
	var a_state := _capture()
	_install(backend, TOKEN_B, PLAYER_B)
	_reset_client(backend)
	mock.force_today(1, 16, 31)
	session = _gs()
	session.match_mode = session.MODE_UNLIMITED
	await _await_flush(backend)
	var date_b := str(session.mission_board.get("mission_date", ""))
	_check("cross_same_period", date_a == date_b and date_a == Daily.challenge_date_from_unix(mock.now_unix) and int(_slot(session.mission_board, "easy").get("mission_id", 0)) == int(_slot(a_state.board, "easy").get("mission_id", 0)))
	_check("cross_progress_isolated", int(_slot(session.mission_board, "easy").get("progress", -1)) == 0 and not bool(_slot(session.mission_board, "easy").get("claimed", false)))
	session.remember_mission_run("client-b-run-1", 15, 25, 0)
	await _await_flush(backend)
	_install(backend, TOKEN_A, PLAYER_A)
	_restore_capture(a_state)
	await _await_flush(backend)
	_check("cross_refresh_keeps_owner", int(_slot(session.mission_board, "easy").get("progress", 0)) == 10 and bool(_slot(session.mission_board, "easy").get("claimed", false)) and mock.profile_coins(PLAYER_B) == 5 and mock.profile_coins(PLAYER_A) == 5)
	var spoofed: Dictionary = await mock.request_json(
		"POST",
		"https://example.invalid/rest/v1/rpc/claim_daily_mission",
		mock.auth_headers(TOKEN_A),
		JSON.stringify({"p_slot": "medium", "p_player_id": PLAYER_B})
	)
	var spoof_data: Dictionary = spoofed.get("data", {})
	_check("cross_ignores_spoofed_player", str(spoof_data.get("reason", "")) == "incomplete" and mock.claim_count(PLAYER_B, mock.today(), "medium") == 0 and mock.profile_coins(PLAYER_B) == 5, str(spoof_data.get("reason", "")))
	var repo = Repo.new()
	var body := repo.claim_body("easy")
	var recorded := repo.record_body("client-a-run-1", 10, 20, 0, {})
	_check("cross_client_omits_player_id", not body.contains("player") and not recorded.contains("p_player_id"))
	_warn("Server identity is auth.uid() from the bearer token. The client never sends a player id for missions. A stolen access token could still act as that user. This was checked in the mock, not against live JWT verification.")


func _capture() -> Dictionary:
	var session = _gs()
	return {
		"coins": int(session.coins),
		"applied": int(session.applied_mission_reward_coins),
		"board": session.mission_board.duplicate(true),
		"pending": session.pending_mission_runs.duplicate(true),
	}


func _restore_capture(state: Dictionary) -> void:
	var session = _gs()
	session.coins = int(state.get("coins", 0))
	session.applied_mission_reward_coins = int(state.get("applied", 0))
	session.mission_board = state.get("board", {}).duplicate(true)
	session.pending_mission_runs = state.get("pending", []).duplicate(true)


func _test_coins(backend) -> void:
	_reset_client(backend)
	var session = _gs()
	session.coins = 0
	session.add_coins(4)
	session.add_coins(4)
	_check("coins_gameplay_stacks", int(session.coins) == 8)
	var price := RR.fish_price(RR.FREE_FISH)
	session.coins = price
	var bought: bool = session.buy_fish(RR.FREE_FISH)
	var again: bool = session.buy_fish(RR.FREE_FISH)
	_check("coins_fish_once", bought and again and int(session.coins) == 0 and session.owns_fish(RR.FREE_FISH))
	var hat_price := RR.hat_price(0)
	session.coins = hat_price - 1
	var denied: bool = session.buy_hat(0)
	var denied_coins := int(session.coins)
	session.add_coins(1)
	var hat_ok: bool = session.buy_hat(0)
	var hat_again: bool = session.buy_hat(0)
	_check("coins_hat_exact", not denied and denied_coins == hat_price - 1 and hat_ok and hat_again and int(session.coins) == 0)
	session.coins = 7
	session.add_coins(-100)
	_check("coins_no_negative", int(session.coins) == 0)
	session.coins = 1 << 62
	session.add_coins(1 << 62)
	_check("coins_overflow_non_negative", int(session.coins) >= 0)
	if int(session.coins) == 0:
		_warn("add_coins wraps at the 64-bit ceiling and the negative result is clamped to 0. Proposed fix: saturate instead of wrapping. Gameplay amounts cannot reach this value.")
	session.coins = 9
	session.applied_mission_reward_coins = 0
	session._save()
	session.coins = 0
	session.owned_fish = PackedInt32Array()
	session.owned_hats = PackedInt32Array()
	session._load()
	_check("coins_persist", int(session.coins) == 9 and session.owns_fish(RR.FREE_FISH) and session.owns_hat(0))
	var ads := FileAccess.get_file_as_string("res://scenes/game/game.gd")
	_check("coins_ad_bonus_is_run_coins", ads.contains("GameSession.add_coins(bonus)") or ads.contains("add_coins(bonus)"))
	backend.mission_note = ""


func _test_ui(backend) -> void:
	_reset_client(backend)
	mock.clear_player(PLAYER_A)
	mock.zone = "eastern"
	mock.now_unix = Daily.unix_utc(2026, 10, 20, 18, 0, 0)
	mock.force_today(1, 24, 40)
	var now := int(Time.get_unix_time_from_system())
	var board := mock.board(PLAYER_A)
	board["server_now"] = now
	board["resets_at"] = now + 3661
	board["fetched_at"] = now
	var session = _gs()
	session.mission_board = board
	var overlay = _make_overlay()
	overlay.use_screen_board()
	root.add_child(overlay)
	await process_frame
	overlay.refresh_from_session()
	overlay.present("board", true)
	await process_frame
	var easy_text := str(overlay._descriptions[0]._value)
	var medium_text := str(overlay._descriptions[1]._value)
	var hard_text := str(overlay._descriptions[2]._value)
	var easy_count := str(overlay._counters[0]._text)
	var bonus_text := str(overlay._bonus_text._text)
	var countdown := str(overlay._countdown._value)
	_check("ui_overlay_labels", easy_text == "Pass 10 Pipes" and medium_text == "Survive 60 Seconds" and hard_text == "Survive 120 Seconds", "%s | %s | %s" % [easy_text, medium_text, hard_text])
	_check("ui_overlay_progress", easy_count == "0/10" and str(overlay._counters[1]._text) == "0/60" and str(overlay._counters[2]._text) == "0/120")
	_check("ui_overlay_incomplete_status", str(overlay._status[0]._mode) == "")
	board.slots[0]["progress"] = 25
	board.slots[0]["complete"] = true
	session.mission_board = board
	overlay.refresh_from_session()
	_check("ui_overlay_caps_progress", str(overlay._counters[0]._text) == "10/10" and str(overlay._status[0]._mode) == "done")
	_check("ui_overlay_rewards", str(overlay._reward_text[0]._text) == "+5" and str(overlay._reward_text[1]._text) == "+10" and str(overlay._reward_text[2]._text) == "+20" and bonus_text == "+25")
	_check("ui_overlay_countdown", countdown == "RESETS IN 01:01:01", countdown)
	var back_found := false
	for child in overlay._host.get_children():
		if child is Button and not (child as Button).disabled:
			back_found = true
	overlay._dismiss_from_back()
	_check("ui_overlay_back", back_found and overlay.mode() == "hidden")
	board = mock.board(PLAYER_A)
	var progressed: Dictionary = board.duplicate(true)
	progressed.slots[0]["progress"] = 10
	progressed.slots[0]["complete"] = true
	progressed.slots[0]["claimed"] = false
	session.mission_board = progressed
	var panel_script = load("res://scripts/daily_missions_panel.gd")
	var panel = panel_script.new()
	root.add_child(panel)
	await process_frame
	panel._render()
	var easy_card: Dictionary = panel._cards.easy
	var bonus_card: Dictionary = panel._cards.bonus
	_check("ui_panel_description", str(easy_card.body.text) == "Pass 10 pipes total." and str(easy_card.count.text).begins_with("10 / 10"))
	_check("ui_panel_claim_hidden", not easy_card.claim.visible and not bonus_card.claim.visible and easy_card.claim.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("ui_panel_pending", str(easy_card.mark.text) == "PENDING" and easy_card.mark.visible)
	panel.open()
	await _wait_quiet(backend)
	_check("ui_panel_open_keeps_claim_hidden", not easy_card.claim.visible and panel.visible)
	progressed.slots[0]["claimed"] = true
	progressed.bonus = board.get("bonus", {}).duplicate(true)
	progressed.bonus["progress"] = 1
	progressed.bonus["unlocked"] = false
	progressed.bonus["claimed"] = false
	session.mission_board = progressed
	panel._render()
	_check("ui_panel_claimed_mark", str(easy_card.mark.text) == "✓" and not easy_card.claim.visible)
	var closed_hits: Array = [0]
	panel.closed.connect(func() -> void:
		closed_hits[0] = int(closed_hits[0]) + 1
	)
	panel._back.emit_signal("pressed")
	_check("ui_panel_back", int(closed_hits[0]) == 1 and not panel.visible, "hits=%s visible=%s" % [closed_hits[0], panel.visible])
	panel.queue_free()
	overlay.queue_free()
	_warn("Headless mode checked live overlay and panel text, claim-button visibility, countdown text, and Back. It cannot confirm pixel alignment. Existing layout checks cover the board geometry; a device screenshot is still needed for visual spacing.")
	backend.mission_note = ""


func _test_contract() -> void:
	var base := FileAccess.get_file_as_string("res://tools/supabase/daily_missions.sql")
	var dive := FileAccess.get_file_as_string("res://tools/supabase/daily_missions_deep_dive.sql")
	var eastern := FileAccess.get_file_as_string("res://tools/supabase/daily_missions_eastern_reset.sql")
	var repo = Repo.new()
	var record := repo.record_body("contract1", 10, 20, 1, {"dives_entered": 1, "dives_completed": 1, "dive_seconds": 10, "lane_changes": 2, "lanes_left": 1, "lanes_right": 1, "obstacles": 3, "mines": 1})
	var claim := repo.claim_body("easy")
	var keys := ["p_run_id", "p_pipes", "p_seconds", "p_gameplay_coins", "p_dives_entered", "p_dives_completed", "p_dive_seconds", "p_lane_changes", "p_lanes_left", "p_lanes_right", "p_obstacles", "p_mines"]
	var keys_ok := true
	for key in keys:
		if not record.contains(key) or not eastern.contains(key):
			keys_ok = false
	_check("contract_rpc_params", keys_ok and claim.contains("p_slot") and repo.board_url().ends_with("/rpc/get_daily_missions") and repo.record_url().ends_with("/rpc/record_unlimited_mission_run") and repo.claim_url().ends_with("/rpc/claim_daily_mission") and eastern.contains("claim_daily_mission(p_slot text)") and not eastern.contains("create or replace function public.get_daily_missions"))
	_check("contract_rewards_and_unique", eastern.contains("when 'easy' then 5") and eastern.contains("when 'medium' then 10") and eastern.contains("'reward', 25") and eastern.contains("existing_sum + reward > 60") and base.contains("primary key (player_id, mission_date, slot)"))
	_check("contract_identity_rls", eastern.contains("auth.uid()") and base.contains("enable row level security") and base.contains("player_id = auth.uid()") and base.contains("grant select on public.daily_mission_claims") and not base.contains("grant insert on public.daily_mission_claims"))
	_check("contract_eastern_file_gated", eastern.contains("America/New_York") and eastern.contains("Do not run until this reset change is approved.") and base.contains("timezone('utc'") and dive.contains("timezone('utc'"))
	var client := FileAccess.get_file_as_string("res://scripts/daily_missions.gd")
	_check("contract_client_names_eastern", client.contains("America/New_York") and client.contains("preview_rotation() mirrors the picker"))
	_warn("Database contract checks read the SQL files in the repo. They do not prove which function is deployed. No SQL was executed.")


class MissionMock extends RefCounted:
	const Missions := preload("res://scripts/daily_missions.gd")
	const Daily := preload("res://scripts/daily_challenge.gd")
	const ClientScript := preload("res://scripts/backend/supabase_client.gd")

	var host: Node
	var headers_client = null
	var tokens: Dictionary = {}
	var zone := "eastern"
	var now_unix := 0
	var profiles: Dictionary = {}
	var progress: Dictionary = {}
	var runs: Dictionary = {}
	var claims: Dictionary = {}
	var sets: Dictionary = {}
	var requests: Array = []
	var unexpected := 0
	var fault := ""
	var fault_once := false
	var commit_on_fault := false
	var fault_url := ""
	var delay := 0.0
	var stall_board_once := false
	var stalled := false
	var release_stall := false
	var legacy_only := false
	var bad_json := false
	var claim_hits := 0

	func _init(owner: Node) -> void:
		host = owner
		headers_client = ClientScript.new(owner)
		now_unix = Daily.unix_utc(2026, 10, 20, 18, 0, 0)

	func cancel() -> void:
		pass

	func is_ready() -> bool:
		return true

	func auth_headers(access_token: String = "") -> PackedStringArray:
		return headers_client.auth_headers(access_token)

	func request_json(method: String, url: String, headers: PackedStringArray, body: String = "") -> Dictionary:
		return await _dispatch(method, url, headers, body)

	func request_json_independent(method: String, url: String, headers: PackedStringArray, body: String = "") -> Dictionary:
		return await _dispatch(method, url, headers, body)

	func today() -> String:
		if zone == "utc":
			return Daily.utc_date_from_unix(now_unix)
		return Daily.challenge_date_from_unix(now_unix)

	func force_today(easy_id: int, medium_id: int, hard_id: int) -> void:
		sets[today()] = {"easy": easy_id, "medium": medium_id, "hard": hard_id}

	func clear_player(uid: String) -> void:
		profiles.erase(uid)
		var drop: Array = []
		for key in progress.keys():
			if str(key).begins_with(uid + "|"):
				drop.append(key)
		for key in drop:
			progress.erase(key)
		drop.clear()
		for key in runs.keys():
			if str(key).begins_with(uid + "|"):
				drop.append(key)
		for key in drop:
			runs.erase(key)
		drop.clear()
		for key in claims.keys():
			if str(key).begins_with(uid + "|"):
				drop.append(key)
		for key in drop:
			claims.erase(key)

	func profile_coins(uid: String) -> int:
		return int(profiles.get(uid, {}).get("mission_reward_coins", 0))

	func run_count(uid: String) -> int:
		var n := 0
		for key in runs.keys():
			if str(key).begins_with(uid + "|"):
				n += 1
		return n

	func claim_count(uid: String, date: String, slot: String) -> int:
		return 1 if claims.has("%s|%s|%s" % [uid, date, slot]) else 0

	func progress_of(uid: String, date: String) -> Dictionary:
		return progress.get("%s|%s" % [uid, date], {}).duplicate(true)

	func claim(uid: String, slot: String) -> Dictionary:
		return _claim(uid, slot)

	func claim_after_ready(uid: String, slot: String) -> Dictionary:
		_prepare_complete(uid)
		return _claim(uid, slot)

	func claim_body(uid: String, slot: String, _spoof: String) -> Dictionary:
		return _claim(uid, slot)

	func record(uid: String, run_id: String, pipes: int, seconds: int, coins: int, dive: Dictionary) -> Dictionary:
		return _record(uid, run_id, pipes, seconds, coins, dive)

	func _prepare_complete(uid: String) -> void:
		var date := today()
		var stats := _blank()
		stats.pipes_total = 200
		stats.runs = 30
		stats.best_pipes = 80
		stats.best_seconds = 180
		stats.gameplay_coins = 500
		stats.coin_runs = 10
		stats.run_pipes = [80, 80, 80, 80, 80]
		stats.dives_entered = 8
		stats.dives_completed = 6
		stats.best_dives = 2
		stats.dive_seconds = 80
		stats.lane_changes = 80
		stats.lanes_left = 40
		stats.lanes_right = 40
		stats.obstacles_dodged = 80
		stats.best_obstacles = 20
		stats.mines_passed = 20
		progress["%s|%s" % [uid, date]] = stats

	func _dispatch(method: String, url: String, headers: PackedStringArray, body: String) -> Dictionary:
		if delay > 0.0:
			await host.get_tree().create_timer(delay).timeout
		var uid := _uid(headers)
		requests.append({"url": url, "body": body, "uid": uid})
		var hit := fault_url.is_empty() or url.contains(fault_url)
		if hit and (fault != "" or bad_json):
			var failing := fault
			var corrupt := bad_json
			if fault_once:
				fault = ""
				bad_json = false
				fault_once = false
			if commit_on_fault and failing != "":
				_apply_body(uid, url, body)
			if corrupt:
				return {"ok": false, "status": 200, "data": null, "error": "invalid_json", "godot_http_result": HTTPRequest.RESULT_SUCCESS}
			if failing == "offline":
				return _transport(HTTPRequest.RESULT_CANT_CONNECT)
			if failing == "timeout":
				return _transport(HTTPRequest.RESULT_TIMEOUT)
			if failing == "429":
				return _http(429)
			if failing == "500":
				return _http(500)
			if failing == "400":
				return _http(400)
		if uid.is_empty():
			unexpected += 1
			return _http(401)
		if url.contains("get_daily_missions"):
			if stall_board_once:
				stall_board_once = false
				var snapshot := board(uid)
				stalled = true
				while not release_stall:
					await host.get_tree().process_frame
				stalled = false
				release_stall = false
				return _ok(snapshot)
			return _ok(board(uid))
		if url.contains("claim_daily_mission"):
			claim_hits += 1
			var parsed: Variant = JSON.parse_string(body)
			var slot := ""
			if typeof(parsed) == TYPE_DICTIONARY:
				slot = str(parsed.get("p_slot", ""))
			return _ok(_claim(uid, slot))
		if url.contains("record_unlimited_mission_run"):
			if legacy_only and body.contains("p_dives_entered"):
				return {"ok": false, "status": 404, "data": {"code": "PGRST202", "message": "Could not find the function"}, "error": "http_404", "godot_http_result": HTTPRequest.RESULT_SUCCESS}
			var parsed_run: Variant = JSON.parse_string(body)
			if typeof(parsed_run) != TYPE_DICTIONARY:
				return _http(400)
			if not body.contains("p_dives_entered") and int(parsed_run.get("p_pipes", 0)) > 80:
				return _ok({"ok": false, "reason": "rejected", "accepted": false})
			var dive := {
				"dives_entered": int(parsed_run.get("p_dives_entered", 0)),
				"dives_completed": int(parsed_run.get("p_dives_completed", 0)),
				"dive_seconds": int(parsed_run.get("p_dive_seconds", 0)),
				"lane_changes": int(parsed_run.get("p_lane_changes", 0)),
				"lanes_left": int(parsed_run.get("p_lanes_left", 0)),
				"lanes_right": int(parsed_run.get("p_lanes_right", 0)),
				"obstacles": int(parsed_run.get("p_obstacles", 0)),
				"mines": int(parsed_run.get("p_mines", 0)),
			}
			return _ok(_record(uid, str(parsed_run.get("p_run_id", "")), int(parsed_run.get("p_pipes", 0)), int(parsed_run.get("p_seconds", 0)), int(parsed_run.get("p_gameplay_coins", 0)), dive))
		unexpected += 1
		return _ok({"ok": false, "reason": "ignored"})

	func _apply_body(uid: String, url: String, body: String) -> void:
		if uid.is_empty():
			return
		var parsed: Variant = JSON.parse_string(body)
		if typeof(parsed) != TYPE_DICTIONARY:
			return
		if url.contains("claim_daily_mission"):
			_claim(uid, str(parsed.get("p_slot", "")))
		elif url.contains("record_unlimited_mission_run"):
			_record(uid, str(parsed.get("p_run_id", "")), int(parsed.get("p_pipes", 0)), int(parsed.get("p_seconds", 0)), int(parsed.get("p_gameplay_coins", 0)), {
				"dives_entered": int(parsed.get("p_dives_entered", 0)),
				"dives_completed": int(parsed.get("p_dives_completed", 0)),
				"dive_seconds": int(parsed.get("p_dive_seconds", 0)),
				"lane_changes": int(parsed.get("p_lane_changes", 0)),
				"lanes_left": int(parsed.get("p_lanes_left", 0)),
				"lanes_right": int(parsed.get("p_lanes_right", 0)),
				"obstacles": int(parsed.get("p_obstacles", 0)),
				"mines": int(parsed.get("p_mines", 0)),
			})

	func board(uid: String) -> Dictionary:
		var date := today()
		var set_row: Dictionary = _ensure_set(date)
		var stats: Dictionary = progress.get("%s|%s" % [uid, date], _blank())
		var slots: Array = []
		var claimed_slots := 0
		for slot_name in ["easy", "medium", "hard"]:
			var mission: Dictionary = Missions.mission_by_id(int(set_row.get(slot_name, 0)))
			var judged: Dictionary = Missions.evaluate(str(mission.get("rule", "")), int(mission.get("goal", 0)), int(mission.get("goal_b", 0)), stats)
			var was := claims.has("%s|%s|%s" % [uid, date, slot_name])
			if was:
				claimed_slots += 1
			slots.append({
				"slot": slot_name,
				"mission_id": int(mission.get("id", 0)),
				"description": str(mission.get("description", "")),
				"reward": int(Missions.REWARDS.get(slot_name, 0)),
				"progress": int(judged.get("progress", 0)),
				"goal": int(judged.get("goal", 0)),
				"complete": bool(judged.get("complete", false)),
				"claimed": was,
			})
		var bonus_claimed := claims.has("%s|%s|bonus" % [uid, date])
		return {
			"ok": true,
			"mission_date": date,
			"server_now": now_unix,
			"resets_at": _resets_at(date),
			"mission_reward_coins": profile_coins(uid),
			"granted_now": 0,
			"slots": slots,
			"bonus": {
				"reward": 25,
				"progress": claimed_slots,
				"goal": 3,
				"unlocked": claimed_slots == 3,
				"complete": claimed_slots == 3 and not bonus_claimed,
				"claimed": bonus_claimed,
				"description": "COMPLETE ALL 3",
			},
		}

	func _claim(uid: String, slot: String) -> Dictionary:
		var date := today()
		if slot != "easy" and slot != "medium" and slot != "hard" and slot != "bonus":
			var bad := board(uid)
			bad["ok"] = false
			bad["reason"] = "bad_slot"
			bad["granted_now"] = 0
			return bad
		var reward := int(Missions.REWARDS.get(slot, 0))
		var complete := false
		if slot == "bonus":
			complete = claim_count(uid, date, "easy") + claim_count(uid, date, "medium") + claim_count(uid, date, "hard") == 3
		else:
			var row := {}
			for candidate in board(uid).get("slots", []):
				if str(candidate.get("slot", "")) == slot:
					row = candidate
			complete = bool(row.get("complete", false))
		if not complete:
			var denied := board(uid)
			denied["ok"] = false
			denied["reason"] = "incomplete"
			denied["granted_now"] = 0
			return denied
		var existing := 0
		for name in ["easy", "medium", "hard", "bonus"]:
			if claims.has("%s|%s|%s" % [uid, date, name]):
				existing += int(claims["%s|%s|%s" % [uid, date, name]])
		if existing + reward > 60:
			var capped := board(uid)
			capped["ok"] = false
			capped["reason"] = "cap"
			capped["granted_now"] = 0
			return capped
		var key := "%s|%s|%s" % [uid, date, slot]
		if claims.has(key):
			var already := board(uid)
			already["granted_now"] = 0
			already["reason"] = "already"
			return already
		claims[key] = reward
		var profile: Dictionary = profiles.get(uid, {"mission_reward_coins": 0})
		profile.mission_reward_coins = int(profile.get("mission_reward_coins", 0)) + reward
		profiles[uid] = profile
		var granted := board(uid)
		granted["granted_now"] = reward
		granted["reason"] = "claimed"
		return granted

	func _record(uid: String, run_id: String, pipes: int, seconds: int, coins: int, dive: Dictionary) -> Dictionary:
		var entered := int(dive.get("dives_entered", 0))
		if not Missions.valid_run_id(run_id) or not Missions.accept_run(pipes, seconds, coins, entered) or not Missions.accept_dive(pipes, dive):
			return {"ok": false, "reason": "rejected", "accepted": false}
		var run_key := "%s|%s" % [uid, run_id]
		if runs.has(run_key):
			var duplicate := board(uid)
			duplicate["reason"] = "duplicate"
			duplicate["accepted"] = false
			return duplicate
		runs[run_key] = true
		var date := today()
		var stats: Dictionary = progress.get("%s|%s" % [uid, date], _blank())
		stats.pipes_total = int(stats.pipes_total) + pipes
		stats.runs = int(stats.runs) + 1
		stats.best_pipes = maxi(int(stats.best_pipes), pipes)
		stats.best_seconds = maxi(int(stats.best_seconds), seconds)
		stats.gameplay_coins = int(stats.gameplay_coins) + coins
		if coins > 0:
			stats.coin_runs = int(stats.coin_runs) + 1
		var samples: Array = stats.run_pipes
		if samples.size() < 60:
			samples.append(pipes)
		stats.run_pipes = samples
		stats.dives_entered = int(stats.dives_entered) + entered
		stats.dives_completed = int(stats.dives_completed) + int(dive.get("dives_completed", 0))
		stats.best_dives = maxi(int(stats.best_dives), int(dive.get("dives_completed", 0)))
		stats.dive_seconds = int(stats.dive_seconds) + int(dive.get("dive_seconds", 0))
		stats.lane_changes = int(stats.lane_changes) + int(dive.get("lane_changes", 0))
		stats.lanes_left = int(stats.lanes_left) + int(dive.get("lanes_left", 0))
		stats.lanes_right = int(stats.lanes_right) + int(dive.get("lanes_right", 0))
		stats.obstacles_dodged = int(stats.obstacles_dodged) + int(dive.get("obstacles", 0))
		stats.best_obstacles = maxi(int(stats.best_obstacles), int(dive.get("obstacles", 0)))
		stats.mines_passed = int(stats.mines_passed) + int(dive.get("mines", 0))
		progress["%s|%s" % [uid, date]] = stats
		var recorded := board(uid)
		recorded["reason"] = "recorded"
		recorded["accepted"] = true
		return recorded

	func _ensure_set(date: String) -> Dictionary:
		if sets.has(date):
			return sets[date]
		var recent: Array = []
		for key in sets.keys():
			if str(key) >= date:
				continue
			recent.append(int(sets[key].easy))
			recent.append(int(sets[key].medium))
			recent.append(int(sets[key].hard))
		var picked: Dictionary = Missions.preview_rotation(date, recent)
		sets[date] = {"easy": int(picked.get("easy", 0)), "medium": int(picked.get("medium", 0)), "hard": int(picked.get("hard", 0))}
		return sets[date]

	func _resets_at(date: String) -> int:
		var parts := date.split("-")
		var year := int(parts[0])
		var month := int(parts[1])
		var day := int(parts[2])
		var noon := 0
		if zone == "utc":
			noon = Daily.unix_utc(year, month, day, 12, 0, 0)
			var nxt: Dictionary = Time.get_datetime_dict_from_unix_time(noon + 86400)
			return Daily.unix_utc(int(nxt.year), int(nxt.month), int(nxt.day), 0, 0, 0)
		noon = Daily.eastern_midnight_unix(year, month, day) + 12 * 3600
		var nxt_east: Dictionary = Time.get_datetime_dict_from_unix_time(noon + 86400)
		return Daily.eastern_midnight_unix(int(nxt_east.year), int(nxt_east.month), int(nxt_east.day))

	func _blank() -> Dictionary:
		return {
			"pipes_total": 0,
			"runs": 0,
			"best_pipes": 0,
			"best_seconds": 0,
			"gameplay_coins": 0,
			"coin_runs": 0,
			"run_pipes": [],
			"dives_entered": 0,
			"dives_completed": 0,
			"best_dives": 0,
			"dive_seconds": 0,
			"lane_changes": 0,
			"lanes_left": 0,
			"lanes_right": 0,
			"obstacles_dodged": 0,
			"best_obstacles": 0,
			"mines_passed": 0,
		}

	func _uid(headers: PackedStringArray) -> String:
		for header in headers:
			var text := str(header).strip_edges()
			if not text.to_lower().begins_with("authorization:"):
				continue
			var value := text.substr(text.find(":") + 1).strip_edges()
			if value.to_lower().begins_with("bearer "):
				return str(tokens.get(value.substr(7).strip_edges(), ""))
		return ""

	func _ok(data: Dictionary) -> Dictionary:
		return {"ok": true, "status": 200, "data": data, "error": "", "godot_http_result": HTTPRequest.RESULT_SUCCESS}

	func _http(status: int) -> Dictionary:
		return {"ok": false, "status": status, "data": {"message": "mock_%d" % status}, "error": "http_%d" % status, "godot_http_result": HTTPRequest.RESULT_SUCCESS}

	func _transport(code: int) -> Dictionary:
		return {"ok": false, "status": 0, "data": null, "error": "transport", "godot_http_result": code}
