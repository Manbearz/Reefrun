extends "res://scripts/ghost_repository.gd"

const GhostRunScript := preload("res://scripts/ghost_run.gd")


func get_runs_for_seed(course_seed: int) -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return []
	var backend: Node = tree.root.get_node_or_null("/root/Backend")
	if backend == null or not backend.has_method("cached_ghost_runs"):
		return []
	var rows: Array = backend.cached_ghost_runs(course_seed)
	var out: Array = []
	for row in rows:
		var run = _from_row(row)
		if run and run.is_valid() and run.course_seed == course_seed:
			out.append(run)
	return out


func _from_row(row: Variant):
	if typeof(row) != TYPE_DICTIONARY:
		return null
	var run = GhostRunScript.new()
	run.course_seed = int(row.get("course_seed", 0))
	run.physics_version = int(row.get("physics_version", 1))
	run.course_version = int(row.get("course_version", 1))
	run.display_name = str(row.get("display_name", "YOU"))
	run.player_name = run.display_name
	run.fish_id = str(row.get("fish_id", "fish_blue"))
	run.hat_id = int(row.get("hat_id", -1))
	run.death_tick = int(row.get("death_tick", -1))
	run.score = int(row.get("score", 0))
	run.source = GhostRunScript.SOURCE_REAL
	run.run_id = str(row.get("id", row.get("run_id", "")))
	run.player_id = str(row.get("player_id", ""))
	run.created_at = _unix(row.get("created_at", 0))
	var flaps: Variant = row.get("flap_ticks", [])
	var packed := PackedInt32Array()
	if flaps is Array:
		for v in flaps:
			packed.append(int(v))
	elif flaps is PackedInt32Array:
		packed = flaps
	run.flap_ticks = packed
	return run


func _unix(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	var text := str(value)
	if text.is_empty():
		return 0
	return int(Time.get_unix_time_from_datetime_string(text))
