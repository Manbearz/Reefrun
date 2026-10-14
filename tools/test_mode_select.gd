extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var backend = get_root().get_node_or_null("Backend")
	var session = get_root().get_node_or_null("GameSession")
	var ready: bool = backend != null and backend.has_method("daily_challenge_ready") and backend.daily_challenge_ready()
	var no_auto_ghosts: bool = backend != null and not backend.has_method("_kick_daily_prep")
	session.match_mode = session.MODE_DAILY
	session.commit_match_challenge({"challenge_id": "daily:2026-10-12:cv1:pv1", "course_seed": 750528330, "server_confirmed": false})
	var kept: bool = session.match_mode == session.MODE_DAILY and session.current_challenge_id().begins_with("daily:")
	session.match_mode = session.MODE_UNLIMITED
	session.active_challenge = {"challenge_id": "", "course_seed": 5, "server_confirmed": false}
	session.course_seed = 5
	var unlimited: bool = session.current_challenge_id() == "" and session.match_mode == session.MODE_UNLIMITED
	var ok: bool = ready and no_auto_ghosts and kept and unlimited
	print("[mode] ok=%s ready=%s kept_daily=%s unlimited=%s" % [ok, ready, kept, unlimited])
	quit(0 if ok else 1)
