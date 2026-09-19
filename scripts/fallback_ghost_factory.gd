extends RefCounted

const GhostRunScript := preload("res://scripts/ghost_run.gd")
const DT := 1.0 / 60.0


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
		var gap_y := RR.VIEW_H * 0.42
		var world_x := RR.PIPE_SPEED * float(t) * DT
		while pipe_i + 1 < layout.size() and float(layout[pipe_i]["x"]) < world_x + 20.0:
			pipe_i += 1
		if pipe_i < layout.size():
			gap_y = float(layout[pipe_i]["gap_y"])
		var bias := (0.5 - skill) * 28.0
		var want := cooldown <= 0 and (y > gap_y + 10.0 + bias or v > 360.0)
		if t > 0 and y < RR.PLAY_TOP + 36.0:
			want = false
		if t == 0 or want:
			v = -RR.FLAP
			flaps.append(t)
			cooldown = 5 + int(round((1.0 - skill) * 5.0))
		else:
			cooldown = maxi(0, cooldown - 1)
		v = minf(v + RR.GRAVITY * DT, RR.TERMINAL)
		y += v * DT
	return flaps
