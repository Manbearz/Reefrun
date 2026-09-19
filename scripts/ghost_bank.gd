extends RefCounted

const GhostRunScript := preload("res://scripts/ghost_run.gd")
const DIR := "user://ghost_runs"


func get_runs(course_seed: int) -> Array:
	var out: Array = []
	var cfg := ConfigFile.new()
	if cfg.load(_path(course_seed)) != OK:
		return out
	var count := int(cfg.get_value("meta", "count", 0))
	for i in count:
		var run = _read_run(cfg, "run_%d" % i)
		if run == null or not run.is_valid():
			continue
		if run.course_seed != course_seed:
			continue
		out.append(run)
	return out


func save_run(run) -> void:
	if run == null or not run.is_valid():
		return
	_ensure_dir()
	var path := _path(run.course_seed)
	var cfg := ConfigFile.new()
	cfg.load(path)
	var count := int(cfg.get_value("meta", "count", 0))
	if count >= RR.GHOST_COUNT:
		_compact_oldest(cfg, count)
		count = int(cfg.get_value("meta", "count", 0))
	_write_run(cfg, "run_%d" % count, run)
	cfg.set_value("meta", "count", count + 1)
	cfg.set_value("meta", "course_seed", run.course_seed)
	cfg.save(path)


func _read_run(cfg: ConfigFile, sec: String):
	if not cfg.has_section(sec):
		return null
	var run = GhostRunScript.new()
	run.version = int(cfg.get_value(sec, "version", 1))
	run.physics_version = int(cfg.get_value(sec, "physics_version", 1))
	run.course_version = int(cfg.get_value(sec, "course_version", 1))
	run.course_seed = int(cfg.get_value(sec, "course_seed", 0))
	run.player_name = str(cfg.get_value(sec, "player_name", "YOU"))
	run.display_name = str(cfg.get_value(sec, "display_name", run.player_name))
	run.fish_id = str(cfg.get_value(sec, "fish_id", "fish_blue"))
	run.hat_id = int(cfg.get_value(sec, "hat_id", -1))
	run.death_tick = int(cfg.get_value(sec, "death_tick", -1))
	run.score = int(cfg.get_value(sec, "score", 0))
	run.source = str(cfg.get_value(sec, "source", GhostRunScript.SOURCE_REAL))
	run.run_id = str(cfg.get_value(sec, "run_id", ""))
	run.player_id = str(cfg.get_value(sec, "player_id", ""))
	run.created_at = int(cfg.get_value(sec, "created_at", 0))
	var flaps: Variant = cfg.get_value(sec, "flap_ticks", PackedInt32Array())
	if flaps is PackedInt32Array:
		run.flap_ticks = flaps
	if run.display_name.is_empty():
		run.display_name = run.player_name
	return run


func _write_run(cfg: ConfigFile, sec: String, run) -> void:
	cfg.set_value(sec, "version", run.version)
	cfg.set_value(sec, "physics_version", run.physics_version)
	cfg.set_value(sec, "course_version", run.course_version)
	cfg.set_value(sec, "course_seed", run.course_seed)
	cfg.set_value(sec, "player_name", run.player_name)
	cfg.set_value(sec, "display_name", run.label())
	cfg.set_value(sec, "fish_id", run.fish_id)
	cfg.set_value(sec, "hat_id", run.hat_id)
	cfg.set_value(sec, "death_tick", run.death_tick)
	cfg.set_value(sec, "score", run.score)
	cfg.set_value(sec, "flap_ticks", run.flap_ticks)
	cfg.set_value(sec, "source", run.source)
	cfg.set_value(sec, "run_id", run.run_id)
	cfg.set_value(sec, "player_id", run.player_id)
	cfg.set_value(sec, "created_at", run.created_at)


func _compact_oldest(cfg: ConfigFile, count: int) -> void:
	var kept: Array = []
	for i in range(1, count):
		var run = _read_run(cfg, "run_%d" % i)
		if run:
			kept.append(run)
	for sec in cfg.get_sections():
		cfg.erase_section(sec)
	for i in kept.size():
		_write_run(cfg, "run_%d" % i, kept[i])
	cfg.set_value("meta", "count", kept.size())


func _ensure_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if not dir.dir_exists("ghost_runs"):
		dir.make_dir("ghost_runs")


func _path(course_seed: int) -> String:
	return "%s/%d.cfg" % [DIR, course_seed]
