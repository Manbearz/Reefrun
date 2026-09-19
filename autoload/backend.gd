extends Node

# Orchestrates Supabase stages. Safe no-op when config is empty or the network fails.

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")
const ClientScript := preload("res://scripts/backend/supabase_client.gd")
const AuthScript := preload("res://scripts/backend/supabase_auth.gd")
const ProfileScript := preload("res://scripts/backend/profile_service.gd")
const CourseSeedScript := preload("res://scripts/backend/course_seed_service.gd")
const LeaderboardScript := preload("res://scripts/backend/leaderboard_repository.gd")
const GhostRunScript := preload("res://scripts/ghost_run.gd")

signal signed_in(user_id: String)
signal identity_ready
signal leaderboards_ready

var auth = null
var _client = null
var _profiles = null
var _seeds = null
var _leaderboards = null
var global_weekly: Array = []
var global_monthly: Array = []
var _lb_busy := false
var _ghost_cache: Dictionary = {}
var _pending_uploads: Array = []
var _shared_seed := 0
var _busy := false
var _auth_logged := false
var _refresh_busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	auth = AuthScript.new()
	_client = ClientScript.new(self)
	_profiles = ProfileScript.new()
	_seeds = CourseSeedScript.new()
	_leaderboards = LeaderboardScript.new()
	if not ConfigScript.is_configured():
		_resolve_identity()
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
	return _shared_seed != 0


func shared_course_seed() -> int:
	return _shared_seed


func _resolve_identity() -> void:
	if not has_session():
		GameSession.ensure_local_fallback_id()
	_auth_logged = true
	identity_ready.emit()


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
		for key in ["error", "error_description", "message", "msg", "msg_code"]:
			var value := str(data.get(key, "")).strip_edges()
			if value.is_empty():
				continue
			if value.begins_with("eyJ") or value.contains("sb_secret") or value.contains("service_role"):
				continue
			parts.append(value)
	elif typeof(data) == TYPE_STRING:
		var text := str(data).strip_edges()
		if not text.is_empty() and not text.begins_with("eyJ") and text.length() < 240:
			parts.append(text)
	var fallback := str(result.get("error", "")).strip_edges()
	if not fallback.is_empty() and not fallback.begins_with("eyJ"):
		parts.append(fallback)
	return ", ".join(parts)


func cached_ghost_runs(course_seed: int) -> Array:
	var key := str(course_seed)
	if _ghost_cache.has(key):
		return _ghost_cache[key]
	return []


func upload_ghost_run(run) -> void:
	if run == null or not is_configured() or auth == null or not auth.has_session():
		return
	_pending_uploads.append(run)
	call_deferred("_flush_uploads")


func cancel_pre_match_requests() -> void:
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
	var data: Variant = result.get("data", null)
	if typeof(data) == TYPE_DICTIONARY:
		var code := str(data.get("code", data.get("error_code", ""))).to_lower()
		if code == "pgrst301" or code.find("jwt") >= 0:
			return true
	var err := _safe_auth_error(result).to_lower()
	return err.find("jwt expired") >= 0 or err.find("invalid jwt") >= 0


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
	var result: Dictionary = await _send_authed(method, url, body, independent, prefer_minimal)
	if not _is_jwt_expired(result):
		return result
	if not await _refresh_session():
		return result
	return await _send_authed(method, url, body, independent, prefer_minimal)


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


func _refresh_shared_seed() -> void:
	if not _pre_match_network_allowed():
		return
	var result: Dictionary = await _authed_request("GET", _seeds.current_url(), "", false, true)
	if result.ok:
		_shared_seed = _seeds.parse_seed(result.data)


func prefetch_ghosts(course_seed: int) -> void:
	if course_seed == 0:
		return
	if not _pre_match_network_allowed():
		return
	if not is_configured() or auth == null or not auth.has_session():
		return
	var url := (
		ConfigScript.project_url()
		+ "/rest/v1/ghost_runs?select=id,player_id,course_seed,display_name,fish_id,hat_id,flap_ticks,death_tick,score,physics_version,course_version,created_at"
		+ "&course_seed=eq.%d&course_version=eq.%d&physics_version=eq.%d&limit=%d"
		% [course_seed, RR.COURSE_VERSION, RR.PHYSICS_VERSION, RR.GHOST_COUNT]
	)
	var result: Dictionary = await _authed_request("GET", url, "", false, true)
	if result.ok and result.data is Array:
		_ghost_cache[str(course_seed)] = result.data


func _flush_uploads() -> void:
	if _pending_uploads.is_empty():
		return
	var queued: Array = _pending_uploads.duplicate()
	_pending_uploads.clear()
	for run in queued:
		await _upload_ghost_run(run)


func _menu_seed() -> int:
	if _shared_seed != 0:
		return _shared_seed
	return GameSession.course_seed


func _pre_match_network_allowed() -> bool:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return true
	return not str(tree.current_scene.scene_file_path).ends_with("scenes/game/game.tscn")


func _upload_ghost_run(run) -> void:
	var body := {
		"player_id": auth.user_id,
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
		false,
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


func fetch_leaderboards() -> void:
	if _lb_busy or not is_configured() or not has_session():
		leaderboards_ready.emit()
		return
	if not _pre_match_network_allowed():
		leaderboards_ready.emit()
		return
	_fetch_leaderboards()


func submit_leaderboard_score(score: int, display_name: String) -> void:
	if score <= 0 or not is_configured() or not has_session():
		return
	_submit_leaderboard_score(score, display_name)


func _fetch_leaderboards() -> void:
	_lb_busy = true
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
	if week.ok:
		global_weekly = _leaderboards.parse_rows(week.data)
	if month.ok:
		global_monthly = _leaderboards.parse_rows(month.data)
	_lb_busy = false
	leaderboards_ready.emit()


func _submit_leaderboard_score(score: int, display_name: String) -> void:
	var result: Dictionary = await _authed_request(
		"POST",
		_leaderboards.submit_url(),
		JSON.stringify({
			"p_score": score,
			"p_display_name": display_name,
		}),
		true,
		true
	)
	if not result.ok:
		push_warning("[leaderboard] submit skipped: %s" % _safe_auth_error(result))
