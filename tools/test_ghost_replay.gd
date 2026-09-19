extends SceneTree

const CourseBuilderScript := preload("res://scripts/course_builder.gd")
const GhostBankScript := preload("res://scripts/ghost_bank.gd")
const GhostRunScript := preload("res://scripts/ghost_run.gd")
const GhostMatchScript := preload("res://scripts/ghost_match.gd")
const DT := 1.0 / 60.0


func _init() -> void:
	var course_ok: bool = CourseBuilderScript.validate_determinism(827361)
	course_ok = CourseBuilderScript.validate_determinism(1) and course_ok
	var store_ok := _test_store()
	var fill_ok := _test_fill()
	var flaps := PackedInt32Array()
	flaps.append(0)
	for t in range(1, 240):
		if t % 18 == 0:
			flaps.append(t)
	var a := _sim(flaps, 240)
	var b := _sim(flaps, 240)
	var path_ok := a.size() == b.size()
	for i in a.size():
		if not is_equal_approx(a[i], b[i]):
			path_ok = false
			push_error("path mismatch t=%d %s %s" % [i, a[i], b[i]])
			break
	print("[replay] identical path=%s samples=%d last_y=%.3f store=%s fill=%s" % [path_ok, a.size(), a[a.size() - 1], store_ok, fill_ok])
	quit(0 if course_ok and path_ok and store_ok and fill_ok else 1)


func _test_store() -> bool:
	var seed := 424242
	var run = GhostRunScript.new()
	run.course_seed = seed
	run.player_name = "TEST"
	run.display_name = "TEST"
	run.fish_id = "fish_blue"
	run.hat_id = 3
	run.flap_ticks = PackedInt32Array([0, 14, 39, 63])
	run.death_tick = 80
	run.score = 3
	run.source = GhostRunScript.SOURCE_REAL
	run.player_id = "p1"
	run.run_id = "run-1"
	var bank = GhostBankScript.new()
	bank.save_run(run)
	var loaded: Array = bank.get_runs(seed)
	var ok := loaded.size() == 1
	if ok:
		var got = loaded[0]
		ok = (
			got.label() == "TEST"
			and got.death_tick == 80
			and got.score == 3
			and got.hat_id == 3
			and got.player_id == "p1"
			and got.run_id == "run-1"
			and got.flap_ticks == run.flap_ticks
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ghost_runs/%d.cfg" % seed))
	print("[store] save/load=%s count=%d" % [ok, loaded.size()])
	return ok


func _test_fill() -> bool:
	var seed := 777001
	var built: Dictionary = CourseBuilderScript.generate(seed)
	var layout: Array = built["layout"]
	var filler = GhostMatchScript.new()
	var empty: Array = filler.fill_competitors(seed, layout, "local_me")
	var ok := empty.size() == RR.GHOST_COUNT
	var fallbacks := 0
	var ids := {}
	for run in empty:
		if run.source == GhostRunScript.SOURCE_FALLBACK:
			fallbacks += 1
		if run.run_id != "":
			if ids.has(run.run_id):
				ok = false
			ids[run.run_id] = true
		if run.course_seed != seed or not run.is_valid():
			ok = false
	ok = ok and fallbacks == RR.GHOST_COUNT
	var mine = _real(seed, "local_me", "mine-1", "ME")
	var a = _real(seed, "other_a", "real-a", "Ada")
	var b = _real(seed, "other_b", "real-b", "Bea")
	var dup = _real(seed, "other_c", "real-a", "Cara")
	filler.bank.save_run(mine)
	filler.bank.save_run(a)
	filler.bank.save_run(b)
	filler.bank.save_run(dup)
	var mixed: Array = filler.fill_competitors(seed, layout, "local_me")
	var real_n := 0
	var saw_me := false
	var seen := {}
	for run in mixed:
		if run.source == GhostRunScript.SOURCE_REAL:
			real_n += 1
			if run.player_id == "local_me":
				saw_me = true
		if run.run_id != "":
			if seen.has(run.run_id):
				ok = false
			seen[run.run_id] = true
	ok = ok and mixed.size() == RR.GHOST_COUNT and real_n == 2 and not saw_me
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ghost_runs/%d.cfg" % seed))
	print("[fill] empty_fallback=%d mixed_real=%d size=%d ok=%s" % [fallbacks, real_n, mixed.size(), ok])
	return ok


func _real(seed: int, player_id: String, run_id: String, name: String):
	var run = GhostRunScript.new()
	run.course_seed = seed
	run.display_name = name
	run.player_name = name
	run.fish_id = "fish_blue"
	run.flap_ticks = PackedInt32Array([0, 12, 30])
	run.death_tick = 40
	run.score = 1
	run.source = GhostRunScript.SOURCE_REAL
	run.player_id = player_id
	run.run_id = run_id
	return run


func _sim(flaps: PackedInt32Array, ticks: int) -> PackedFloat32Array:
	var y := RR.VIEW_H * 0.42
	var v := 0.0
	var fi := 0
	var out := PackedFloat32Array()
	if fi < flaps.size() and flaps[fi] == 0:
		v = -RR.FLAP
		fi += 1
	out.append(y)
	for t in range(1, ticks):
		if fi < flaps.size() and flaps[fi] == t:
			v = -RR.FLAP
			fi += 1
		v = minf(v + RR.GRAVITY * DT, RR.TERMINAL)
		y += v * DT
		out.append(y)
	return out
