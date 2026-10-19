extends Node

# Orchestrates Supabase stages. Safe no-op when config is empty or the network fails.

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")
const ClientScript := preload("res://scripts/backend/supabase_client.gd")
const AuthScript := preload("res://scripts/backend/supabase_auth.gd")
const ProfileScript := preload("res://scripts/backend/profile_service.gd")
const CourseSeedScript := preload("res://scripts/backend/course_seed_service.gd")
const LeaderboardScript := preload("res://scripts/backend/leaderboard_repository.gd")
const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")
const DailyAttemptScript := preload("res://scripts/daily_attempt.gd")
const DailyTestModeScript := preload("res://scripts/daily_test_mode.gd")
const CourseBuilderScript := preload("res://scripts/course_builder.gd")
const GhostMatchScript := preload("res://scripts/ghost_match.gd")
const FallbackScript := preload("res://scripts/fallback_ghost_factory.gd")
const ShareRewardScript := preload("res://scripts/backend/share_reward_repository.gd")
const DailyMissionRepoScript := preload("res://scripts/backend/daily_mission_repository.gd")
const DailyMissionsScript := preload("res://scripts/daily_missions.gd")
const ReferralRulesScript := preload("res://scripts/share/referral_rules.gd")

signal signed_in(user_id: String)
signal identity_ready
signal leaderboards_ready
signal share_rewards_changed
signal daily_missions_changed
signal mission_reward_granted(slot: String, coins: int, mission_date: String)

var auth = null
var _client = null
var _profiles = null
var _seeds = null
var _leaderboards = null
var _share_rewards = null
var _missions = null
var _mission_busy := false
var _mission_flush_again := false
var _mission_auto_claim := false
var _mission_claim_blocked := ""
var _mission_claim_date := ""
var mission_note := ""
var _share_reward_busy := false
var global_daily: Array = []
var global_weekly: Array = []
var global_monthly: Array = []
var _lb_busy := false
var _ghost_cache: Dictionary = {}
var _roster: Dictionary = {}
var _pending_uploads: Array = []
var _challenge: Dictionary = {}
var _server_as_of := 0
var _local_at_fetch := 0
var _busy := false
var _auth_logged := false
var _refresh_busy := false
var _daily_busy := false
var _daily_stop := false
var _lb_period_date := ""
var _lb_checked_date := ""
var _daily_roll_checked := ""
var _lb_needs_refresh := false
var leaderboard_meta: Dictionary = {}
var _followup_busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	auth = AuthScript.new()
	_client = ClientScript.new(self)
	_profiles = ProfileScript.new()
	_seeds = CourseSeedScript.new()
	_leaderboards = LeaderboardScript.new()
	_share_rewards = ShareRewardScript.new()
	_missions = DailyMissionRepoScript.new()
	if not ConfigScript.is_configured():
		_resolve_identity()
		_log_daily_auth("unconfigured")
		return
	_bootstrap()


func is_configured() -> bool:
	return ConfigScript.is_configured()


func has_session() -> bool:
	return auth != null and auth.has_session()


func has_usable_session() -> bool:
	return auth != null and auth.has_session() and auth.access_token_fresh()


func auth_source_label() -> String:
	return "Supabase Anonymous" if has_session() else "Local Fallback"


func supabase_status_label() -> String:
	return "Connected" if has_usable_session() else "Not Connected"


func has_shared_seed() -> bool:
	return int(_challenge.get("course_seed", 0)) != 0


func shared_course_seed() -> int:
	return int(_challenge.get("course_seed", 0))


func challenge_for_new_match() -> Dictionary:
	return DailyChallengeScript.choose_for_new_match(
		_challenge,
		_server_as_of,
		_local_at_fetch,
		int(Time.get_unix_time_from_system())
	)


func prepared_roster(challenge: Dictionary) -> Array:
	var key := DailyChallengeScript.cache_key(challenge)
	if not _roster.has(key):
		return []
	var rows: Variant = _roster[key]
	if rows is Array and rows.size() >= RR.GHOST_COUNT:
		return rows
	return []


func may_upload_ghost(run) -> bool:
	if run == null or GameSession.practice_daily:
		return false
	if not DailyChallengeScript.may_submit(GameSession.current_challenge()):
		return false
	return str(run.challenge_id) == GameSession.current_challenge_id()


func leaderboard_period_stale() -> bool:
	if _lb_period_date == "":
		return false
	var est := _estimated_server_date()
	if est == "" or est == _lb_period_date or est == _lb_checked_date:
		return false
	return true


func daily_refresh_due() -> bool:
	if _daily_busy or not is_configured() or not has_session():
		return false
	if not _pre_match_network_allowed():
		return false
	var est := _estimated_server_date()
	if est == "" or _challenge.is_empty():
		return false
	if est == str(_challenge.get("challenge_date", "")) or est == _daily_roll_checked:
		return false
	return true


func daily_challenge_ready() -> bool:
	return _seeds != null and _seeds.has_method("parse_challenge") and _seeds.has_method("challenge_url")


func prepare_for_daily_play() -> void:
	_daily_stop = false
	while _daily_busy:
		await get_tree().process_frame
		if _daily_stop:
			return
	if _daily_stop:
		return
	await _prepare_daily_match()


func prepare_claimed_daily(challenge: Dictionary) -> void:
	_daily_stop = false
	while _daily_busy:
		await get_tree().process_frame
		if _daily_stop:
			return
	if _daily_stop:
		return
	_daily_busy = true
	_adopt_server_challenge(challenge)
	_log_daily_stage("prepare", {
		"attempt_id": str(challenge.get("attempt_id", "")),
		"seed": int(challenge.get("course_seed", 0)),
		"date": str(challenge.get("challenge_date", "")),
		"id": str(challenge.get("challenge_id", "")),
	})
	if _daily_stop or not _pre_match_network_allowed():
		_daily_busy = false
		return
	await _prefetch_challenge_ghosts()
	if _daily_stop or not _pre_match_network_allowed():
		_daily_busy = false
		return
	await _build_roster()
	_daily_busy = false


func fetch_daily_attempt_status() -> Dictionary:
	if _daily_busy:
		var busy := {"ok": false, "status": 0, "error": "busy", "attempted": false}
		_log_daily_stage("get_daily_attempt_status", busy)
		return busy
	if not is_configured() or not has_session():
		var missing := {"ok": false, "status": 0, "error": "no_session", "attempted": false}
		_log_rpc("get_daily_attempt_status", missing)
		_log_daily_stage("get_daily_attempt_status", missing)
		return missing
	_daily_busy = true
	var status_key := str(GameSession.pending_claim_key).strip_edges()
	var status_body := JSON.stringify({
		"p_idempotency_key": status_key if status_key != "" else null,
	})
	var result: Dictionary = await _authed_request("POST", _leaderboards.status_url(), status_body, false, false)
	_daily_busy = false
	_log_rpc("get_daily_attempt_status", result)
	var parsed: Dictionary = DailyAttemptScript.parse_status(result)
	if not parsed.get("ok", false):
		parsed["error"] = _useful_rpc_error(str(parsed.get("error", "")), result)
	_log_daily_stage("get_daily_attempt_status", _with_postgrest({
		"status": int(parsed.get("status", 0)),
		"ok": bool(parsed.get("ok", false)),
		"attempted": bool(parsed.get("attempted", false)),
		"recoverable": bool(parsed.get("recoverable", false)),
		"method": "POST",
		"params": "p_idempotency_key",
		"error": str(parsed.get("error", "")),
	}, result))
	if (
		not parsed.get("ok", false)
		and not parsed.get("attempted", false)
		and GameSession.has_method("clear_claim_key")
		and not DailyAttemptScript.keep_claim_key(int(parsed.get("status", 0)))
	):
		GameSession.clear_claim_key()
	if parsed.get("ok", false) and int(parsed.get("as_of_unix", 0)) > 0:
		_server_as_of = int(parsed.get("as_of_unix", 0))
		_local_at_fetch = int(Time.get_unix_time_from_system())
	return parsed


func fetch_practice_course() -> Dictionary:
	if not DailyTestModeScript.enabled():
		return {}
	while _daily_busy:
		await get_tree().process_frame
		if not DailyTestModeScript.enabled():
			return {}
	_daily_busy = true
	await _fetch_daily_challenge()
	_daily_busy = false
	if not DailyChallengeScript.may_submit(_challenge):
		return {}
	return DailyTestModeScript.practice_course(_challenge)


func claim_daily_attempt() -> Dictionary:
	var denied := {"ok": false, "already_used": false, "status": 0, "challenge": {}, "resets_at_unix": 0}
	_daily_stop = false
	while _daily_busy:
		await get_tree().process_frame
		if _daily_stop:
			denied["cancelled"] = true
			denied["error"] = "cancelled"
			_log_claim(denied)
			return denied
	if not is_configured() or not has_session():
		_log_rpc("claim_daily_attempt", {"ok": false, "status": 0, "error": "no_session"})
		denied["error"] = "no_session"
		_log_claim(denied)
		return denied
	_daily_busy = true
	var key := str(GameSession.pending_claim_key).strip_edges()
	if key == "":
		key = DailyAttemptScript.new_idempotency_key()
	if GameSession.has_method("remember_claim_key"):
		GameSession.remember_claim_key(key)
	var parsed := denied.duplicate(true)
	var last_http: Dictionary = {}
	for _try in 3:
		if _daily_stop:
			parsed = denied.duplicate(true)
			parsed["cancelled"] = true
			parsed["error"] = "cancelled"
			break
		var result: Dictionary = await _authed_request(
			"POST",
			_leaderboards.claim_url(),
			JSON.stringify({"p_idempotency_key": key}),
			false,
			false
		)
		last_http = result
		_log_rpc("claim_daily_attempt", result)
		parsed = DailyAttemptScript.parse_claim(result)
		if parsed.get("cancelled", false):
			break
		if parsed.get("ok", false) or parsed.get("already_used", false):
			break
		var status := int(parsed.get("status", 0))
		if status != 0 and status < 500:
			break
	if parsed.get("ok", false) and typeof(parsed.get("challenge", {})) == TYPE_DICTIONARY:
		_adopt_server_challenge(parsed["challenge"])
	elif GameSession.has_method("clear_claim_key") and (
		parsed.get("already_used", false)
		or not DailyAttemptScript.keep_claim_key(int(parsed.get("status", 0)))
	):
		# already_used means the server row exists. A definite 4xx means it does not.
		# Neither case may leave a local key that pretends this day was completed.
		GameSession.clear_claim_key()
	_daily_busy = false
	if not parsed.get("ok", false) and not last_http.is_empty():
		parsed["error"] = _useful_rpc_error(str(parsed.get("error", "")), last_http)
	_log_claim(parsed, last_http)
	return parsed


func start_daily_attempt(attempt_id: String) -> Dictionary:
	var denied := {"ok": false, "started": false, "already_started": false, "status": 0}
	var clean_id := attempt_id.strip_edges()
	if clean_id == "" or not is_configured() or not has_session():
		denied["error"] = "missing_attempt" if clean_id == "" else "no_session"
		_log_rpc("start_daily_attempt", denied)
		_log_start(clean_id, denied)
		return denied
	var parsed := denied.duplicate(true)
	var last_http: Dictionary = {}
	var saw_uncertain := false
	for _try in 3:
		if _daily_stop:
			parsed = denied.duplicate(true)
			parsed["cancelled"] = true
			parsed["error"] = "cancelled"
			break
		var result: Dictionary = await _authed_request(
			"POST",
			_leaderboards.start_url(),
			JSON.stringify({"p_attempt_id": clean_id}),
			false,
			false
		)
		last_http = result
		_log_rpc("start_daily_attempt", result)
		# The HTTP helper retries a lost response before this loop sees it.
		# That retry can come back already_started and is still this one run.
		saw_uncertain = DailyAttemptScript.start_attempt_uncertain(saw_uncertain, result)
		parsed = DailyAttemptScript.recover_lost_start(saw_uncertain, DailyAttemptScript.parse_start(result))
		if parsed.get("started", false) or parsed.get("already_started", false):
			break
		if saw_uncertain:
			continue
		break
	if parsed.get("already_started", false) and not parsed.get("started", false) and GameSession.has_method("clear_claim_key"):
		GameSession.clear_claim_key()
	if not bool(last_http.get("ok", false)) and not last_http.is_empty():
		parsed["error"] = _useful_rpc_error(str(parsed.get("error", "")), last_http)
	_log_start(clean_id, parsed, last_http)
	return parsed


func refresh_daily_after_rollover() -> void:
	var est := _estimated_server_date()
	if est != "":
		_daily_roll_checked = est
	if _daily_busy or not is_configured() or not has_session() or not _pre_match_network_allowed():
		return
	_daily_busy = true
	await _fetch_daily_challenge()
	_daily_busy = false


func _resolve_identity() -> void:
	if not has_session():
		GameSession.ensure_local_fallback_id()
	_auth_logged = true
	identity_ready.emit()
	call_deferred("flush_daily_missions")


func _adopt_supabase_user(uid: String) -> void:
	if uid.is_empty() or uid.begins_with("local_"):
		return
	GameSession.adopt_supabase_id(uid)
	signed_in.emit(uid)


func _safe_auth_error(result: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if int(result.get("status", 0)) != 0:
		parts.append("http_%d" % int(result.status))
	var data: Variant = result.get("data", null)
	if typeof(data) == TYPE_DICTIONARY:
		for key in ["code", "error", "error_description", "message", "msg", "msg_code", "details", "hint"]:
			var value := str(data.get(key, "")).strip_edges()
			if value.is_empty():
				continue
			if value.begins_with("eyJ") or value.contains("sb_secret") or value.contains("service_role"):
				continue
			if value.length() > 180:
				value = value.substr(0, 180)
			parts.append(value)
	elif typeof(data) == TYPE_STRING:
		var text := str(data).strip_edges()
		if not text.is_empty() and not text.begins_with("eyJ") and text.length() < 240:
			parts.append(text)
	var fallback := str(result.get("error", "")).strip_edges()
	if not fallback.is_empty() and not fallback.begins_with("eyJ"):
		parts.append(fallback)
	if int(result.get("status", 0)) == 0 and int(result.get("godot_http_result", -1)) >= 0:
		parts.append("transport_%d" % int(result.godot_http_result))
	return ", ".join(parts)


func _log_rpc(rpc_name: String, result: Dictionary) -> void:
	var status := int(result.get("status", 0))
	if bool(result.get("ok", false)):
		print("[rpc] %s status=%d" % [rpc_name, status])
		return
	var body := _postgrest_fields(result)
	var message := str(body.message)
	if message == "":
		message = _safe_auth_error(result)
	push_warning("[rpc] %s status=%d code=%s message=%s details=%s hint=%s" % [
		rpc_name,
		status,
		str(body.code),
		message,
		str(body.details),
		str(body.hint),
	])
	var raw := str(result.get("body_text", "")).strip_edges()
	print("[rpc] %s response_body=%s content_type=%s authorization=%s apikey=%s" % [
		rpc_name,
		raw if raw != "" else "(empty)",
		str(result.get("content_type", "")),
		str(result.get("authorization", "")),
		str(result.get("apikey", "")),
	])


func _log_daily_stage(stage: String, fields: Dictionary) -> void:
	var parts: PackedStringArray = PackedStringArray()
	for key in fields.keys():
		parts.append("%s=%s" % [str(key), str(fields[key])])
	print("[daily] %s %s" % [stage, " ".join(parts)])


func _log_daily_auth(stage: String) -> void:
	var kind := "empty"
	var id := str(GameSession.player_id).strip_edges()
	if id.begins_with("local_"):
		kind = "local_fallback"
	elif not id.is_empty():
		kind = "supabase"
	_log_daily_stage("auth", {
		"stage": stage,
		"configured": is_configured(),
		"session": _auth_state_label(),
		"player": kind,
	})


func _postgrest_text(value: Variant) -> String:
	if value == null:
		return ""
	var text := str(value).strip_edges()
	if text.is_empty() or text == "<null>" or text.to_lower() == "null":
		return ""
	if text.begins_with("eyJ") or text.contains("sb_secret") or text.contains("service_role"):
		return ""
	if text.length() > 240:
		text = text.substr(0, 240)
	return text


func _postgrest_fields(result: Dictionary) -> Dictionary:
	var out := {"code": "", "message": "", "details": "", "hint": ""}
	var data: Variant = result.get("data", null)
	if typeof(data) != TYPE_DICTIONARY:
		return out
	out.code = _postgrest_text(data.get("code", data.get("error_code", "")))
	out.message = _postgrest_text(data.get("message", data.get("msg", "")))
	if str(out.message) == "":
		out.message = _postgrest_text(data.get("error_description", data.get("error", "")))
	out.details = _postgrest_text(data.get("details", ""))
	out.hint = _postgrest_text(data.get("hint", ""))
	return out


func _with_postgrest(fields: Dictionary, result: Dictionary) -> Dictionary:
	var body := _postgrest_fields(result)
	fields["code"] = body.code
	fields["message"] = body.message
	fields["details"] = body.details
	fields["hint"] = body.hint
	return fields


func _generic_http_error(text: String) -> bool:
	return text.begins_with("http_") and text.substr(5).is_valid_int()


func _useful_rpc_error(parsed_error: String, result: Dictionary) -> String:
	var generic := parsed_error.strip_edges()
	if bool(result.get("ok", false)) and not _generic_http_error(generic) and generic != "":
		return generic
	if not _generic_http_error(generic) and generic != "" and generic != "0":
		return generic
	var body := _postgrest_fields(result)
	var parts: PackedStringArray = PackedStringArray()
	if str(body.code) != "":
		parts.append("code=%s" % str(body.code))
	if str(body.message) != "":
		parts.append(str(body.message))
	if str(body.details) != "":
		parts.append(str(body.details))
	if str(body.hint) != "":
		parts.append("hint=%s" % str(body.hint))
	if not parts.is_empty():
		return " ".join(parts)
	if generic != "":
		return generic
	return _safe_auth_error(result)


func _log_claim(parsed: Dictionary, http: Dictionary = {}) -> void:
	var challenge: Variant = parsed.get("challenge", {})
	var attempt_id := ""
	var seed := 0
	if typeof(challenge) == TYPE_DICTIONARY:
		attempt_id = str(challenge.get("attempt_id", ""))
		seed = int(challenge.get("course_seed", 0))
	_log_daily_stage("claim_daily_attempt", _with_postgrest({
		"status": int(parsed.get("status", 0)),
		"ok": bool(parsed.get("ok", false)),
		"already_used": bool(parsed.get("already_used", false)),
		"attempt_id": attempt_id,
		"seed": seed,
		"method": "POST",
		"params": "p_idempotency_key",
		"error": _stage_error(parsed, http),
	}, http))


func _log_start(attempt_id: String, parsed: Dictionary, http: Dictionary = {}) -> void:
	_log_daily_stage("start_daily_attempt", _with_postgrest({
		"attempt_id": attempt_id,
		"status": int(parsed.get("status", 0)),
		"started": bool(parsed.get("started", false)),
		"already_started": bool(parsed.get("already_started", false)),
		"method": "POST",
		"params": "p_attempt_id",
		"error": _stage_error(parsed, http),
	}, http))


func _stage_error(parsed: Dictionary, http: Dictionary) -> String:
	if http.is_empty():
		return str(parsed.get("error", "")).strip_edges()
	if bool(parsed.get("ok", false)) or bool(parsed.get("started", false)):
		var kept := str(parsed.get("error", "")).strip_edges()
		if _generic_http_error(kept):
			return ""
		return kept
	return _useful_rpc_error(str(parsed.get("error", "")), http)


func cached_ghost_runs(course_seed: int) -> Array:
	var key := "seed:%d" % course_seed
	return DailyChallengeScript.cached_rows(_ghost_cache, key, int(Time.get_unix_time_from_system()))


func cached_ghost_runs_for_challenge(challenge_id: String) -> Array:
	var now := int(Time.get_unix_time_from_system())
	for key in _ghost_cache.keys():
		if not str(key).begins_with(challenge_id + "|"):
			continue
		var rows := DailyChallengeScript.cached_rows(_ghost_cache, str(key), now)
		if not rows.is_empty() or DailyChallengeScript.ghost_cache_fresh(_ghost_cache, str(key), now):
			return rows
	return []


func upload_ghost_run(run) -> void:
	if run == null or not is_configured() or auth == null or not auth.has_session():
		return
	_pending_uploads.append(run)
	call_deferred("_flush_uploads")


func cancel_pre_match_requests() -> void:
	_daily_stop = true
	if _client != null and _client.has_method("cancel"):
		_client.cancel()


func prepare_menu() -> void:
	if not is_configured():
		return
	if _busy:
		return
	if auth != null and auth.needs_refresh() and _pre_match_network_allowed():
		_ensure_fresh_session()
		return
	if has_session() or _auth_logged:
		return
	_bootstrap()


func _bootstrap() -> void:
	if _busy:
		return
	_busy = true
	if auth.load_session():
		if not auth.user_id.is_empty() and not auth.user_id.begins_with("local_"):
			_adopt_supabase_user(auth.user_id)
		if not auth.access_token_fresh() and _pre_match_network_allowed() and auth.has_refresh_token():
			await _refresh_session()
	# A saved refresh_token means this is the same anonymous user. Do not sign up again.
	if auth.user_id.is_empty() and not auth.has_refresh_token() and _pre_match_network_allowed():
		await _sign_in_anonymous()
	if auth.has_session():
		_adopt_supabase_user(auth.user_id)
	_busy = false
	_resolve_identity()
	_log_daily_auth("bootstrap")
	_menu_followup()


func _ensure_fresh_session() -> void:
	if _busy or auth == null:
		return
	_busy = true
	if auth.needs_refresh() and _pre_match_network_allowed():
		await _refresh_session()
	if auth.has_session():
		_adopt_supabase_user(auth.user_id)
	_busy = false


func _sign_in_anonymous() -> void:
	if not _pre_match_network_allowed():
		return
	var result: Dictionary = await _client.request_json(
		"POST",
		auth.signup_url(),
		_client.auth_headers(),
		JSON.stringify({"data": {}})
	)
	var applied: bool = bool(result.ok) and auth.apply_payload(result.data)
	if result.ok and not applied and auth != null and not auth.access_token.is_empty():
		await _fetch_auth_user()
		applied = auth.has_session()
	if applied:
		_adopt_supabase_user(auth.user_id)
	elif not result.ok:
		push_warning("[auth] sign-in failed: %s" % _safe_auth_error(result))


func _fetch_auth_user() -> void:
	if auth == null or auth.access_token.is_empty():
		return
	var result: Dictionary = await _client.request_json(
		"GET",
		auth.user_url(),
		_client.auth_headers(auth.access_token)
	)
	if not result.ok or typeof(result.data) != TYPE_DICTIONARY:
		return
	var uid := str(result.data.get("id", "")).strip_edges()
	auth.apply_user_id(uid)


func _refresh_session() -> bool:
	if auth == null:
		return false
	if _refresh_busy:
		while _refresh_busy:
			await get_tree().process_frame
		return auth.access_token_fresh()
	if not auth.has_refresh_token():
		return false
	_refresh_busy = true
	var previous_uid := str(auth.user_id)
	var result: Dictionary = await _client.request_json_independent(
		"POST",
		auth.refresh_url(),
		_client.auth_headers(),
		JSON.stringify({"refresh_token": auth.refresh_token})
	)
	var applied: bool = bool(result.ok) and auth.apply_payload(result.data)
	if applied:
		if not previous_uid.is_empty() and auth.user_id != previous_uid:
			auth.user_id = previous_uid
			auth.save_session()
		_adopt_supabase_user(auth.user_id)
		_refresh_busy = false
		return true
	push_warning("[auth] session refresh failed: %s" % _safe_auth_error(result))
	_refresh_busy = false
	return false


func _is_jwt_expired(result: Dictionary) -> bool:
	if int(result.get("status", 0)) != 401:
		return false
	if _is_jwt_issued_in_future(result):
		return false
	var data: Variant = result.get("data", null)
	if typeof(data) == TYPE_DICTIONARY:
		var code := str(data.get("code", data.get("error_code", ""))).to_lower()
		if code == "pgrst301" or code.find("jwt") >= 0:
			return true
	var err := _safe_auth_error(result).to_lower()
	return err.find("jwt expired") >= 0 or err.find("invalid jwt") >= 0


func _is_jwt_issued_in_future(result: Dictionary) -> bool:
	if int(result.get("status", 0)) != 401:
		return false
	var data: Variant = result.get("data", null)
	if typeof(data) == TYPE_DICTIONARY:
		var code := str(data.get("code", data.get("error_code", ""))).to_upper()
		if code == "PGRST303":
			return true
	return _safe_auth_error(result).to_lower().find("issued at future") >= 0


func _is_transport_failure(result: Dictionary) -> bool:
	if int(result.get("status", 0)) != 0:
		return false
	var code := int(result.get("godot_http_result", -1))
	return (
		code == HTTPRequest.RESULT_CANT_RESOLVE
		or code == HTTPRequest.RESULT_CANT_CONNECT
		or code == HTTPRequest.RESULT_CONNECTION_ERROR
		or code == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR
		or code == HTTPRequest.RESULT_NO_RESPONSE
		or code == HTTPRequest.RESULT_TIMEOUT
	)


func _send_authed(method: String, url: String, body: String, independent: bool, prefer_minimal: bool) -> Dictionary:
	var headers: PackedStringArray = _client.auth_headers(auth.access_token)
	if prefer_minimal:
		headers.append("Prefer: return=minimal")
	if independent:
		return await _client.request_json_independent(method, url, headers, body)
	return await _client.request_json(method, url, headers, body)


func _authed_request(method: String, url: String, body: String = "", independent := false, prefer_minimal := true) -> Dictionary:
	if auth != null and auth.needs_refresh():
		await _refresh_session()
	var result := await _send_with_clock_retry(method, url, body, independent, prefer_minimal)
	if _is_transport_failure(result):
		await get_tree().create_timer(0.8).timeout
		result = await _send_with_clock_retry(method, url, body, independent, prefer_minimal)
		result["retried_after_transport"] = true
	if not _is_jwt_expired(result):
		return result
	if not await _refresh_session():
		return result
	return await _send_with_clock_retry(method, url, body, independent, prefer_minimal)


func _send_with_clock_retry(method: String, url: String, body: String, independent: bool, prefer_minimal: bool) -> Dictionary:
	var result: Dictionary = await _send_authed(method, url, body, independent, prefer_minimal)
	# A token minted a moment ago can be rejected once with PGRST303 while
	# PostgREST's clock is still behind the auth server. Refreshing again
	# mints another future token, so wait and resend the same one.
	if _is_jwt_issued_in_future(result):
		print("[auth] jwt issued at future status=401, retrying same token")
		await get_tree().create_timer(1.2).timeout
		result = await _send_authed(method, url, body, independent, prefer_minimal)
	return result


func _ensure_profile() -> void:
	if not _pre_match_network_allowed():
		return
	var got: Dictionary = await _authed_request("GET", _profiles.profiles_url(auth.user_id), "", false, true)
	if got.ok and got.data is Array and not got.data.is_empty():
		return
	await get_tree().create_timer(0.25).timeout
	if not _pre_match_network_allowed():
		return
	await _authed_request("GET", _profiles.profiles_url(auth.user_id), "", false, true)


func _prepare_daily_match() -> void:
	_daily_busy = true
	await _fetch_daily_challenge()
	if _daily_stop or not _pre_match_network_allowed():
		_daily_busy = false
		return
	await _prefetch_challenge_ghosts()
	if _daily_stop or not _pre_match_network_allowed():
		_daily_busy = false
		return
	await _build_roster()
	_daily_busy = false


func _adopt_server_challenge(challenge: Dictionary) -> void:
	_challenge = challenge.duplicate(true)
	_server_as_of = int(challenge.get("as_of_unix", 0))
	if _server_as_of <= 0:
		_server_as_of = int(Time.get_unix_time_from_system())
	_local_at_fetch = int(Time.get_unix_time_from_system())
	_daily_roll_checked = ""


func _fetch_daily_challenge() -> void:
	if not _pre_match_network_allowed() or auth == null or not auth.has_session():
		_log_daily_stage("get_daily_challenge", {"status": 0, "ok": false, "error": "no_session", "session": _auth_state_label()})
		return
	var result: Dictionary = await _authed_request("POST", _seeds.challenge_url(), "{}", false, false)
	_log_rpc("get_daily_challenge", result)
	if not result.ok:
		_log_daily_stage("get_daily_challenge", {
			"status": int(result.get("status", 0)),
			"ok": false,
			"error": _safe_auth_error(result),
		})
		return
	var parsed: Dictionary = _seeds.parse_challenge(result.data)
	if parsed.is_empty():
		_log_daily_stage("get_daily_challenge", {
			"status": int(result.get("status", 0)),
			"ok": false,
			"error": "challenge_rejected",
		})
		return
	_log_daily_stage("get_daily_challenge", {
		"status": int(result.get("status", 0)),
		"ok": true,
		"date": str(parsed.get("challenge_date", "")),
		"seed": int(parsed.get("course_seed", 0)),
		"id": str(parsed.get("challenge_id", "")),
	})
	_challenge = parsed
	_server_as_of = int(parsed.get("as_of_unix", 0))
	if _server_as_of <= 0:
		_server_as_of = int(Time.get_unix_time_from_system())
	_local_at_fetch = int(Time.get_unix_time_from_system())
	_daily_roll_checked = ""


func _prefetch_challenge_ghosts() -> void:
	if not DailyChallengeScript.may_submit(_challenge):
		return
	if not _pre_match_network_allowed() or auth == null or not auth.has_session():
		return
	var key := DailyChallengeScript.cache_key(_challenge)
	var now := int(Time.get_unix_time_from_system())
	if not DailyChallengeScript.should_download_ghosts(_ghost_cache, key, now):
		return
	var cid := str(_challenge.get("challenge_id", "")).uri_encode()
	var player := str(auth.user_id).uri_encode()
	var url := (
		ConfigScript.project_url()
		+ "/rest/v1/ghost_runs?select=id,player_id,challenge_id,course_seed,display_name,fish_id,hat_id,flap_ticks,death_tick,score,physics_version,course_version"
		+ "&challenge_id=eq.%s&course_seed=eq.%d&course_version=eq.%d&physics_version=eq.%d&player_id=neq.%s&order=created_at.desc&limit=%d"
		% [cid, int(_challenge.get("course_seed", 0)), RR.COURSE_VERSION, RR.PHYSICS_VERSION, player, RR.GHOST_COUNT]
	)
	var result: Dictionary = await _authed_request("GET", url, "", false, true)
	if result.ok and result.data is Array:
		DailyChallengeScript.remember_ghosts(_ghost_cache, key, result.data, int(Time.get_unix_time_from_system()))
		_roster.erase(key)


func _build_roster() -> void:
	if not DailyChallengeScript.may_submit(_challenge):
		return
	var key := DailyChallengeScript.cache_key(_challenge)
	if _roster.has(key) and _roster[key] is Array and _roster[key].size() >= RR.GHOST_COUNT:
		return
	var seed := int(_challenge.get("course_seed", 0))
	var challenge_id := str(_challenge.get("challenge_id", ""))
	var built: Dictionary = CourseBuilderScript.generate(seed)
	var layout: Array = built["layout"]
	var lanes: PackedInt32Array = built["harpoon_lanes"]
	_log_daily_stage("layout", {
		"seed": seed,
		"pipes": layout.size(),
		"harpoons": lanes.size(),
		"id": challenge_id,
	})
	var match = GhostMatchScript.new()
	var picked: Array = match.collect_reals(seed, GameSession.player_id, "", challenge_id)
	var slot := 0
	var made := 0
	while picked.size() < RR.GHOST_COUNT:
		if _daily_stop or not _pre_match_network_allowed():
			_log_daily_stage("roster", {"count": picked.size(), "error": "cancelled"})
			return
		picked.append(FallbackScript.make(seed, slot, layout, challenge_id))
		slot += 1
		made += 1
		if made % 8 == 0:
			await get_tree().process_frame
	_roster[key] = picked
	_log_daily_stage("roster", {"count": picked.size(), "seed": seed})


func _estimated_server_date() -> String:
	var unix := DailyChallengeScript.estimated_server_unix(
		_server_as_of,
		_local_at_fetch,
		int(Time.get_unix_time_from_system())
	)
	if unix <= 0:
		return ""
	return DailyChallengeScript.challenge_date_from_unix(unix)


func _flush_uploads() -> void:
	if _pending_uploads.is_empty():
		return
	var queued: Array = _pending_uploads.duplicate()
	_pending_uploads.clear()
	for run in queued:
		await _upload_ghost_run(run)


func _pre_match_network_allowed() -> bool:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return true
	return not str(tree.current_scene.scene_file_path).ends_with("scenes/game/game.tscn")


func _upload_ghost_run(run) -> void:
	if run == null or str(run.challenge_id) == "":
		return
	var body := {
		"player_id": auth.user_id,
		"challenge_id": run.challenge_id,
		"course_seed": run.course_seed,
		"display_name": run.label(),
		"fish_id": run.fish_id,
		"hat_id": run.hat_id,
		"flap_ticks": _ticks_array(run.flap_ticks),
		"death_tick": run.death_tick,
		"score": run.score,
		"physics_version": run.physics_version,
		"course_version": run.course_version,
	}
	var result: Dictionary = await _authed_request(
		"POST",
		ConfigScript.project_url() + "/rest/v1/ghost_runs",
		JSON.stringify(body),
		true,
		true
	)
	if not result.ok:
		push_warning("[backend] ghost upload skipped: %s" % str(result.error))


func _ticks_array(ticks: PackedInt32Array) -> Array:
	var out: Array = []
	for t in ticks:
		out.append(int(t))
	return out


func _rest_headers() -> PackedStringArray:
	var headers: PackedStringArray = _client.auth_headers(auth.access_token)
	headers.append("Prefer: return=minimal")
	return headers


func leaderboard_busy() -> bool:
	return _lb_busy


func fetch_leaderboards() -> void:
	if not _pre_match_network_allowed():
		_lb_needs_refresh = true
		leaderboards_ready.emit()
		return
	if not is_configured() or not has_session():
		for period in ["daily", "weekly", "monthly"]:
			_log_leaderboard(period, {"ok": false, "status": 0, "error": "no_session"}, [])
		leaderboards_ready.emit()
		return
	if _lb_busy:
		_lb_needs_refresh = true
		leaderboards_ready.emit()
		return
	_lb_needs_refresh = false
	_fetch_leaderboards()


func on_menu_ready() -> void:
	_menu_followup()


func finalize_daily_attempt(attempt_id: String, score: int, display_name: String) -> void:
	var clean_id := attempt_id.strip_edges()
	if clean_id == "" or not is_configured() or not has_session():
		var reason := "no_attempt" if clean_id == "" else "no_session"
		_log_rpc("finalize_daily_attempt", {"ok": false, "status": 0, "error": reason})
		return
	var result: Dictionary = await _authed_request(
		"POST",
		_leaderboards.finalize_url(),
		JSON.stringify({
			"p_attempt_id": clean_id,
			"p_score": score,
			"p_display_name": display_name,
		}),
		true,
		false
	)
	_log_rpc("finalize_daily_attempt", result)
	var parsed: Dictionary = DailyAttemptScript.parse_finalize(result)
	if not parsed.get("stored", false):
		return
	print("[rpc] finalize_daily_attempt stored_score=%d accepted=%d duplicate=%d" % [
		int(parsed.get("score", 0)),
		1 if parsed.get("accepted", false) else 0,
		1 if parsed.get("duplicate", false) else 0,
	])
	if GameSession.has_method("clear_pending_finalize"):
		GameSession.clear_pending_finalize()
	_lb_needs_refresh = true
	fetch_leaderboards()


func submit_unlimited_score(score: int, display_name: String) -> void:
	if score <= 0:
		return
	var clean_name := display_name.strip_edges().substr(0, 7)
	if clean_name == "":
		clean_name = "YOU"
	if not is_configured() or not has_session():
		_log_rpc("submit_leaderboard_score", {"ok": false, "status": 0, "error": "no_session"})
		return
	var result: Dictionary = await _authed_request(
		"POST",
		_leaderboards.submit_url(),
		JSON.stringify({
			"p_score": score,
			"p_display_name": clean_name,
		}),
		true,
		false
	)
	_log_rpc("submit_leaderboard_score", result)
	if not bool(result.get("ok", false)):
		return
	if GameSession.has_method("clear_pending_unlimited_if"):
		GameSession.clear_pending_unlimited_if(score)
	_lb_needs_refresh = true
	fetch_leaderboards()


func _fetch_leaderboards() -> void:
	_lb_busy = true
	var est := _estimated_server_date()
	if est != "":
		_lb_checked_date = est
	var day: Dictionary = await _authed_request(
		"POST",
		_leaderboards.list_url(),
		JSON.stringify({"p_period": "daily"}),
		false,
		false
	)
	var week: Dictionary = await _authed_request(
		"POST",
		_leaderboards.list_url(),
		JSON.stringify({"p_period": "weekly"}),
		false,
		false
	)
	var month: Dictionary = await _authed_request(
		"POST",
		_leaderboards.list_url(),
		JSON.stringify({"p_period": "monthly"}),
		false,
		false
	)
	var day_rows: Array = _leaderboards.parse_rows(day.data) if day.ok else []
	var week_rows: Array = _leaderboards.parse_rows(week.data) if week.ok else []
	var month_rows: Array = _leaderboards.parse_rows(month.data) if month.ok else []
	if day.ok:
		global_daily = day_rows
	if week.ok:
		global_weekly = week_rows
	if month.ok:
		global_monthly = month_rows
	_log_leaderboard("daily", day, day_rows)
	_log_leaderboard("weekly", week, week_rows)
	_log_leaderboard("monthly", month, month_rows)
	if day.ok or week.ok or month.ok:
		var finished_est := _estimated_server_date()
		if finished_est != "":
			_lb_period_date = finished_est
	_lb_busy = false
	leaderboards_ready.emit()
	if _lb_needs_refresh:
		fetch_leaderboards()


func _log_leaderboard(period: String, result: Dictionary, rows: Array) -> void:
	var ok := bool(result.get("ok", false))
	var first_name := ""
	var first_score := 0
	if ok and not rows.is_empty() and typeof(rows[0]) == TYPE_DICTIONARY:
		first_name = str(rows[0].get("name", rows[0].get("display_name", "")))
		first_score = int(rows[0].get("score", 0))
	leaderboard_meta[period] = {
		"ok": ok,
		"status": int(result.get("status", 0)),
		"count": rows.size() if ok else 0,
		"name": first_name,
		"score": first_score,
	}
	print("[leaderboard] rpc=get_leaderboard params=p_period=%s status=%d transport=%s auth=%s rows=%d first=%s score=%d" % [
		period,
		int(result.get("status", 0)),
		_transport_label(result),
		_auth_state_label(),
		int(leaderboard_meta[period]["count"]),
		first_name,
		first_score,
	])
	if not ok:
		push_warning("[leaderboard] fail rpc=get_leaderboard params=p_period=%s status=%d transport=%s auth=%s error=%s" % [
			period,
			int(result.get("status", 0)),
			_transport_label(result),
			_auth_state_label(),
			_safe_auth_error(result),
		])


func _menu_followup() -> void:
	if _followup_busy or not _pre_match_network_allowed() or not has_session():
		return
	_followup_busy = true
	await _retry_pending_finalize()
	await _retry_pending_unlimited()
	if has_session() and _share_network_allowed():
		await refresh_share_rewards()
	if _lb_needs_refresh and _pre_match_network_allowed():
		fetch_leaderboards()
	_followup_busy = false


func _retry_pending_finalize() -> void:
	if not _has_pending_finalize() or not is_configured() or not has_session():
		return
	await finalize_daily_attempt(
		GameSession.pending_finalize_attempt,
		int(GameSession.pending_finalize_score),
		str(GameSession.pending_finalize_name)
	)


func _has_pending_finalize() -> bool:
	return GameSession.has_method("has_pending_finalize") and GameSession.has_pending_finalize()


func _retry_pending_unlimited() -> void:
	if not GameSession.has_method("has_pending_unlimited") or not GameSession.has_pending_unlimited():
		return
	if not is_configured() or not has_session():
		return
	await submit_unlimited_score(
		int(GameSession.pending_unlimited_score),
		str(GameSession.pending_unlimited_name)
	)


func refresh_share_rewards() -> void:
	if _share_reward_busy or not is_configured() or not has_session():
		return
	if not _share_network_allowed():
		return
	_share_reward_busy = true
	var completed: bool = GameSession.pending_first_run
	var code := ""
	if completed or GameSession.pending_referral_code != "":
		code = GameSession.pending_referral_code
		var result: Dictionary = await _authed_request(
			"POST",
			_share_rewards.sync_url(),
			_share_rewards.sync_body(code, completed),
			true,
			false
		)
		_apply_share_result(result)
		_log_share("sync_share_progress", result)
	else:
		var result: Dictionary = await _authed_request(
			"POST",
			_share_rewards.status_url(),
			"{}",
			true,
			false
		)
		_apply_share_result(result)
		_log_share("get_share_reward_status", result)
	_share_reward_busy = false
	share_rewards_changed.emit()


func note_referral_link(url: String) -> void:
	var code := ReferralRulesScript.parse_ref(url)
	if code == "" or not GameSession.has_method("remember_referral_code"):
		return
	GameSession.remember_referral_code(code)


func _share_network_allowed() -> bool:
	if _pre_match_network_allowed():
		return true
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return false
	return bool(tree.current_scene.get("finished"))


func _apply_share_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	var parsed := ReferralRulesScript.parse_status(result.get("data", {}))
	if GameSession.has_method("apply_share_result"):
		var delta: int = GameSession.apply_share_result(parsed, int(result.get("status", 0)), true)
		if delta > 0:
			print("[share] granted_coins=%d" % delta)


func _auth_state_label() -> String:
	if auth == null:
		return "no_auth"
	if not auth.has_session():
		return "refresh_only" if auth.has_refresh_token() else "no_session"
	return "fresh" if auth.access_token_fresh() else "stale"


func _transport_label(result: Dictionary) -> String:
	var code := int(result.get("godot_http_result", -1))
	if code < 0:
		return "none"
	var name := "other"
	match code:
		HTTPRequest.RESULT_SUCCESS:
			name = "success"
		HTTPRequest.RESULT_CANT_CONNECT:
			name = "cant_connect"
		HTTPRequest.RESULT_CANT_RESOLVE:
			name = "cant_resolve"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			name = "connection_error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			name = "tls"
		HTTPRequest.RESULT_NO_RESPONSE:
			name = "no_response"
		HTTPRequest.RESULT_TIMEOUT:
			name = "timeout"
	return "%s(%d)" % [name, code]


func _log_share(rpc_name: String, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_log_rpc(rpc_name, result)
		return
	var parsed := ReferralRulesScript.parse_status(result.get("data", {}))
	print("[share] %s status=%d attach=%s qualified=%d granted=%d first_run=%s" % [
		rpc_name,
		int(result.get("status", 0)),
		str(parsed.get("attach", "")),
		int(parsed.get("qualified", 0)),
		int(parsed.get("granted_coins", 0)),
		str(bool(parsed.get("first_run", false))),
	])


func mission_busy() -> bool:
	return _mission_busy


func refresh_daily_missions() -> void:
	flush_daily_missions()


func flush_daily_missions() -> void:
	if _mission_busy:
		_mission_flush_again = true
		return
	if not is_configured() or _missions == null:
		if GameSession.mission_board.is_empty():
			mission_note = "error"
			daily_missions_changed.emit()
		return
	if not has_session():
		if GameSession.mission_board.is_empty():
			mission_note = "loading"
			daily_missions_changed.emit()
		return
	_mission_claim_blocked = ""
	_mission_busy = true
	if GameSession.mission_board.is_empty():
		mission_note = "loading"
		daily_missions_changed.emit()
	var pending: Array = GameSession.pending_mission_runs.duplicate()
	var stopped := false
	for run in pending:
		if typeof(run) != TYPE_DICTIONARY:
			continue
		var result: Dictionary = await _authed_request(
			"POST",
			_missions.record_url(),
			_missions.record_body(
				str(run.get("id", "")),
				int(run.get("pipes", 0)),
				int(run.get("seconds", 0)),
				int(run.get("coins", 0))
			),
			true,
			false
		)
		var data: Variant = result.get("data", {})
		var reason := ""
		var accepted := false
		if typeof(data) == TYPE_DICTIONARY:
			reason = str(data.get("reason", ""))
			accepted = bool(data.get("ok", false))
		if reason == "rejected" or reason == "duplicate" or accepted:
			GameSession.drop_mission_run(str(run.get("id", "")))
			if accepted:
				GameSession.apply_mission_board(data)
		else:
			stopped = true
			break
	if not stopped:
		var board_result: Dictionary = await _authed_request("POST", _missions.board_url(), "{}", true, false)
		var board: Variant = board_result.get("data", {})
		if bool(board_result.get("ok", false)) and typeof(board) == TYPE_DICTIONARY and bool(board.get("ok", false)):
			GameSession.apply_mission_board(board)
			mission_note = ""
		elif GameSession.mission_board.is_empty():
			mission_note = "error"
	elif GameSession.mission_board.is_empty():
		mission_note = "error"
	_mission_busy = false
	daily_missions_changed.emit()
	_finish_mission_flush()


func claim_daily_mission(slot: String) -> void:
	if _mission_busy:
		_mission_auto_claim = true
		return
	var board: Dictionary = GameSession.mission_board if GameSession.mission_board is Dictionary else {}
	var wanted := DailyMissionsScript.next_auto_claim(board, _mission_claim_blocked)
	if wanted == "":
		return
	slot = wanted
	if not is_configured() or not has_session() or _missions == null:
		_mission_claim_blocked = slot
		return
	_mission_busy = true
	var result: Dictionary = await _authed_request(
		"POST",
		_missions.claim_url(),
		_missions.claim_body(slot),
		true,
		false
	)
	var data: Variant = result.get("data", {})
	var credited := bool(result.get("ok", false)) and typeof(data) == TYPE_DICTIONARY and bool(data.get("ok", false))
	var reason := ""
	var granted := 0
	if typeof(data) == TYPE_DICTIONARY:
		reason = str(data.get("reason", ""))
		granted = int(data.get("granted_now", 0))
	if credited:
		var delta := GameSession.apply_mission_board(data)
		mission_note = ""
		var follow := DailyMissionsScript.next_auto_claim(GameSession.mission_board)
		# The same slot still being eligible means the board did not record the claim.
		_mission_claim_blocked = slot if follow == slot else ""
		if delta > 0:
			print("[missions] claimed slot=%s coins=%d" % [slot, delta])
		# "already" and board refreshes credit nothing new, so they stay silent.
		if reason == "claimed" and granted > 0:
			var mission_date := str(GameSession.mission_board.get("mission_date", ""))
			mission_reward_granted.emit(slot, granted, mission_date)
	else:
		_mission_claim_blocked = slot
		if not bool(result.get("ok", false)):
			_log_rpc("claim_daily_mission", result)
		if GameSession.mission_board.is_empty():
			mission_note = "error"
	_mission_busy = false
	daily_missions_changed.emit()
	_finish_mission_flush()


func _schedule_auto_claim() -> void:
	if _mission_busy:
		_mission_auto_claim = true
		return
	var board: Dictionary = GameSession.mission_board if GameSession.mission_board is Dictionary else {}
	var date := str(board.get("mission_date", ""))
	if date != _mission_claim_date:
		if _mission_claim_date != "":
			_mission_claim_blocked = ""
		_mission_claim_date = date
	var slot := DailyMissionsScript.next_auto_claim(board, _mission_claim_blocked)
	if slot == "":
		return
	claim_daily_mission(slot)


func _finish_mission_flush() -> void:
	if _mission_flush_again:
		_mission_flush_again = false
		_mission_auto_claim = false
		call_deferred("flush_daily_missions")
		return
	_mission_auto_claim = false
	_schedule_auto_claim()
