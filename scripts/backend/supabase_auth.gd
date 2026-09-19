extends RefCounted

# STAGE 2 — anonymous auth.
# Later: link this anonymous user to Apple / Google via supabase.auth.linkIdentity.
# Do not put service-role keys here.

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")

var access_token := ""
var refresh_token := ""
var user_id := ""
var expires_at := 0


func has_session() -> bool:
	return not access_token.is_empty() and not user_id.is_empty()


func can_restore() -> bool:
	return not user_id.is_empty() and (not access_token.is_empty() or not refresh_token.is_empty())


func load_session() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(ConfigScript.SESSION_PATH) != OK:
		return false
	access_token = str(cfg.get_value("session", "access_token", ""))
	refresh_token = str(cfg.get_value("session", "refresh_token", ""))
	user_id = str(cfg.get_value("session", "user_id", ""))
	expires_at = int(cfg.get_value("session", "expires_at", 0))
	return can_restore()


func save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "access_token", access_token)
	cfg.set_value("session", "refresh_token", refresh_token)
	cfg.set_value("session", "user_id", user_id)
	cfg.set_value("session", "expires_at", expires_at)
	cfg.save(ConfigScript.SESSION_PATH)


func apply_payload(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var root: Dictionary = data
	var session: Dictionary = root
	var session_raw: Variant = root.get("session", null)
	if typeof(session_raw) == TYPE_DICTIONARY:
		session = session_raw
	var token := str(session.get("access_token", root.get("access_token", "")))
	var refresh := str(session.get("refresh_token", root.get("refresh_token", "")))
	var uid := _extract_user_id(root, session)
	if token.is_empty():
		return false
	access_token = token
	refresh_token = refresh
	if not uid.is_empty():
		user_id = uid
	var expires_in := int(session.get("expires_in", root.get("expires_in", 3600)))
	var explicit_exp := int(session.get("expires_at", root.get("expires_at", 0)))
	if explicit_exp > 100000:
		expires_at = explicit_exp
	else:
		expires_at = int(Time.get_unix_time_from_system()) + maxi(expires_in, 60)
	save_session()
	return has_session()


func apply_user_id(uid: String) -> bool:
	var clean := uid.strip_edges()
	if clean.is_empty() or clean.begins_with("local_"):
		return false
	user_id = clean
	if has_session():
		save_session()
		return true
	return false


func _extract_user_id(root: Dictionary, session: Dictionary) -> String:
	for block in [root.get("user", null), session.get("user", null)]:
		if typeof(block) == TYPE_DICTIONARY:
			var uid := str(block.get("id", "")).strip_edges()
			if not uid.is_empty():
				return uid
	return ""


func signup_url() -> String:
	return ConfigScript.project_url() + "/auth/v1/signup"


func refresh_url() -> String:
	return ConfigScript.project_url() + "/auth/v1/token?grant_type=refresh_token"


func user_url() -> String:
	return ConfigScript.project_url() + "/auth/v1/user"
