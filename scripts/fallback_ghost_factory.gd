extends RefCounted

const GhostRunScript := preload("res://scripts/ghost_run.gd")
const DT := 1.0 / 60.0
const RISE := RR.FLAP * RR.FLAP / (2.0 * RR.GRAVITY)


static func make(course_seed: int, slot: int, layout: Array) -> GhostRun:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(course_seed) * 10007 + slot * 131 + 17
	var run = GhostRunScript.new()
	run.physics_version = RR.PHYSICS_VERSION
	run.course_version = RR.COURSE_VERSION
	run.course_seed = course_seed
	run.source = GhostRunScript.SOURCE_FALLBACK
	run.run_id = "fallback:%d:%d" % [course_seed, slot]
	run.player_id = ""
	run.display_name = _name(slot)
	run.player_name = run.display_name
	run.fish_id = RR.FISH_IDS[slot % RR.FISH_IDS.size()]
	run.hat_id = rng.randi_range(0, RR.HAT_COUNT - 1) if rng.randf() < 0.55 else -1
	run.created_at = 0
	var death_pipe := _roll_death(rng)
	run.score = death_pipe
	var first := int(round(RR.FIRST_PIPE * 60.0))
	var interval := int(round(RR.PIPE_INTERVAL * 60.0))
	run.death_tick = maxi(1, first + death_pipe * interval + rng.randi_range(8, 42))
	run.flap_ticks = _flaps_for(layout, run.death_tick, rng)
	return run


static func _name(slot: int) -> String:
	return "%s %d" % [RR.GHOST_NAMES[slot % RR.GHOST_NAMES.size()], slot / RR.GHOST_NAMES.size() + 1]


static func _roll_death(rng: RandomNumberGenerator) -> int:
	var u := rng.randf()
	if u < 0.20:
		return 0
	if u < 0.45:
		return 1
	if u < 0.66:
		return 2
	if u < 0.80:
		return 3
	if u < 0.90:
		return 4
	if u < 0.96:
		return rng.randi_range(5, 8)
	return rng.randi_range(9, 28)


static func _flaps_for(layout: Array, death_tick: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var flaps := PackedInt32Array()
	var y := RR.VIEW_H * 0.42
	var v := 0.0
	var cooldown := 0
	var pipe_i := 0
	var skill := clampf(rng.randfn(0.58, 0.18), 0.18, 0.92)
	for t in death_tick + 1:
		while pipe_i + 1 < layout.size() and float(layout[pipe_i]["x"]) < RR.PIPE_SPEED * float(t) * DT - 20.0:
			pipe_i += 1
		var target := _gap_at(layout, pipe_i) + (0.5 - skill) * 24.0
		var want := t == 0 or (cooldown <= 0 and _want_flap(y, v, target))
		if want:
			v = -RR.FLAP
			flaps.append(t)
			cooldown = 18 + int(round((1.0 - skill) * 10.0))
		else:
			cooldown = maxi(0, cooldown - 1)
		v = minf(v + RR.GRAVITY * DT, RR.TERMINAL)
		y += v * DT
	return flaps


static func _gap_at(layout: Array, pipe_i: int) -> float:
	if pipe_i < layout.size():
		return float(layout[pipe_i]["gap_y"])
	return RR.VIEW_H * 0.42


static func _want_flap(y: float, v: float, target: float) -> bool:
	# A flap always rises RISE pixels. Refuse if that would leave the playfield.
	if y - RISE < RR.PLAY_TOP + 4.0:
		return false
	var falling := v > 0.0
	if not falling:
		return false
	# Floor save: schedule a hop before gravity carries us out.
	if y > RR.PLAY_BOTTOM - 72.0:
		return true
	# Only hop once we have fallen back to/through the gap. No velocity-only override.
	return y >= target + 8.0
