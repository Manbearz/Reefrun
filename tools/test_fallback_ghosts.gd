extends SceneTree

const CourseBuilderScript := preload("res://scripts/course_builder.gd")
const FallbackScript := preload("res://scripts/fallback_ghost_factory.gd")
const GhostBankScript := preload("res://scripts/ghost_bank.gd")
const GhostRunScript := preload("res://scripts/ghost_run.gd")
const DT := 1.0 / 60.0
const SEEDS := [1, 17, 827361, 424242, 777001]


func _init() -> void:
	var fallback_ok := _test_fallback_paths()
	var real_ok := _test_real_recordings()
	quit(0 if fallback_ok and real_ok else 1)


func _test_fallback_paths() -> bool:
	var ok := true
	var runs := 0
	var total_flaps := 0
	var worst_min := 9999.0
	var worst_max := -9999.0
	var bound_hits := 0
	var gap_checks := 0
	var gap_hits := 0
	var climb_hits := 0
	for seed in SEEDS:
		var layout: Array = CourseBuilderScript.generate(seed)["layout"]
		for slot in RR.GHOST_COUNT:
			var run = FallbackScript.make(seed, slot, layout)
			if run.source != GhostRunScript.SOURCE_FALLBACK or not run.is_valid():
				push_error("invalid fallback seed=%d slot=%d" % [seed, slot])
				ok = false
				continue
			if run.flap_ticks.is_empty() or run.flap_ticks[0] != 0:
				push_error("missing tick-0 flap seed=%d slot=%d" % [seed, slot])
				ok = false
			var path := _simulate(run.flap_ticks, run.death_tick)
			runs += 1
			total_flaps += run.flap_ticks.size()
			worst_min = minf(worst_min, path.min_y)
			worst_max = maxf(worst_max, path.max_y)
			if path.min_y < RR.PLAY_TOP or path.max_y > RR.PLAY_BOTTOM:
				bound_hits += 1
				ok = false
				if bound_hits <= 8:
					push_error(
						"bounds seed=%d slot=%d min=%.1f max=%.1f flaps=%d death=%d"
						% [seed, slot, path.min_y, path.max_y, run.flap_ticks.size(), run.death_tick]
					)
			if _has_upward_drift(run.flap_ticks) and path.min_y < RR.PLAY_TOP + 12.0:
				climb_hits += 1
				ok = false
				if climb_hits <= 8:
					push_error("regular climb flaps seed=%d slot=%d min=%.1f %s" % [seed, slot, path.min_y, str(run.flap_ticks)])
			var gap := _gap_follow(layout, path.y, run.death_tick)
			gap_checks += gap.checks
			gap_hits += gap.hits
	var avg_flaps := float(total_flaps) / float(maxi(1, runs))
	var gap_rate := 100.0 * float(gap_hits) / float(maxi(1, gap_checks))
	print(
		"[fallback] runs=%d slots=%d seeds=%d min_y=%.1f max_y=%.1f avg_flaps=%.1f bound_hits=%d climb_hits=%d gap=%d/%d (%.1f%%) ok=%s"
		% [
			runs,
			RR.GHOST_COUNT,
			SEEDS.size(),
			worst_min,
			worst_max,
			avg_flaps,
			bound_hits,
			climb_hits,
			gap_hits,
			gap_checks,
			gap_rate,
			ok,
		]
	)
	if gap_rate < 70.0:
		push_error("gap follow too low: %.1f%%" % gap_rate)
		ok = false
	return ok


func _test_real_recordings() -> bool:
	var bank = GhostBankScript.new()
	var checked := 0
	var bound_hits := 0
	for seed in SEEDS:
		for run in bank.get_runs(seed):
			if run == null or run.source != GhostRunScript.SOURCE_REAL:
				continue
			if not run.is_valid():
				continue
			checked += 1
			var path := _simulate(run.flap_ticks, maxi(run.death_tick, 1))
			if path.min_y < RR.PLAY_TOP - 40.0 or path.max_y > RR.VIEW_H:
				bound_hits += 1
	print("[real] stored_runs=%d extreme_bounds=%d (sequences unchanged)" % [checked, bound_hits])
	return true


func _simulate(flaps: PackedInt32Array, death_tick: int) -> Dictionary:
	var y := RR.VIEW_H * 0.42
	var v := 0.0
	var fi := 0
	var min_y := y
	var max_y := y
	var samples := PackedFloat32Array()
	samples.append(y)
	for t in death_tick + 1:
		if fi < flaps.size() and int(flaps[fi]) == t:
			v = -RR.FLAP
			fi += 1
		elif fi < flaps.size() and int(flaps[fi]) < t:
			fi += 1
			if fi < flaps.size() and int(flaps[fi]) == t:
				v = -RR.FLAP
				fi += 1
		v = minf(v + RR.GRAVITY * DT, RR.TERMINAL)
		y += v * DT
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)
		samples.append(y)
	return {"min_y": min_y, "max_y": max_y, "y": samples}


func _has_upward_drift(flaps: PackedInt32Array) -> bool:
	if flaps.size() < 5:
		return false
	var step := int(flaps[1]) - int(flaps[0])
	if step < 20:
		return false
	var same := 0
	for i in range(1, flaps.size()):
		if absi((int(flaps[i]) - int(flaps[i - 1])) - step) <= 1:
			same += 1
	return same >= flaps.size() - 2 and step <= 34


func _gap_follow(layout: Array, ys: PackedFloat32Array, death_tick: int) -> Dictionary:
	var checks := 0
	var hits := 0
	var death_x := RR.PIPE_SPEED * float(death_tick) * DT
	for spec in layout:
		var px := float(spec["x"])
		if px + 40.0 >= death_x:
			break
		var t := int(round(px / (RR.PIPE_SPEED * DT)))
		if t < 0 or t >= ys.size():
			continue
		checks += 1
		var gap_y := float(spec["gap_y"])
		var half := float(spec["gap_h"]) * 0.5
		if absf(ys[t] - gap_y) <= half + 18.0:
			hits += 1
	return {"checks": checks, "hits": hits}
