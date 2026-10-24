extends SceneTree

# Local mock of the Supabase leaderboard / Daily Challenge RPCs.
# Never opens a socket and never writes a live score or attempt.
# Godot --headless --path . --script res://tools/test_leaderboard_backend.gd

const LeaderboardScript := preload("res://scripts/backend/leaderboard_repository.gd")
const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")
const DailyAttemptScript := preload("res://scripts/daily_attempt.gd")
const ClientScript := preload("res://scripts/backend/supabase_client.gd")

const PLAYER_A := "11111111-1111-4111-8111-111111111111"
const PLAYER_B := "22222222-2222-4222-8222-222222222222"
const TOKEN_A := "test-token-player-a"
const TOKEN_B := "test-token-player-b"

var _saved: Dictionary = {}
var _snap_ok := false
var mock: MockServer
var _passed := 0
var _failed := 0
var _warnings: PackedStringArray = PackedStringArray()


func _init() -> void:
	_snapshot_userdata()
	call_deferred("_run")


func _initialize() -> void:
	# Block any autoload request that starts before the mock is installed.
	# Pending score/attempt fields are cleared only until this process restores
	# the snapshot taken in _init.
	ProjectSettings.set_setting("network/http_proxy/host", "127.0.0.1")
	ProjectSettings.set_setting("network/http_proxy/port", 9)
	var session := ConfigFile.new()
	session.set_value("session", "access_token", "test-isolated-token")
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


func _run() -> void:
	var version := Engine.get_version_info()
	var version_text := "%s.%s.%s" % [version["major"], version["minor"], version["patch"]]
	print("[leaderboard-test] godot=%s status=%s" % [version_text, str(version.get("status", ""))])
	var backend := root.get_node_or_null("Backend")
	if backend == null:
		print("[leaderboard-test] FAIL backend_missing")
		_restore_userdata()
		quit(1)
		return
	mock = MockServer.new(backend)
	backend.call("cancel_pre_match_requests")
	_drop_live_http(backend)
	backend._client = mock
	for _i in 8:
		await process_frame
	_drop_live_http(backend)
	if not await _wait_quiet(backend, 1500):
		_warn("Bootstrap left followup=%s share=%s. Live HTTP was cancelled and the mock took over. This is the test harness, not a leaderboard failure." % [backend._followup_busy, backend._share_reward_busy])
		backend._followup_busy = false
		backend._mission_busy = false
		backend._share_reward_busy = false
		backend._lb_busy = false
		backend._lb_needs_refresh = false
		backend._finalize_running = false
		backend._daily_busy = false
		backend._busy = false
		backend._refresh_busy = false
	_install(backend, TOKEN_A, PLAYER_A)
	mock.requests.clear()
	mock.unexpected = 0
	_check("godot_version", version_text == "4.7.2", version_text)
	await _test_contract()
	await _test_daily_submission(backend)
	await _test_daily_personal_best(backend)
	await _test_unlimited_submission(backend)
	await _test_ranking_display(backend)
	await _test_immediate_visibility(backend)
	await _test_historical_mismatch(backend)
	await _test_attempts(backend)
	await _test_cross_device(backend)
	await _test_network(backend)
	await _test_out_of_order(backend)
	_warn_local_mirror()
	var restored := _restore_userdata()
	_check("userdata_restored", restored, "snapshot_ok=%s" % _snap_ok)
	print("[leaderboard-test] scenarios=%d passed=%d failed=%d warnings=%d" % [_passed + _failed, _passed, _failed, _warnings.size()])
	for warning in _warnings:
		print("[leaderboard-test] WARN %s" % warning)
	print("[leaderboard-test] ok=%s" % (_failed == 0))
	quit(0 if _failed == 0 else 1)


func _check(name: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passed += 1
		print("[leaderboard-test] %s=pass" % name)
	else:
		_failed += 1
		print("[leaderboard-test] %s=FAIL %s" % [name, detail])


func _warn(text: String) -> void:
	_warnings.append(text)


func _gs():
	return root.get_node("GameSession")


func _install(backend, token: String, uid: String) -> void:
	mock.tokens[token] = uid
	backend.auth.access_token = token
	backend.auth.user_id = uid
	backend.auth.refresh_token = ""
	backend.auth.expires_at = int(Time.get_unix_time_from_system()) + 7200


func _reset(backend) -> void:
	if mock.stalled:
		mock.release_stall = true
		var guard := 0
		while mock.stalled and guard < 30:
			await process_frame
			guard += 1
	mock.reset_data()
	mock.now_unix = DailyChallengeScript.unix_utc(2026, 10, 12, 15)
	mock.publish_zone = "eastern"
	mock.query_zone = "eastern"
	mock.delay = 0.0
	backend.global_daily = []
	backend.global_weekly = []
	backend.global_monthly = []
	backend.leaderboard_meta = {}
	backend.daily_submit_error = ""
	backend._lb_needs_refresh = false
	backend._lb_period_date = ""
	backend._lb_checked_date = ""
	_gs().pending_claim_key = ""
	_gs().pending_finalize_attempt = ""
	_gs().pending_finalize_score = 0
	_gs().pending_finalize_name = ""
	_gs().pending_unlimited_score = 0
	_gs().pending_unlimited_name = ""
	_gs().match_mode = ""
	_gs().practice_daily = false
	_gs().active_challenge = {}
	_install(backend, TOKEN_A, PLAYER_A)


func _drop_live_http(backend: Node) -> void:
	var pending: Array = []
	for child in backend.get_children():
		if child is HTTPRequest:
			pending.append(child)
	for child in pending:
		var http := child as HTTPRequest
		http.cancel_request()
		http.queue_free()


func _busy_text(backend) -> String:
	return "followup=%s mission=%s share=%s lb=%s refresh_needed=%s finalize=%s daily=%s auth=%s token=%s stalled=%s" % [
		backend._followup_busy,
		backend._mission_busy,
		backend._share_reward_busy,
		backend._lb_busy,
		backend._lb_needs_refresh,
		backend._finalize_running,
		backend._daily_busy,
		backend._busy,
		backend._refresh_busy,
		mock.stalled,
	]


func _wait_quiet(backend, limit_ms: int = 8000) -> bool:
	var started := Time.get_ticks_msec()
	var stable := 0
	while Time.get_ticks_msec() - started < limit_ms:
		var quiet: bool = (
			not bool(backend._busy)
			and not backend._followup_busy
			and not backend._lb_busy
			and not backend._lb_needs_refresh
			and not backend._finalize_running
			and not backend._daily_busy
			and not backend._mission_busy
			and not backend._share_reward_busy
			and not backend._refresh_busy
			and not mock.stalled
		)
		if quiet:
			stable += 1
			if stable >= 3:
				return true
		else:
			stable = 0
		await process_frame
	print("[leaderboard-test] still_busy %s" % _busy_text(backend))
	return false


func _shown(backend, period: String) -> PackedStringArray:
	var raw: Variant = backend.global_monthly
	if period == "daily":
		raw = backend.global_daily
	elif period == "weekly":
		raw = backend.global_weekly
	var out := PackedStringArray()
	if not (raw is Array):
		return out
	for row in raw:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var name: String = _gs().clamp_player_name(str(row.get("name", row.get("display_name", "")))).to_upper()
		if name == "<NULL>" or name == "NULL":
			name = ""
		var value := int(row.get("score", 0))
		var score: String = str(value) if value > 0 else ""
		if name == "" and score == "":
			continue
		out.append("%s %s" % [name, score])
	return out


func _note(backend, period: String) -> String:
	var rows := _shown(backend, period)
	var meta: Dictionary = {}
	var got: Variant = backend.leaderboard_meta.get(period, {})
	if typeof(got) == TYPE_DICTIONARY:
		meta = got
	var submit_error: String = str(backend.daily_submit_error) if period == "daily" else ""
	if not meta.is_empty() and not bool(meta.get("ok", false)) and not backend.leaderboard_busy():
		return "COULD NOT LOAD SCORES"
	if submit_error != "":
		return "SCORE NOT SAVED"
	if rows.is_empty() and (meta.is_empty() or backend.leaderboard_busy()):
		return "LOADING"
	return ""


func _joined(lines: PackedStringArray) -> String:
	return ", ".join(lines)


func _sql(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _between(source: String, start: String, end: String) -> String:
	var at := source.find(start)
	if at < 0:
		return ""
	var stop := source.find(end, at + start.length())
	if stop < 0:
		return source.substr(at)
	return source.substr(at, stop - at)


func _request(url_suffix: String, which: int = -1) -> Dictionary:
	var seen := 0
	var found := {}
	for row in mock.requests:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if not str(row.get("url", "")).ends_with(url_suffix):
			continue
		found = row
		if which < 0:
			continue
		if seen == which:
			return row
		seen += 1
	return found if which < 0 else {}


func _keys_exact(row: Dictionary, expected: Array) -> bool:
	var parsed: Variant = row.get("json", {})
	if typeof(parsed) != TYPE_DICTIONARY or parsed.size() != expected.size():
		return false
	for key in expected:
		if not parsed.has(key):
			return false
	return true


func _test_contract() -> void:
	var split := _sql("res://tools/supabase/leaderboard_split.sql")
	var attempt := _sql("res://tools/supabase/daily_attempt.sql")
	var midnight := _sql("res://tools/supabase/daily_midnight.sql")
	var utc_file := _sql("res://tools/supabase/daily_leaderboard_utc.sql")
	var start_fix := _sql("res://tools/supabase/daily_start_fix.sql")
	var leaderboard := _sql("res://tools/supabase/leaderboard.sql")
	var repo = LeaderboardScript.new()
	var daily_branch := "when p_period = 'daily' then pg_catalog.to_char(pg_catalog.timezone('America/New_York', pg_catalog.now()), 'YYYY-MM-DD')"
	var utc_branch := "when p_period = 'daily' then pg_catalog.to_char((pg_catalog.timezone('utc', pg_catalog.now()))::date, 'YYYY-MM-DD')"
	var publish_eastern := "v_day date := (pg_catalog.timezone('America/New_York', pg_catalog.now()))::date;"
	var finalize_at := split.find("function public.finalize_daily_attempt")
	var finalize_head := split.substr(finalize_at, 500)
	_check(
		"contract_rpc_signatures",
		finalize_at >= 0
		and finalize_head.find("p_attempt_id uuid") >= 0
		and finalize_head.find("p_score integer") >= 0
		and finalize_head.find("p_display_name text") >= 0
		and split.find("submit_leaderboard_score(p_score integer, p_display_name text)") >= 0
		and split.find("get_leaderboard(p_period text)") >= 0
		and split.find("returns table (display_name text, score integer)") >= 0
		and attempt.find("claim_daily_attempt(p_idempotency_key uuid)") >= 0
		and attempt.find("start_daily_attempt(p_attempt_id uuid)") >= 0
		and attempt.find("get_daily_attempt_status(p_idempotency_key uuid default null)") >= 0
		and str(repo.claim_url()).ends_with("/rest/v1/rpc/claim_daily_attempt")
		and str(repo.finalize_url()).ends_with("/rest/v1/rpc/finalize_daily_attempt")
		and str(repo.submit_url()).ends_with("/rest/v1/rpc/submit_leaderboard_score")
		and str(repo.list_url()).ends_with("/rest/v1/rpc/get_leaderboard")
	)
	var finalize_body := _between(split, "function public.finalize_daily_attempt", "function public.submit_leaderboard_score")
	var submit_body := _between(split, "function public.submit_leaderboard_score", "function public.get_leaderboard")
	_check(
		"contract_daily_timezone",
		split.find(daily_branch) >= 0
		and split.find(utc_branch) < 0
		and midnight.find(daily_branch) >= 0
		and midnight.find(publish_eastern) >= 0
		and attempt.find(publish_eastern) >= 0
		and finalize_body.find("'daily'") >= 0
		and finalize_body.find("'weekly'") < 0
		and finalize_body.find("'monthly'") < 0
		and submit_body.find("'weekly'") >= 0
		and submit_body.find("'monthly'") >= 0
		and submit_body.find("'daily'") < 0
		and submit_body.find("timezone('utc'") >= 0
	)
	_check(
		"contract_uniqueness_and_rls",
		attempt.find("leaderboard_scores_daily_period") >= 0
		and attempt.find("leaderboard_scores_unlimited_period") >= 0
		and attempt.find("daily_attempts_player_challenge unique (player_id, challenge_id)") >= 0
		and attempt.find("alter table public.daily_attempts enable row level security") >= 0
		and leaderboard.find("alter table public.leaderboard_scores enable row level security") >= 0
		and leaderboard.find("grant select on table public.leaderboard_scores to authenticated") >= 0
		and leaderboard.find("revoke all on table public.leaderboard_scores from public, anon, authenticated") >= 0
		and leaderboard.find("grant insert on table public.leaderboard_scores") < 0
		and split.find("grant execute on function public.get_leaderboard(text) to authenticated") >= 0
		and split.find("security definer") >= 0
	)
	_check(
		"contract_identity_is_auth_uid",
		finalize_body.find("auth.uid()") >= 0
		and finalize_body.find("p_player_id") < 0
		and submit_body.find("auth.uid()") >= 0
		and submit_body.find("p_player_id") < 0
		and attempt.find("uid uuid := auth.uid()") >= 0
	)
	_check(
		"contract_utc_file_is_not_the_live_rule",
		utc_file.find("Do not apply this file") >= 0
		and utc_file.find(utc_branch) >= 0
		and start_fix.find("This file has not been executed") >= 0
		and start_fix.find("timezone('utc', pg_catalog.now())") >= 0
	)
	if start_fix.find("timezone('utc', pg_catalog.now())") >= 0:
		_warn("daily_start_fix.sql would republish the challenge on the UTC date. Its header says it has not been executed. Applying it after the Eastern functions would recreate the next-day leaderboard gap.")
	var backend_src := _sql("res://autoload/backend.gd")
	var menu_src := _sql("res://scenes/menu/main_menu.gd")
	var finalize_fn := _between(backend_src, "func finalize_daily_attempt", "func _set_daily_submit_error")
	var submit_fn := _between(backend_src, "func submit_unlimited_score", "func _fetch_leaderboards")
	var choose := _between(menu_src, "func _choose_daily", "func _begin_claimed_game")
	_check(
		"contract_client_refresh_and_menu",
		finalize_fn.find("fetch_leaderboards()") >= 0
		and finalize_fn.find("\"p_attempt_id\"") >= 0
		and finalize_fn.find("\"p_player_id\"") < 0
		and submit_fn.find("fetch_leaderboards()") >= 0
		and submit_fn.find("\"p_score\"") >= 0
		and submit_fn.find("\"p_player_id\"") < 0
		and menu_src.find("global_daily") >= 0
		and menu_src.find("func _fill_scores") >= 0
		and choose.find("if _mode_busy") >= 0
	)


func _test_daily_submission(backend) -> void:
	await _reset(backend)
	var claim: Dictionary = await backend.claim_daily_attempt()
	var challenge: Dictionary = claim.get("challenge", {})
	var started: Dictionary = await backend.start_daily_attempt(str(challenge.get("attempt_id", "")))
	_gs().player_name = "reef"
	_gs().player_id = PLAYER_B
	_gs().begin_claimed_daily(challenge)
	_gs().record_run(27, 1, 1)
	var quiet := await _wait_quiet(backend)
	var finalize := _request("/finalize_daily_attempt")
	var listed := _request("/get_leaderboard")
	var shown := _shown(backend, "daily")
	_check(
		"daily_submission_request",
		quiet
		and bool(claim.get("ok", false))
		and bool(started.get("started", false))
		and _keys_exact(finalize, ["p_attempt_id", "p_score", "p_display_name"])
		and str(finalize.get("json", {}).get("p_attempt_id", "")) == str(challenge.get("attempt_id", ""))
		and int(finalize.get("json", {}).get("p_score", 0)) == 27
		and str(finalize.get("json", {}).get("p_display_name", "")) == "REEF"
		and str(finalize.get("uid", "")) == PLAYER_A
		and str(finalize.get("uid", "")) != _gs().player_id
		and _keys_exact(listed, ["p_period"])
		and int(mock.count_scores(PLAYER_A, "daily")) == 1
		and int(mock.count_scores(PLAYER_B, "daily")) == 0,
		"quiet=%s player=%s shown=%s uid=%s body=%s" % [quiet, str(_gs().player_id), shown, str(finalize.get("uid", "")), str(finalize.get("body", ""))]
	)
	_check(
		"daily_score_display",
		_joined(shown) == "REEF 27"
		and _joined(_shown(backend, "weekly")) == ""
		and _joined(_shown(backend, "monthly")) == ""
		and str(backend.daily_submit_error) == ""
		and _note(backend, "daily") == ""
		and int(finalize.get("seq", -1)) < int(listed.get("seq", -1)),
		"daily=%s weekly=%s note=%s error=%s" % [shown, _shown(backend, "weekly"), _note(backend, "daily"), backend.daily_submit_error]
	)


func _test_daily_personal_best(backend) -> void:
	await _reset(backend)
	mock.seed_daily(PLAYER_A, "old", 10)
	var low: Dictionary = await _play_daily(backend, 27, "REEF")
	_check(
		"daily_higher_replaces_lower",
		bool(low.get("ok", false)) and _joined(_shown(backend, "daily")) == "REEF 27" and mock.count_scores(PLAYER_A, "daily") == 1,
		str(_shown(backend, "daily"))
	)
	await _reset(backend)
	mock.seed_daily(PLAYER_A, "old", 50)
	var high: Dictionary = await _play_daily(backend, 20, "REEF")
	_check(
		"daily_lower_keeps_personal_best",
		bool(high.get("ok", false)) and _joined(_shown(backend, "daily")) == "OLD 50" and mock.count_scores(PLAYER_A, "daily") == 1,
		str(_shown(backend, "daily"))
	)
	await _reset(backend)
	var first: Dictionary = await _play_daily(backend, 18, "REEF")
	var attempt_id := str(_gs().active_challenge.get("attempt_id", ""))
	await backend.finalize_daily_attempt(attempt_id, 40, "REEF")
	var quiet := await _wait_quiet(backend)
	_check(
		"daily_duplicate_finalize_one_row",
		quiet and bool(first.get("ok", false)) and _joined(_shown(backend, "daily")) == "REEF 18" and mock.count_scores(PLAYER_A, "daily") == 1 and mock.attempt_count(PLAYER_A) == 1,
		str(_shown(backend, "daily"))
	)


func _test_unlimited_submission(backend) -> void:
	await _reset(backend)
	mock.now_unix = DailyChallengeScript.unix_utc(2026, 10, 21, 0, 12)
	_gs().player_name = "longname"
	_gs().player_id = PLAYER_B
	_gs().start_match(_gs().MODE_UNLIMITED)
	_gs().record_run(40, 1, 1)
	if not await _wait_quiet(backend):
		_check("weekly_submission_request", false, "not quiet after first submit")
		return
	_gs().player_name = "kelp"
	_gs().record_run(12, 2, 1)
	if not await _wait_quiet(backend):
		_check("weekly_submission_request", false, "not quiet after lower submit")
		return
	var lower := _request("/submit_leaderboard_score")
	var mid_week := _joined(_shown(backend, "weekly"))
	var mid_month := _joined(_shown(backend, "monthly"))
	_gs().player_name = "eel"
	_gs().record_run(55, 1, 1)
	var quiet := await _wait_quiet(backend)
	var last := _request("/submit_leaderboard_score")
	var week_key := DailyChallengeScript.week_key(DailyChallengeScript.utc_date_from_unix(mock.now_unix))
	_check(
		"weekly_submission_request",
		quiet
		and _keys_exact(last, ["p_score", "p_display_name"])
		and int(last.get("json", {}).get("p_score", 0)) == 55
		and str(last.get("json", {}).get("p_display_name", "")) == "EEL"
		and str(last.get("uid", "")) == PLAYER_A
		and str(mock.period_key_of(PLAYER_A, "weekly")) == week_key
		and week_key == "2026-10-19"
		and mock.count_scores(PLAYER_A, "weekly") == 1,
		"body=%s key=%s" % [str(last.get("body", "")), mock.period_key_of(PLAYER_A, "weekly")]
	)
	_check(
		"weekly_score_display",
		_joined(_shown(backend, "weekly")) == "EEL 55" and _joined(_shown(backend, "daily")) == "",
		"weekly=%s daily=%s lower_body=%s" % [_shown(backend, "weekly"), _shown(backend, "daily"), str(lower.get("body", ""))]
	)
	_check(
		"monthly_submission_and_display",
		str(mock.period_key_of(PLAYER_A, "monthly")) == "2026-10"
		and mock.count_scores(PLAYER_A, "monthly") == 1
		and _joined(_shown(backend, "monthly")) == "EEL 55"
		and _keys_exact(_request("/get_leaderboard"), ["p_period"]),
		str(_shown(backend, "monthly"))
	)
	# The lower 12-point submit is the middle request. Replay that state by walking the stored rule:
	# after 40 then 12, the board must have stayed 40 while taking the new name, then 55 replaced both.
	_check(
		"unlimited_lower_does_not_replace_score",
		int(lower.get("json", {}).get("p_score", 0)) == 12
		and str(lower.get("json", {}).get("p_display_name", "")) == "KELP"
		and mid_week == "KELP 40"
		and mid_month == "KELP 40"
		and int(mock.score_of(PLAYER_A, "weekly")) == 55
		and int(mock.score_of(PLAYER_A, "monthly")) == 55,
		"lower=%s mid_week=%s mid_month=%s stored=%s" % [str(lower.get("json", {})), mid_week, mid_month, mock.score_of(PLAYER_A, "weekly")]
	)


func _test_ranking_display(backend) -> void:
	await _reset(backend)
	mock.seed_daily(PLAYER_A, "tiea", 40)
	mock.seed_daily(PLAYER_B, "tieb", 40)
	var extra := [
		["33333333-3333-4333-8333-333333333333", "high", 90],
		["44444444-4444-4444-8444-444444444444", "fish30", 30],
		["55555555-5555-4555-8555-555555555555", "fish29", 29],
		["66666666-6666-4666-8666-666666666666", "fish28", 28],
		["77777777-7777-4777-8777-777777777777", "fish27", 27],
		["88888888-8888-4888-8888-888888888888", "fish26", 26],
		["99999999-9999-4999-8999-999999999999", "fish25", 25],
		["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "fish24", 24],
		["bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "fish23", 23],
		["cccccccc-cccc-4ccc-8ccc-cccccccccccc", "low", 1],
		["dddddddd-dddd-4ddd-8ddd-dddddddddddd", "zzzz", 2],
	]
	for row in extra:
		mock.tokens[str(row[0])] = str(row[0])
		mock.seed_daily(str(row[0]), str(row[1]), int(row[2]))
	backend.fetch_leaderboards()
	var quiet := await _wait_quiet(backend)
	var shown := _shown(backend, "daily")
	var expected := "HIGH 90, TIEA 40, TIEB 40, FISH30 30, FISH29 29, FISH28 28, FISH27 27, FISH26 26, FISH25 25, FISH24 24"
	var blob := _joined(shown)
	var parsed: Array = LeaderboardScript.new().parse_rows([{
		"display_name": "11111111-1111-4111-8111-111111111111",
		"score": 77,
	}])
	var parsed_name := ""
	if not parsed.is_empty() and typeof(parsed[0]) == TYPE_DICTIONARY:
		parsed_name = str(parsed[0].get("name", "x"))
	_check(
		"ranking_sort_limit_and_names",
		quiet and blob == expected and shown.size() == 10 and blob.find("FISH23") < 0 and blob.find("LOW") < 0 and blob.find("ZZZZ") < 0 and parsed_name == "" and int(parsed[0].get("score", 0)) == 77,
		blob
	)


func _test_immediate_visibility(backend) -> void:
	await _reset(backend)
	mock.now_unix = DailyChallengeScript.unix_utc(2026, 10, 21, 0, 12)
	var eastern := DailyChallengeScript.challenge_date_from_unix(mock.now_unix)
	var utc := DailyChallengeScript.utc_date_from_unix(mock.now_unix)
	var played: Dictionary = await _play_daily(backend, 27, "REEF")
	var finalize := _request("/finalize_daily_attempt")
	var listed := _request("/get_leaderboard")
	var gets_after := 0
	for row in mock.requests:
		if str(row.get("url", "")).ends_with("/get_leaderboard") and str(row.get("json", {}).get("p_period", "")) == "daily" and int(row.get("seq", -1)) > int(finalize.get("seq", 999999)):
			gets_after += 1
	_check(
		"immediate_daily_visibility",
		bool(played.get("ok", false))
		and eastern == "2026-10-20"
		and utc == "2026-10-21"
		and mock.period_key_of(PLAYER_A, "daily") == "2026-10-20"
		and gets_after >= 1
		and _joined(_shown(backend, "daily")) == "REEF 27"
		and str(backend.daily_submit_error) == ""
		and _note(backend, "daily") == ""
		and bool(listed.get("json", {}) is Dictionary),
		"eastern=%s utc=%s stored=%s shown=%s gets_after=%d error=%s system=%s" % [
			eastern,
			utc,
			mock.period_key_of(PLAYER_A, "daily"),
			_shown(backend, "daily"),
			gets_after,
			backend.daily_submit_error,
			Time.get_date_string_from_system(),
		]
	)


func _test_historical_mismatch(backend) -> void:
	await _reset(backend)
	mock.publish_zone = "utc"
	mock.query_zone = "eastern"
	mock.now_unix = DailyChallengeScript.unix_utc(2026, 10, 21, 0, 12)
	var played: Dictionary = await _play_daily(backend, 27, "REEF")
	var hidden := _joined(_shown(backend, "daily")) == ""
	var stored := mock.period_key_of(PLAYER_A, "daily")
	mock.now_unix = DailyChallengeScript.eastern_midnight_unix(2026, 10, 21) + 60
	backend.fetch_leaderboards()
	var quiet := await _wait_quiet(backend)
	_check(
		"historical_mismatch_hidden_then_next_eastern_day",
		bool(played.get("ok", false))
		and stored == "2026-10-21"
		and hidden
		and quiet
		and _joined(_shown(backend, "daily")) == "REEF 27",
		"stored=%s hidden=%s later=%s" % [stored, hidden, _shown(backend, "daily")]
	)


func _test_attempts(backend) -> void:
	await _reset(backend)
	var status: Dictionary = await backend.fetch_daily_attempt_status()
	_check(
		"attempt_status_does_not_claim",
		bool(status.get("ok", false)) and not bool(status.get("attempted", true)) and mock.attempt_count(PLAYER_A) == 0,
		str(status)
	)
	var first_task = backend.claim_daily_attempt()
	var second_task = backend.claim_daily_attempt()
	var first: Dictionary = await first_task
	var second: Dictionary = await second_task
	var attempt_id := str(first.get("challenge", {}).get("attempt_id", ""))
	var start_one = backend.start_daily_attempt(attempt_id)
	var start_two = backend.start_daily_attempt(attempt_id)
	var started: Dictionary = await start_one
	var again: Dictionary = await start_two
	_check(
		"attempt_rapid_tap_one_row",
		bool(first.get("ok", false))
		and bool(second.get("ok", false))
		and str(second.get("challenge", {}).get("attempt_id", "")) == attempt_id
		and mock.attempt_count(PLAYER_A) == 1
		and bool(started.get("started", false))
		and not bool(again.get("started", true))
		and bool(again.get("already_started", false)),
		"first=%s second=%s start=%s again=%s count=%d" % [first.get("ok"), second.get("ok"), started, again, mock.attempt_count(PLAYER_A)]
	)
	await backend.finalize_daily_attempt(attempt_id, 15, "REEF")
	if not await _wait_quiet(backend):
		_check("attempt_restart_cannot_bypass", false, "not quiet after finalize")
		return
	_gs().pending_claim_key = ""
	var bypass: Dictionary = await backend.claim_daily_attempt()
	_check(
		"attempt_restart_cannot_bypass",
		str(backend.daily_submit_error) == ""
		and _joined(_shown(backend, "daily")) == "REEF 15"
		and mock.finalized_count(PLAYER_A) == 1
		and bool(bypass.get("already_used", false))
		and not bool(bypass.get("ok", true))
		and mock.attempt_count(PLAYER_A) == 1,
		"bypass=%s attempts=%d shown=%s error=%s" % [bypass, mock.attempt_count(PLAYER_A), _shown(backend, "daily"), backend.daily_submit_error]
	)
	_install(backend, TOKEN_B, PLAYER_B)
	var other: Dictionary = await backend.claim_daily_attempt()
	_check(
		"attempt_other_player_independent",
		bool(other.get("ok", false)) and mock.attempt_count(PLAYER_B) == 1 and mock.attempt_count(PLAYER_A) == 1,
		str(other)
	)
	_install(backend, TOKEN_A, PLAYER_A)
	mock.now_unix = DailyChallengeScript.eastern_midnight_unix(2026, 10, 13) + 120
	var tomorrow: Dictionary = await backend.claim_daily_attempt()
	_check(
		"attempt_available_next_eastern_day",
		bool(tomorrow.get("ok", false))
		and str(tomorrow.get("challenge", {}).get("challenge_date", "")) == "2026-10-13"
		and mock.attempt_count(PLAYER_A) == 2,
		str(tomorrow.get("challenge", {}))
	)
	await _reset(backend)
	mock.fault = "500"
	var failed: Dictionary = await backend.claim_daily_attempt()
	var claim_requests := 0
	for row in mock.requests:
		if str(row.get("url", "")).ends_with("/claim_daily_attempt"):
			claim_requests += 1
	_check(
		"attempt_server_error_does_not_consume",
		not bool(failed.get("ok", true))
		and not bool(failed.get("already_used", true))
		and mock.attempt_count(PLAYER_A) == 0
		and claim_requests == 3
		and _gs().pending_claim_key != "",
		"status=%s requests=%d key=%s" % [failed.get("status"), claim_requests, _gs().pending_claim_key]
	)
	mock.fault = ""
	mock.requests.clear()
	mock.fault = "400"
	mock.fault_once = true
	var rejected: Dictionary = await backend.claim_daily_attempt()
	_check(
		"attempt_client_error_clears_key",
		not bool(rejected.get("ok", true)) and _gs().pending_claim_key == "" and mock.attempt_count(PLAYER_A) == 0,
		"key=%s result=%s" % [_gs().pending_claim_key, rejected]
	)


func _test_cross_device(backend) -> void:
	await _reset(backend)
	var a: Dictionary = await _play_daily(backend, 27, "REEF")
	_install(backend, TOKEN_B, PLAYER_B)
	var b: Dictionary = await _play_daily(backend, 40, "CORAL")
	var board_b := _joined(_shown(backend, "daily"))
	_install(backend, TOKEN_A, PLAYER_A)
	backend.fetch_leaderboards()
	var quiet := await _wait_quiet(backend)
	var board_a := _joined(_shown(backend, "daily"))
	var periods := PackedStringArray()
	for row in mock.requests:
		if str(row.get("url", "")).ends_with("/get_leaderboard") and str(row.get("json", {}).get("p_period", "")) == "daily":
			periods.append(str(row.get("json", {}).get("p_period", "")))
	_check(
		"cross_device_same_board",
		quiet
		and bool(a.get("ok", false))
		and bool(b.get("ok", false))
		and board_a == "CORAL 40, REEF 27"
		and board_b == board_a
		and mock.player_for_name("daily", "REEF") == PLAYER_A
		and mock.player_for_name("daily", "CORAL") == PLAYER_B
		and periods.size() >= 2,
		"a=%s b=%s" % [board_a, board_b]
	)
	var forged := JSON.stringify({
		"p_score": 99,
		"p_display_name": "HACK",
		"p_player_id": PLAYER_A,
	})
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % TOKEN_B,
	])
	var spoof: Dictionary = await mock.request_json_independent("POST", LeaderboardScript.new().submit_url(), headers, forged)
	_check(
		"cross_device_ignores_foreign_player_id",
		bool(spoof.get("ok", false))
		and mock.player_for_name("weekly", "HACK") == PLAYER_B
		and mock.player_for_name("weekly", "HACK") != PLAYER_A,
		"hack_owner=%s" % mock.player_for_name("weekly", "HACK")
	)
	_warn("Live JWT verification and Row Level Security were not executed. The client never sends a player id; the mock, like the SQL, attributes the write to the bearer token. A stolen access token could still act as that user.")


func _test_network(backend) -> void:
	await _reset(backend)
	var played: Dictionary = await _play_daily(backend, 27, "REEF")
	backend.global_daily = [{"name": "KEEP", "score": 4, "display_name": "KEEP"}]
	mock.fault = "offline"
	backend.fetch_leaderboards()
	var offline_quiet := await _wait_quiet(backend)
	var kept := _joined(_shown(backend, "daily"))
	_check(
		"network_offline_keeps_board",
		bool(played.get("ok", false)) and offline_quiet and kept == "KEEP 4" and _note(backend, "daily") == "COULD NOT LOAD SCORES",
		"shown=%s note=%s" % [kept, _note(backend, "daily")]
	)
	mock.fault = ""
	backend.fetch_leaderboards()
	var restored := await _wait_quiet(backend)
	_check(
		"network_restored_shows_score",
		restored and _joined(_shown(backend, "daily")) == "REEF 27" and _note(backend, "daily") == "",
		str(_shown(backend, "daily"))
	)
	mock.fault = "timeout"
	backend.global_daily = [{"name": "KEEP", "score": 4, "display_name": "KEEP"}]
	backend.fetch_leaderboards()
	var timeout_quiet := await _wait_quiet(backend)
	mock.fault = ""
	_check(
		"network_timeout",
		timeout_quiet and _joined(_shown(backend, "daily")) == "KEEP 4" and _note(backend, "daily") == "COULD NOT LOAD SCORES",
		str(_shown(backend, "daily"))
	)
	await _reset(backend)
	var ready: Dictionary = await _claim_and_start(backend)
	mock.fault = "429"
	mock.fault_once = true
	_gs().pending_finalize_attempt = str(ready.get("attempt_id", ""))
	_gs().pending_finalize_score = 27
	_gs().pending_finalize_name = "REEF"
	await backend.finalize_daily_attempt(str(ready.get("attempt_id", "")), 27, "REEF")
	var limited := await _wait_quiet(backend)
	_check(
		"network_429_not_shown_as_saved",
		limited
		and mock.count_scores(PLAYER_A, "daily") == 0
		and _joined(_shown(backend, "daily")) == ""
		and str(backend.daily_submit_error) != ""
		and _note(backend, "daily") == "SCORE NOT SAVED"
		and _gs().pending_finalize_attempt == str(ready.get("attempt_id", "")),
		"error=%s pending=%s" % [backend.daily_submit_error, _gs().pending_finalize_attempt]
	)
	mock.fault = ""
	backend.on_menu_ready()
	var retried := await _wait_quiet(backend)
	_check(
		"network_429_retry_one_row",
		retried and _joined(_shown(backend, "daily")) == "REEF 27" and mock.count_scores(PLAYER_A, "daily") == 1 and _gs().pending_finalize_attempt == "",
		"shown=%s rows=%d pending=%s" % [_shown(backend, "daily"), mock.count_scores(PLAYER_A, "daily"), _gs().pending_finalize_attempt]
	)
	await _reset(backend)
	ready = await _claim_and_start(backend)
	mock.fault = "500"
	mock.fault_once = true
	mock.commit_on_fault = true
	await backend.finalize_daily_attempt(str(ready.get("attempt_id", "")), 27, "REEF")
	var failed_store := await _wait_quiet(backend)
	_check(
		"network_500_not_shown_until_confirmed",
		failed_store
		and mock.count_scores(PLAYER_A, "daily") == 1
		and _joined(_shown(backend, "daily")) == ""
		and str(backend.daily_submit_error) != "",
		"shown=%s error=%s rows=%d" % [_shown(backend, "daily"), backend.daily_submit_error, mock.count_scores(PLAYER_A, "daily")]
	)
	await backend.finalize_daily_attempt(str(ready.get("attempt_id", "")), 27, "REEF")
	var confirmed := await _wait_quiet(backend)
	_check(
		"network_500_retry_no_duplicate",
		confirmed and _joined(_shown(backend, "daily")) == "REEF 27" and mock.count_scores(PLAYER_A, "daily") == 1,
		str(_shown(backend, "daily"))
	)
	await _reset(backend)
	ready = await _claim_and_start(backend)
	mock.fault = "bad_json"
	mock.fault_once = true
	await backend.finalize_daily_attempt(str(ready.get("attempt_id", "")), 27, "REEF")
	var bad := await _wait_quiet(backend)
	_check(
		"network_bad_json",
		bad and mock.count_scores(PLAYER_A, "daily") == 0 and _joined(_shown(backend, "daily")) == "" and str(backend.daily_submit_error) != "",
		"error=%s" % backend.daily_submit_error
	)
	mock.fault = ""
	mock.force_empty_get = true
	backend.daily_submit_error = ""
	backend.global_daily = [{"name": "KEEP", "score": 4, "display_name": "KEEP"}]
	backend.fetch_leaderboards()
	var empty_quiet := await _wait_quiet(backend)
	_check(
		"network_empty_leaderboard",
		empty_quiet and _shown(backend, "daily").is_empty() and _note(backend, "daily") == "" and bool(backend.leaderboard_meta.get("daily", {}).get("ok", false)),
		"note=%s meta=%s" % [_note(backend, "daily"), backend.leaderboard_meta.get("daily", {})]
	)
	mock.force_empty_get = false
	backend.global_daily = [{"name": "KEEP", "score": 4, "display_name": "KEEP"}]
	mock.force_null_get = true
	backend.fetch_leaderboards()
	var null_quiet := await _wait_quiet(backend)
	_check(
		"network_malformed_payload_keeps_old",
		null_quiet and _joined(_shown(backend, "daily")) == "KEEP 4" and _note(backend, "daily") == "COULD NOT LOAD SCORES",
		str(_shown(backend, "daily"))
	)
	mock.force_null_get = false
	mock.delay = 0.25
	backend.fetch_leaderboards()
	var slow := await _wait_quiet(backend)
	mock.delay = 0.0
	_check("network_slow_response", slow and _shown(backend, "daily").is_empty(), str(_shown(backend, "daily")))
	await _reset(backend)
	ready = await _claim_and_start(backend)
	mock.fault = "timeout"
	mock.fault_once = true
	mock.commit_on_fault = true
	await backend.finalize_daily_attempt(str(ready.get("attempt_id", "")), 22, "REEF")
	var lost := await _wait_quiet(backend)
	_check(
		"network_timeout_after_commit_retries_once",
		lost and _joined(_shown(backend, "daily")) == "REEF 22" and mock.count_scores(PLAYER_A, "daily") == 1 and mock.finalize_applies == 2,
		"shown=%s applies=%d" % [_shown(backend, "daily"), mock.finalize_applies]
	)


func _test_out_of_order(backend) -> void:
	await _reset(backend)
	mock.seed_daily(PLAYER_B, "old", 5)
	mock.stall_daily_once = true
	var seen: Array = []
	var on_board := func() -> void:
		seen.append(_joined(_shown(backend, "daily")))
	backend.leaderboards_ready.connect(on_board)
	backend.fetch_leaderboards()
	var spins := 0
	while not mock.stalled and spins < 50:
		await process_frame
		spins += 1
	var ready: Dictionary = await _claim_and_start(backend)
	await backend.finalize_daily_attempt(str(ready.get("attempt_id", "")), 27, "REEF")
	mock.release_stall = true
	var quiet := await _wait_quiet(backend)
	if backend.leaderboards_ready.is_connected(on_board):
		backend.leaderboards_ready.disconnect(on_board)
	var last := str(seen.back()) if not seen.is_empty() else ""
	_check(
		"network_out_of_order_keeps_newest",
		mock.stalled == false
		and quiet
		and seen.size() >= 2
		and last.find("REEF 27") >= 0
		and last.find("OLD 5") >= 0
		and last != "OLD 5",
		"seen=%s" % str(seen)
	)


func _play_daily(backend, score: int, name: String) -> Dictionary:
	var ready: Dictionary = await _claim_and_start(backend)
	if not bool(ready.get("ok", false)):
		return ready
	await backend.finalize_daily_attempt(str(ready.get("attempt_id", "")), score, name)
	var quiet := await _wait_quiet(backend)
	return {"ok": quiet and str(backend.daily_submit_error) == "", "attempt_id": ready.get("attempt_id", "")}


func _claim_and_start(backend) -> Dictionary:
	var claim: Dictionary = await backend.claim_daily_attempt()
	if not bool(claim.get("ok", false)):
		return {"ok": false, "claim": claim}
	var attempt_id := str(claim.get("challenge", {}).get("attempt_id", ""))
	var started: Dictionary = await backend.start_daily_attempt(attempt_id)
	_gs().active_challenge = claim.get("challenge", {})
	return {
		"ok": bool(started.get("started", false)),
		"attempt_id": attempt_id,
		"challenge": claim.get("challenge", {}),
		"started": started,
	}


func _warn_local_mirror() -> void:
	var book := DailyChallengeScript.empty_book()
	var when := DailyChallengeScript.unix_utc(2026, 10, 12, 15)
	DailyAttemptScript.submit_unlimited(book, PLAYER_A, "FIRST", 30, when)
	DailyAttemptScript.submit_unlimited(book, PLAYER_A, "SECOND", 10, when)
	var rows: Array = DailyChallengeScript.visible_board(book, "weekly", when)
	if rows.is_empty():
		return
	if str(rows[0].get("display_name", "")) == "FIRST":
		_warn("The local DailyAttempt mirror keeps the old display name when a lower Unlimited score arrives. submit_leaderboard_score in leaderboard_split.sql updates the name and keeps the higher score. The live client renders the server row, which the mock covers.")


func _snapshot_userdata() -> void:
	_saved = {}
	for path in ["user://reefrun.cfg", "user://supabase_session.cfg"]:
		if FileAccess.file_exists(path):
			_saved[path] = FileAccess.get_file_as_bytes(path)
		else:
			_saved[path] = PackedByteArray()
	_snap_ok = true


func _restore_userdata() -> bool:
	if not _snap_ok:
		return false
	var ok := true
	for path in _saved.keys():
		var bytes: PackedByteArray = _saved[path]
		if bytes.is_empty():
			if FileAccess.file_exists(path):
				var absolute := ProjectSettings.globalize_path(path)
				if DirAccess.remove_absolute(absolute) != OK:
					ok = false
			continue
		var handle := FileAccess.open(path, FileAccess.WRITE)
		if handle == null:
			ok = false
			continue
		handle.store_buffer(bytes)
		handle.close()
		var now := FileAccess.get_file_as_bytes(path)
		if now != bytes:
			ok = false
	return ok


class MockServer extends RefCounted:
	const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")
	const ClientScript := preload("res://scripts/backend/supabase_client.gd")

	var host: Node
	var headers_client = null
	var tokens: Dictionary = {}
	var now_unix := 0
	var publish_zone := "eastern"
	var query_zone := "eastern"
	var delay := 0.0
	var fault := ""
	var fault_once := false
	var commit_on_fault := false
	var force_empty_get := false
	var force_null_get := false
	var stall_daily_once := false
	var stalled := false
	var release_stall := false
	var attempts: Array = []
	var scores: Array = []
	var requests: Array = []
	var unexpected := 0
	var seq := 0
	var tick := 1
	var finalize_applies := 0
	var _gate := false

	func _init(owner: Node) -> void:
		host = owner
		headers_client = ClientScript.new(owner)

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

	func reset_data() -> void:
		attempts = []
		scores = []
		requests = []
		fault = ""
		fault_once = false
		commit_on_fault = false
		force_empty_get = false
		force_null_get = false
		stall_daily_once = false
		release_stall = false
		unexpected = 0
		finalize_applies = 0
		tick = 1

	func count_scores(uid: String, period: String) -> int:
		var n := 0
		for row in scores:
			if str(row.get("player_id", "")) == uid and str(row.get("period", "")) == period:
				n += 1
		return n

	func attempt_count(uid: String) -> int:
		var n := 0
		for row in attempts:
			if str(row.get("player_id", "")) == uid:
				n += 1
		return n

	func finalized_count(uid: String) -> int:
		var n := 0
		for row in attempts:
			if str(row.get("player_id", "")) == uid and bool(row.get("finalized", false)):
				n += 1
		return n

	func period_key_of(uid: String, period: String) -> String:
		for row in scores:
			if str(row.get("player_id", "")) == uid and str(row.get("period", "")) == period:
				return str(row.get("period_key", ""))
		return ""

	func score_of(uid: String, period: String) -> int:
		for row in scores:
			if str(row.get("player_id", "")) == uid and str(row.get("period", "")) == period:
				return int(row.get("score", 0))
		return 0

	func player_for_name(period: String, name: String) -> String:
		for row in scores:
			if str(row.get("period", "")) == period and str(row.get("display_name", "")) == name:
				return str(row.get("player_id", ""))
		return ""

	func seed_daily(uid: String, name: String, score: int) -> void:
		var today := _publish()
		_upsert(uid, _clean(name), score, "daily", str(today.get("challenge_date", "")), str(today.get("challenge_id", "")))

	func _dispatch(method: String, url: String, headers: PackedStringArray, body: String) -> Dictionary:
		var tree := Engine.get_main_loop() as SceneTree
		while _gate:
			await tree.process_frame
		_gate = true
		var response := _apply(method, url, headers, body)
		var hold: bool = stall_daily_once and url.ends_with("/get_leaderboard") and body.find("daily") >= 0 and bool(response.get("ok", false))
		if hold:
			stall_daily_once = false
		_gate = false
		if hold:
			stalled = true
			while not release_stall:
				await tree.process_frame
			stalled = false
			release_stall = false
		elif delay > 0.0:
			await tree.create_timer(delay).timeout
		return response

	func _apply(method: String, url: String, headers: PackedStringArray, body: String) -> Dictionary:
		var parsed: Dictionary = {}
		if body.strip_edges() != "":
			var data: Variant = JSON.parse_string(body)
			if typeof(data) == TYPE_DICTIONARY:
				parsed = data
		var uid := _uid(headers)
		seq += 1
		requests.append({
			"seq": seq,
			"method": method,
			"url": url,
			"body": body,
			"json": parsed,
			"uid": uid,
		})
		var mode := fault
		var commit := commit_on_fault
		if fault_once:
			fault = ""
			fault_once = false
			commit_on_fault = false
		if mode == "offline":
			return _transport(HTTPRequest.RESULT_CANT_CONNECT)
		if mode == "timeout":
			if commit and url.ends_with("/finalize_daily_attempt"):
				_mutate(url, parsed, uid)
			return _transport(HTTPRequest.RESULT_TIMEOUT)
		if mode == "bad_json":
			return {
				"ok": false,
				"status": 200,
				"data": null,
				"error": "invalid_json",
				"godot_request_error": 0,
				"godot_http_result": HTTPRequest.RESULT_SUCCESS,
			}
		if mode == "429" or mode == "500" or mode == "400":
			if commit:
				_mutate(url, parsed, uid)
			return _err(int(mode), "forced_%s" % mode)
		return _mutate(url, parsed, uid)

	func _mutate(url: String, parsed: Dictionary, uid: String) -> Dictionary:
		if url.ends_with("/claim_daily_attempt"):
			return _claim(uid, _text(parsed.get("p_idempotency_key", null)))
		if url.ends_with("/get_daily_attempt_status"):
			return _status(uid, _text(parsed.get("p_idempotency_key", null)))
		if url.ends_with("/start_daily_attempt"):
			return _start(uid, _text(parsed.get("p_attempt_id", null)))
		if url.ends_with("/finalize_daily_attempt"):
			finalize_applies += 1
			return _finalize(uid, _text(parsed.get("p_attempt_id", null)), int(parsed.get("p_score", 0)), str(parsed.get("p_display_name", "")))
		if url.ends_with("/submit_leaderboard_score"):
			return _submit(uid, int(parsed.get("p_score", 0)), str(parsed.get("p_display_name", "")))
		if url.ends_with("/get_leaderboard"):
			return _list(str(parsed.get("p_period", "")))
		if url.ends_with("/get_daily_challenge"):
			if uid == "":
				return _err(401, "not authenticated")
			return _ok([_publish()])
		unexpected += 1
		return _err(401, "blocked")

	func _claim(uid: String, key: String) -> Dictionary:
		if uid == "":
			return _err(401, "not authenticated")
		if key == "":
			return _err(400, "missing idempotency key")
		var today := _publish()
		var cid := str(today.get("challenge_id", ""))
		var existing := _find_player_challenge(uid, cid)
		var owned := false
		var replay := false
		var finalized := false
		var attempt_id := ""
		if existing.is_empty():
			attempt_id = "00000000-0000-4000-8000-%012d" % attempts.size()
			attempts.append({
				"attempt_id": attempt_id,
				"player_id": uid,
				"challenge_id": cid,
				"idempotency_key": key,
				"score": null,
				"started": false,
				"finalized": false,
			})
			owned = true
		else:
			replay = str(existing.get("idempotency_key", "")) == key
			finalized = bool(existing.get("finalized", false))
			var started := bool(existing.get("started", false))
			owned = replay and not started and not finalized
			if owned:
				attempt_id = str(existing.get("attempt_id", ""))
		var row := today.duplicate(true)
		row["attempt_id"] = attempt_id if owned else null
		row["claimed"] = owned
		row["already_used"] = not owned
		row["idempotent_replay"] = replay
		row["finalized"] = finalized
		return _ok([row])

	func _status(uid: String, key: String) -> Dictionary:
		if uid == "":
			return _err(401, "not authenticated")
		var today := _publish()
		var cid := str(today.get("challenge_id", ""))
		var existing := _find_player_challenge(uid, cid)
		var recoverable: bool = (
			not existing.is_empty()
			and key != ""
			and str(existing.get("idempotency_key", "")) == key
			and not bool(existing.get("started", false))
			and not bool(existing.get("finalized", false))
		)
		var row := today.duplicate(true)
		row["attempted"] = not existing.is_empty() and not recoverable
		row["recoverable"] = recoverable
		return _ok([row])

	func _start(uid: String, attempt_id: String) -> Dictionary:
		if uid == "":
			return _err(401, "not authenticated")
		if attempt_id == "":
			return _err(400, "missing attempt")
		var row := _find_attempt(uid, attempt_id)
		if row.is_empty():
			return _err(400, "attempt not found")
		if bool(row.get("started", false)) or bool(row.get("finalized", false)):
			return _ok([{"attempt_id": attempt_id, "started": false, "already_started": true}])
		row["started"] = true
		return _ok([{"attempt_id": attempt_id, "started": true, "already_started": false}])

	func _finalize(uid: String, attempt_id: String, score: int, display_name: String) -> Dictionary:
		if uid == "":
			return _err(401, "not authenticated")
		if attempt_id == "":
			return _err(400, "missing attempt")
		if score < 0:
			return _err(400, "invalid score")
		var row := _find_attempt(uid, attempt_id)
		if row.is_empty():
			return _err(400, "attempt not found")
		if not bool(row.get("started", false)) and not bool(row.get("finalized", false)):
			return _err(400, "attempt not started")
		if bool(row.get("finalized", false)):
			return _ok([{
				"attempt_id": attempt_id,
				"score": int(row.get("score", 0)),
				"accepted": false,
				"duplicate": true,
			}])
		row["score"] = score
		row["finalized"] = true
		if score > 0:
			var today := _publish()
			_upsert(uid, _clean(display_name), score, "daily", str(today.get("challenge_date", "")), str(row.get("challenge_id", "")))
		return _ok([{"attempt_id": attempt_id, "score": score, "accepted": true, "duplicate": false}])

	func _submit(uid: String, score: int, display_name: String) -> Dictionary:
		if uid == "":
			return _err(401, "not authenticated")
		if score <= 0:
			return _ok(null)
		var name := _clean(display_name)
		var utc := DailyChallengeScript.utc_date_from_unix(now_unix)
		_upsert(uid, name, score, "weekly", DailyChallengeScript.week_key(utc), "")
		_upsert(uid, name, score, "monthly", utc.substr(0, 7), "")
		return _ok(null)

	func _list(period: String) -> Dictionary:
		if force_null_get:
			return _ok(null)
		if force_empty_get:
			return _ok([])
		var key := _query_key(period)
		var rows: Array = []
		for row in scores:
			if str(row.get("period", "")) != period or str(row.get("period_key", "")) != key:
				continue
			var daily := str(row.get("challenge_id", "")) != ""
			if period == "daily" and not daily:
				continue
			if (period == "weekly" or period == "monthly") and daily:
				continue
			if int(row.get("score", 0)) <= 0:
				continue
			rows.append(row)
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.get("score", 0)) != int(b.get("score", 0)):
				return int(a.get("score", 0)) > int(b.get("score", 0))
			return int(a.get("created_at", 0)) < int(b.get("created_at", 0))
		)
		if rows.size() > 10:
			rows.resize(10)
		var out: Array = []
		for row in rows:
			out.append({
				"display_name": _clean(str(row.get("display_name", ""))),
				"score": int(row.get("score", 0)),
			})
		return _ok(out)

	func _publish() -> Dictionary:
		var date := _zone_date(publish_zone)
		var parts := date.split("-")
		var year := int(parts[0])
		var month := int(parts[1])
		var day := int(parts[2])
		var next := Time.get_datetime_dict_from_unix_time(DailyChallengeScript.unix_utc(year, month, day, 12) + 86400)
		var resets := DailyChallengeScript.eastern_midnight_unix(int(next.year), int(next.month), int(next.day))
		if publish_zone == "utc":
			resets = DailyChallengeScript.unix_utc(int(next.year), int(next.month), int(next.day))
		return {
			"challenge_id": DailyChallengeScript.challenge_id(date, RR.COURSE_VERSION, RR.PHYSICS_VERSION),
			"challenge_date": date,
			"course_seed": DailyChallengeScript.derive_seed(date, RR.COURSE_VERSION),
			"course_version": RR.COURSE_VERSION,
			"physics_version": RR.PHYSICS_VERSION,
			"as_of_unix": now_unix,
			"resets_unix": resets,
		}

	func _query_key(period: String) -> String:
		if period == "daily":
			return _zone_date(query_zone)
		var utc := DailyChallengeScript.utc_date_from_unix(now_unix)
		if period == "weekly":
			return DailyChallengeScript.week_key(utc)
		if period == "monthly":
			return utc.substr(0, 7)
		return ""

	func _zone_date(zone: String) -> String:
		if zone == "eastern":
			return DailyChallengeScript.challenge_date_from_unix(now_unix)
		return DailyChallengeScript.utc_date_from_unix(now_unix)

	func _upsert(uid: String, name: String, score: int, period: String, period_key: String, challenge_id: String) -> void:
		for row in scores:
			if str(row.get("player_id", "")) != uid:
				continue
			if str(row.get("period", "")) != period or str(row.get("period_key", "")) != period_key:
				continue
			var row_daily := str(row.get("challenge_id", "")) != ""
			if row_daily != (challenge_id != ""):
				continue
			if period == "daily":
				if score > int(row.get("score", 0)):
					row["score"] = score
					row["display_name"] = name
					row["challenge_id"] = challenge_id
				return
			row["display_name"] = name
			if score > int(row.get("score", 0)):
				row["score"] = score
			return
		scores.append({
			"player_id": uid,
			"display_name": name,
			"score": score,
			"period": period,
			"period_key": period_key,
			"challenge_id": challenge_id,
			"created_at": tick,
		})
		tick += 1

	func _find_player_challenge(uid: String, challenge_id: String) -> Dictionary:
		for row in attempts:
			if str(row.get("player_id", "")) == uid and str(row.get("challenge_id", "")) == challenge_id:
				return row
		return {}

	func _find_attempt(uid: String, attempt_id: String) -> Dictionary:
		for row in attempts:
			if str(row.get("player_id", "")) == uid and str(row.get("attempt_id", "")) == attempt_id:
				return row
		return {}

	func _clean(raw: String) -> String:
		var name := raw.strip_edges().substr(0, 7)
		if name.is_empty():
			return "YOU"
		return name

	func _text(value: Variant) -> String:
		if value == null:
			return ""
		var text := str(value).strip_edges()
		if text == "<null>" or text.to_lower() == "null":
			return ""
		return text

	func _uid(headers: PackedStringArray) -> String:
		for header in headers:
			var text := str(header).strip_edges()
			if not text.to_lower().begins_with("authorization:"):
				continue
			var value := text.substr(text.find(":") + 1).strip_edges()
			if value.to_lower().begins_with("bearer "):
				return str(tokens.get(value.substr(7).strip_edges(), ""))
		return ""

	func _ok(data: Variant) -> Dictionary:
		return {
			"ok": true,
			"status": 200,
			"data": data,
			"error": "",
			"godot_request_error": 0,
			"godot_http_result": HTTPRequest.RESULT_SUCCESS,
		}

	func _err(status: int, message: String) -> Dictionary:
		return {
			"ok": false,
			"status": status,
			"data": {"code": "P0001" if status != 401 else "PGRST301", "message": message},
			"error": "http_%d" % status,
			"godot_request_error": 0,
			"godot_http_result": HTTPRequest.RESULT_SUCCESS,
		}

	func _transport(code: int) -> Dictionary:
		return {
			"ok": false,
			"status": 0,
			"data": null,
			"error": "transport",
			"godot_request_error": 0,
			"godot_http_result": code,
		}
