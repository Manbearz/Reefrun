extends SceneTree

const Missions := preload("res://scripts/daily_missions.gd")

# Checks the unapplied Eastern-reset migration. It does not connect to Supabase.

var _failed := 0
var _live_http := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_seal_network()
	var sql := FileAccess.get_file_as_string("res://tools/supabase/eastern_daily_reset.sql")
	var client := FileAccess.get_file_as_string("res://scripts/backend/daily_mission_repository.gd")
	var rules := FileAccess.get_file_as_string("res://scripts/daily_missions.gd")
	_check("file_loaded", sql.length() > 1000)
	_check("publish_eastern", sql.contains("reefrun_publish_today") and sql.contains("timezone('America/New_York', pg_catalog.now())"))
	_check("publish_reset_eastern", sql.contains("at time zone 'America/New_York'"))
	_check("daily_board_eastern", _function_body(sql, "get_leaderboard").contains("p_period = 'daily'") and _function_body(sql, "get_leaderboard").contains("America/New_York"))
	var board := _function_body(sql, "get_leaderboard")
	_check("weekly_stays_utc", board.contains("p_period = 'weekly'") and board.contains("timezone('utc', pg_catalog.now())"))
	_check("monthly_stays_utc", board.contains("p_period = 'monthly'") and board.contains("YYYY-MM"))
	_check("mission_board_eastern", _function_body(sql, "reefrun_daily_mission_board").contains("America/New_York"))
	_check("claim_eastern", _function_body(sql, "claim_daily_mission").contains("America/New_York"))
	_check("record_eastern", _count(sql, "timezone('America/New_York', pg_catalog.now())") >= 4)
	_check("no_delete", not sql.to_lower().contains("delete from"))
	_check("no_historical_rewrite", not sql.to_lower().contains("update public.leaderboard_scores") and not sql.to_lower().contains("update public.daily_attempts") and not sql.to_lower().contains("update public.daily_challenges") and not sql.to_lower().contains("update public.daily_mission_sets") and not sql.to_lower().contains("update public.daily_mission_claims"))
	_check("rewards_unchanged", sql.contains("then 5 when 'medium' then 10 else 20") and sql.contains("'reward', 25") and sql.contains("existing_sum + reward > 60"))
	_check("claim_conflict_unchanged", sql.contains("on conflict (player_id, mission_date, slot) do nothing"))
	_check("twelve_argument_signature", sql.contains("p_dives_entered integer") and sql.contains("p_mines integer"))
	_check("four_argument_wrapper", _count(sql, "function public.record_unlimited_mission_run(") >= 2)
	_check("pipe_cap_20000", sql.contains("p_pipes > 20000") and not sql.contains("or p_pipes > 80\n") and not sql.contains("or p_pipes > 80\r"))
	_check("no_default_overload_ambiguity", not sql.contains("integer default"))
	_check("checks_match_stored_form", sql.contains("<= 80\\)") and sql.contains("<= 1800\\)"))
	_check("client_sends_dive_fields", client.contains("p_dives_entered") and client.contains("p_mines") and client.contains("legacy_record_body"))
	_check("date_guard", sql.contains("Refusing Eastern daily reset"))
	_check("client_accepts_long_runs", rules.contains("const MAX_PIPES_PER_RUN := 20000") and rules.contains("scheduled_dives"))
	_check("snapshot_scores_dive_rules", _snapshot_has_dive_rules(sql, rules))
	_check("snapshot_keeps_pipe_rules", sql.contains("when 'pipes_total'") and sql.contains("when 'survive_best'") and sql.contains("when 'coins_total'") and sql.contains("when 'runs_at_least'") and sql.contains("when 'window_sum'"))
	_check("no_new_mission_rows", not sql.to_lower().contains("insert into public.mission_definitions"))
	_check("short_run_without_dive", _accept(40, 90, 8, 0))
	_check("short_run_too_slow", not _accept(40, 200, 0, 0))
	_check("coins_over_schedule", not _accept(40, 90, 9, 0))
	_check("full_80_keeps_1800_cap", _accept(80, 500, 16, 0) and not _accept(80, 1801, 0, 0))
	_check("checkpoint_5000_in_bounds", _accept(5000, 12000, 1000, 166))
	_check("checkpoint_5000_too_many_dives", not _accept(5000, 12000, 1000, 167))
	_check("checkpoint_5000_too_slow", not _accept(5000, 20000, 0, 166))
	_check("two_thousand_pipes_at_pace", _accept(2000, 4000, 0, 0) and not _accept(2000, 5000, 0, 0))
	_check("dive_before_first_gate", not _accept(20, 40, 0, 1))
	_check("no_live_http", _live_http == 0)
	print("[eastern-sql] failed=%d" % _failed)
	quit(0 if _failed == 0 else 1)


func _seal_network() -> void:
	var backend := root.get_node_or_null("Backend")
	if backend != null and "_client" in backend:
		backend._client = DeadNet.new()
	var pending: Array[Node] = []
	_collect_http(root, pending)
	for http in pending:
		http.cancel_request()
		http.queue_free()


func _collect_http(node: Node, found: Array[Node]) -> void:
	if node is HTTPRequest:
		found.append(node)
		var http := node as HTTPRequest
		if not http.request_completed.is_connected(_on_http):
			http.request_completed.connect(_on_http)
	for child in node.get_children():
		_collect_http(child, found)


func _on_http(result: int, status: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and status >= 200:
		_live_http += 1


class DeadNet:
	func cancel() -> void:
		pass

	func is_ready() -> bool:
		return true

	func auth_headers(_access_token: String = "") -> PackedStringArray:
		return PackedStringArray()

	func request_json(_method: String, _url: String, _headers: PackedStringArray, _body: String = "") -> Dictionary:
		return {"ok": false, "status": 0, "json": null, "error": "blocked", "result": HTTPRequest.RESULT_CANT_CONNECT}

	func request_json_independent(method: String, url: String, headers: PackedStringArray, body: String = "") -> Dictionary:
		return request_json(method, url, headers, body)


func _snapshot_has_dive_rules(sql: String, _rules_text: String) -> bool:
	var seen := {}
	for mission in Missions.catalog():
		var rule := str(mission.get("rule", ""))
		if seen.has(rule):
			continue
		seen[rule] = true
		if not sql.contains("when '%s'" % rule):
			print("[eastern-sql] snapshot missing %s" % rule)
			return false
	return seen.size() >= 18


func _accept(pipes: int, seconds: int, coins: int, dives: int) -> bool:
	var scheduled := 0
	if pipes >= 30:
		scheduled = 1 + int((pipes - 30) / 30)
	var short_limit := 0
	var long_limit := 0
	if pipes < 80:
		short_limit = int(floor(1.8 + float(pipes) * 1.5 + 12.0 + float(12 * int(pipes / 20)))) + 28 * dives
	if pipes > 80:
		long_limit = int(floor(1.8 + float(pipes) * 1.5 + 12.0 + float(12 * int(pipes / 20)))) + 28 * dives
	if pipes < 0 or pipes > 20000 or seconds < 0 or seconds > 86400:
		return false
	if coins < 0 or coins > int(pipes / 5):
		return false
	if pipes > 0 and seconds < pipes - 1:
		return false
	if dives < 0 or dives > scheduled:
		return false
	if pipes < 80 and seconds > short_limit:
		return false
	if pipes <= 80 and seconds > 1800:
		return false
	if pipes > 80 and seconds > long_limit:
		return false
	return true


func _function_body(sql: String, name: String) -> String:
	var marker := "function public.%s" % name
	var at := sql.find(marker)
	if at < 0:
		return ""
	var end := sql.find("$fn$;", at)
	if end < 0:
		return ""
	return sql.substr(at, end - at)


func _count(text: String, needle: String) -> int:
	var total := 0
	var from := 0
	while true:
		var at := text.find(needle, from)
		if at < 0:
			return total
		total += 1
		from = at + needle.length()
	return total


func _check(name: String, ok: bool) -> void:
	if ok:
		print("[eastern-sql] pass %s" % name)
		return
	_failed += 1
	print("[eastern-sql] FAIL %s" % name)
