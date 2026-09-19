extends Node

# Orchestrates Supabase stages. Safe no-op when config is empty or the network fails.

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")
const ClientScript := preload("res://scripts/backend/supabase_client.gd")
const AuthScript := preload("res://scripts/backend/supabase_auth.gd")
const ProfileScript := preload("res://scripts/backend/profile_service.gd")
const CourseSeedScript := preload("res://scripts/backend/course_seed_service.gd")
const GhostRunScript := preload("res://scripts/ghost_run.gd")

signal signed_in(user_id: String)
signal identity_ready

var auth = null
var _client = null
var _profiles = null
var _seeds = null
var _ghost_cache: Dictionary = {}
var _pending_uploads: Array = []
var _shared_seed := 0
var _busy := false
var _auth_logged := false
var _diag_printed := false
var last_auth_diag: Dictionary = {
	"url_configured": "NO",
	"key_configured": "NO",
	"request_sent": "NO",
	"http_status": "-",
	"auth_result": "not_attempted",
	"auth_error": "",
	"godot_error": "",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	auth = AuthScript.new()
	_client = ClientScript.new(self)
	_profiles = ProfileScript.new()
	_seeds = CourseSeedScript.new()
	_reset_auth_diag()
	if not ConfigScript.is_configured():
		_resolve_identity()
		return
	_bootstrap()


func is_configured() -> bool:
	return ConfigScript.is_configured()


func has_session() -> bool:
	return auth != null and auth.has_session()


func auth_source_label() -> String:
	return "Supabase Anonymous" if has_session() else "Local Fallback"


func supabase_status_label() -> String:
	return "Connected" if has_session() else "Not Connected"


func _reset_auth_diag() -> void:
	last_auth_diag["url_configured"] = "YES" if not ConfigScript.project_url().is_empty() else "NO"
	last_auth_diag["key_configured"] = "YES" if not ConfigScript.anon_key().is_empty() else "NO"
	last_auth_diag["request_sent"] = "NO"
	last_auth_diag["http_status"] = "-"
	last_auth_diag["auth_result"] = "not_attempted"
	last_auth_diag["auth_error"] = ""
	last_auth_diag["godot_error"] = ""


func _record_auth_diag(result: Dictionary, applied: bool) -> void:
	last_auth_diag["request_sent"] = "YES"
	last_auth_diag["http_status"] = str(int(result.get("status", 0)))
	last_auth_diag["auth_result"] = "success" if applied and has_session() else "failed"
	last_auth_diag["auth_error"] = "" if applied else _safe_auth_error(result)
	var req_err := int(result.get("godot_request_error", 0))
	var http_res := int(result.get("godot_http_result", -1))
	var godot_bits: PackedStringArray = PackedStringArray()
	if req_err != OK:
		godot_bits.append("request %s (%d)" % [error_string(req_err), req_err])
	if http_res >= 0 and http_res != HTTPRequest.RESULT_SUCCESS:
		godot_bits.append("http %s (%d)" % [_http_result_name(http_res), http_res])
	last_auth_diag["godot_error"] = ", ".join(godot_bits)


func _http_result_name(code: int) -> String:
	match code:
		HTTPRequest.RESULT_SUCCESS:
			return "RESULT_SUCCESS"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "RESULT_CANT_CONNECT"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "RESULT_CANT_RESOLVE"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "RESULT_CONNECTION_ERROR"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "RESULT_TLS_HANDSHAKE_ERROR"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "RESULT_NO_RESPONSE"
		HTTPRequest.RESULT_TIMEOUT:
			return "RESULT_TIMEOUT"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "RESULT_REQUEST_FAILED"
		_:
			return "RESULT_%d" % code


func _print_auth_diag_once() -> void:
	if _diag_printed:
		return
	_diag_printed = true
	print("[AUTH-DIAG] SUPABASE URL CONFIGURED: %s" % last_auth_diag["url_configured"])
	print("[AUTH-DIAG] PUBLISHABLE KEY CONFIGURED: %s" % last_auth_diag["key_configured"])
	print("[AUTH-DIAG] AUTH REQUEST SENT: %s" % last_auth_diag["request_sent"])
	print("[AUTH-DIAG] HTTP STATUS: %s" % last_auth_diag["http_status"])
	print("[AUTH-DIAG] AUTH RESULT: %s" % last_auth_diag["auth_result"])
	var err := str(last_auth_diag["auth_error"])
	if not err.is_empty():
		print("[AUTH-DIAG] AUTH ERROR: %s" % err)
	var godot_err := str(last_auth_diag["godot_error"])
	if not godot_err.is_empty():
		print("[AUTH-DIAG] GODOT ERROR: %s" % godot_err)


func has_shared_seed() -> bool:
	return _shared_seed != 0


func shared_course_seed() -> int:
	return _shared_seed


func _resolve_identity() -> void:
	if not has_session():
		GameSession.ensure_local_fallback_id()
	if _auth_logged:
		_print_auth_diag_once()
		identity_ready.emit()
		return
	_auth_logged = true
	print("[AUTH] Player ID: %s" % GameSession.player_id)
	print("[AUTH] Source: %s" % auth_source_label())
	_print_auth_diag_once()
	identity_ready.emit()


func _adopt_supabase_user(uid: String) -> void:
	if uid.is_empty() or uid.begins_with("local_"):
		return
	GameSession.adopt_supabase_id(uid)
	signed_in.emit(uid)


func _log_auth_result(status: Variant, success: bool, supabase_id: String, error_text: String = "") -> void:
	print("[AUTH] HTTP status: %s" % str(status))
	print("[AUTH] Success: %s" % ("YES" if success else "NO"))
	if success:
		print("[AUTH] Supabase user.id: %s" % supabase_id)
	print("[AUTH] GameSession.player_id: %s" % (GameSession.player_id if not GameSession.player_id.is_empty() else "(empty)"))
	if not success and not error_text.is_empty():
		print("[AUTH] Error: %s" % error_text)
		if str(error_text).findn("Anonymous sign-ins are disabled") >= 0:
			print("[AUTH] Enable Authentication → Sign In / Providers → Anonymous in the Supabase dashboard.")


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
	if _busy or has_session() or _auth_logged:
		return
	_bootstrap()


func _bootstrap() -> void:
	if _busy:
		return
	_busy = true
	if auth.load_session():
		if not auth.user_id.is_empty() and not auth.user_id.begins_with("local_"):
			_adopt_supabase_user(auth.user_id)
			print("[AUTH] Request started")
			_log_auth_result("restored", true, auth.user_id)
		if _pre_match_network_allowed() and not auth.has_session():
			await _refresh_if_needed()
	if not auth.has_session() and _pre_match_network_allowed():
		await _sign_in_anonymous()
	if auth.has_session():
		_adopt_supabase_user(auth.user_id)
	_busy = false
	_resolve_identity()


func _sign_in_anonymous() -> void:
	if not _pre_match_network_allowed():
		return
	print("[AUTH] Request started")
	last_auth_diag["request_sent"] = "YES"
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
	_record_auth_diag(result, applied and has_session())
	var uid := ""
	if auth:
		uid = str(auth.user_id)
	_log_auth_result(
		result.status,
		applied and has_session(),
		uid,
		"" if applied else _safe_auth_error(result)
	)


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


func _refresh_if_needed() -> void:
	if not _pre_match_network_allowed():
		return
	if auth.has_session() and auth.expires_at > int(Time.get_unix_time_from_system()) + 30:
		return
	if auth.refresh_token.is_empty():
		return
	var result: Dictionary = await _client.request_json(
		"POST",
		auth.refresh_url(),
		_client.auth_headers(),
		JSON.stringify({"refresh_token": auth.refresh_token})
	)
	var applied: bool = bool(result.ok) and auth.apply_payload(result.data)
	if applied:
		_adopt_supabase_user(auth.user_id)


func _ensure_profile() -> void:
	if not _pre_match_network_allowed():
		return
	var got: Dictionary = await _client.request_json(
		"GET",
		_profiles.profiles_url(auth.user_id),
		_rest_headers()
	)
	if got.ok and got.data is Array and not got.data.is_empty():
		return
	await get_tree().create_timer(0.25).timeout
	if not _pre_match_network_allowed():
		return
	await _client.request_json("GET", _profiles.profiles_url(auth.user_id), _rest_headers())


func _refresh_shared_seed() -> void:
	if not _pre_match_network_allowed():
		return
	var result: Dictionary = await _client.request_json("GET", _seeds.current_url(), _rest_headers())
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
	var result: Dictionary = await _client.request_json("GET", url, _rest_headers())
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
	var result: Dictionary = await _client.request_json(
		"POST",
		ConfigScript.project_url() + "/rest/v1/ghost_runs",
		_rest_headers(),
		JSON.stringify(body)
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
