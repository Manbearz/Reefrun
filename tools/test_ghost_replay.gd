extends SceneTree

const CourseBuilderScript := preload("res://scripts/course_builder.gd")
const GhostBankScript := preload("res://scripts/ghost_bank.gd")
const GhostRunScript := preload("res://scripts/ghost_run.gd")
const DT := 1.0 / 60.0


func _init() -> void:
	var course_ok: bool = CourseBuilderScript.validate_determinism(827361)
	course_ok = CourseBuilderScript.validate_determinism(1) and course_ok
	var store_ok := _test_store()
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
	print("[replay] identical path=%s samples=%d last_y=%.3f store=%s" % [path_ok, a.size(), a[a.size() - 1], store_ok])
	quit(0 if course_ok and path_ok and store_ok else 1)


func _test_store() -> bool:
	var seed := 424242
	var run = GhostRunScript.new()
	run.course_seed = seed
	run.player_name = "TEST"
	run.fish_id = "fish_blue"
	run.flap_ticks = PackedInt32Array([0, 14, 39, 63])
	run.death_tick = 80
	run.score = 3
	var bank = GhostBankScript.new()
	bank.save_run(run)
	var loaded: Array = bank.get_runs(seed)
	var ok := loaded.size() == 1
	if ok:
		var got = loaded[0]
		ok = (
			got.player_name == "TEST"
			and got.death_tick == 80
			and got.score == 3
			and got.flap_ticks == run.flap_ticks
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ghost_runs/%d.cfg" % seed))
	print("[store] save/load=%s count=%d" % [ok, loaded.size()])
	return ok


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
