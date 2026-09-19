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


func load_session() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(ConfigScript.SESSION_PATH) != OK:
		return false
	access_token = str(cfg.get_value("session", "access_token", ""))
	refresh_token = str(cfg.get_value("session", "refresh_token", ""))
	user_id = str(cfg.get_value("session", "user_id", ""))
	expires_at = int(cfg.get_value("session", "expires_at", 0))
	return has_session()


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
	var session: Variant = data.get("session", data)
	if typeof(session) != TYPE_DICTIONARY:
		return false
	access_token = str(session.get("access_token", ""))
	refresh_token = str(session.get("refresh_token", ""))
	var user: Variant = data.get("user", session.get("user", {}))
	if typeof(user) == TYPE_DICTIONARY:
		user_id = str(user.get("id", ""))
	var expires_in := int(session.get("expires_in", 3600))
	expires_at = int(Time.get_unix_time_from_system()) + expires_in
	if has_session():
		save_session()
		return true
	return false


func signup_url() -> String:
	return ConfigScript.project_url() + "/auth/v1/signup"


func refresh_url() -> String:
	return ConfigScript.project_url() + "/auth/v1/token?grant_type=refresh_token"
