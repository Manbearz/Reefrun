extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var backend: Node = root.get_node_or_null("Backend")
	var session_node: Node = root.get_node_or_null("GameSession")
	if backend == null:
		print("[AUTH] Error: Backend autoload missing")
		quit(1)
		return
	var waited := 0.0
	while waited < 12.0:
		if backend.get("_auth_logged") == true:
			break
		await create_timer(0.25).timeout
		waited += 0.25
	var session: bool = false
	if backend.has_method("has_session"):
		session = bool(backend.has_session())
	var player_id := ""
	if session_node:
		player_id = str(session_node.get("player_id"))
	print("[AUTH-TEST] configured=%s session=%s player_id=%s waited=%.1f" % [
		backend.call("is_configured") if backend.has_method("is_configured") else false,
		session,
		player_id,
		waited,
	])
	quit(0 if session and not player_id.begins_with("local_") and not player_id.is_empty() else 1)
