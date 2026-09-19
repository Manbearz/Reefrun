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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	auth = AuthScript.new()
	_client = ClientScript.new(self)
	_profiles = ProfileScript.new()
	_seeds = CourseSeedScript.new()
	if not ConfigScript.is_configured():
		print("[backend] Supabase not configured; using local/fallback only")
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


func has_shared_seed() -> bool:
	return _shared_seed != 0


func shared_course_seed() -> int:
	return _shared_seed


func _resolve_identity() -> void:
	if _auth_logged:
		return
	_auth_logged = true
	print("[AUTH] Player ID: %s" % GameSession.player_id)
	print("[AUTH] Source: %s" % auth_source_label())
	identity_ready.emit()


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
	_prepare_menu()


func _prepare_menu() -> void:
	if _busy:
		return
	if auth == null or not auth.has_session():
		_bootstrap()
		return
	if not _pre_match_network_allowed():
		return
	_busy = true
	await _refresh_shared_seed()
	if _pre_match_network_allowed():
		await prefetch_ghosts(_menu_seed())
	_busy = false


func _bootstrap() -> void:
	if _busy:
		return
	_busy = true
	if auth.load_session() and _pre_match_network_allowed():
		await _refresh_if_needed()
	if not auth.has_session() and _pre_match_network_allowed():
		await _sign_in_anonymous()
	if auth.has_session():
		GameSession.player_id = auth.user_id
		GameSession._save()
		signed_in.emit(auth.user_id)
		if _pre_match_network_allowed():
			await _ensure_profile()
		if _pre_match_network_allowed():
			await _refresh_shared_seed()
		if _pre_match_network_allowed():
			await prefetch_ghosts(_menu_seed())
	_busy = false
	_resolve_identity()


func _sign_in_anonymous() -> void:
	if not _pre_match_network_allowed():
		return
	var result: Dictionary = await _client.request_json(
		"POST",
		auth.signup_url(),
		_client.auth_headers(),
		JSON.stringify({"data": {}})
	)
	if not result.ok or not auth.apply_payload(result.data):
		push_warning("[backend] anonymous sign-in skipped: %s" % str(result.error))


func _refresh_if_needed() -> void:
	if not _pre_match_network_allowed():
		return
	if auth.expires_at > int(Time.get_unix_time_from_system()) + 30:
		return
	if auth.refresh_token.is_empty():
		return
	var result: Dictionary = await _client.request_json(
		"POST",
		auth.refresh_url(),
		_client.auth_headers(),
		JSON.stringify({"refresh_token": auth.refresh_token})
	)
	if result.ok:
		auth.apply_payload(result.data)


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
