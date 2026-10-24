class_name CourseBuilder
extends RefCounted

# How many unspawned pipes to keep ahead of the player, and how many to append.
# The seed formula is part of the competitive continuation. Pipes already generated
# stay put; only the next chunk uses this seed.
const CHUNK_PIPES := 40
const LOOKAHEAD := 16


static func generate(seed: int, pipe_count: int = RR.PIPE_COUNT, start_index: int = 0) -> Dictionary:
	var course_rng := RandomNumberGenerator.new()
	course_rng.seed = seed
	var layout: Array[Dictionary] = []
	var x := RR.PIPE_SPEED * RR.FIRST_PIPE
	for i in pipe_count:
		var n := start_index + i
		var gap := RR.GAP - minf(float(n / 18), 18.0)
		var slot := course_rng.randi_range(0, 4)
		var half := gap * 0.5
		var pad := RR.FISH_HIT + 8.0
		var top := RR.PLAY_TOP + half + pad
		var bottom := RR.PLAY_BOTTOM - half - pad
		var gap_y := lerpf(top, bottom, float(slot) / 4.0)
		layout.append({
			"x": x,
			"gap_y": gap_y,
			"gap_h": gap,
			"style": RR.PIPE_IDS[course_rng.randi() % RR.PIPE_IDS.size()],
		})
		x += RR.PIPE_SPEED * RR.PIPE_INTERVAL
	var lanes := _harpoon_lanes(course_rng, maxi(1, pipe_count / RR.HARPOON_EVERY) + 2)
	return {
		"layout": layout,
		"harpoon_lanes": lanes,
	}


static func validate_determinism(seed: int, pipe_count: int = 100) -> bool:
	var a := generate(seed, pipe_count)
	var b := generate(seed, pipe_count)
	var la: Array = a["layout"]
	var lb: Array = b["layout"]
	if la.size() != lb.size():
		push_error("Course size mismatch seed=%d %d vs %d" % [seed, la.size(), lb.size()])
		return false
	for i in la.size():
		if not specs_equal(la[i], lb[i]):
			push_error("Course mismatch seed=%d i=%d a=%s b=%s" % [seed, i, str(la[i]), str(lb[i])])
			return false
	var ha: PackedInt32Array = a["harpoon_lanes"]
	var hb: PackedInt32Array = b["harpoon_lanes"]
	if ha != hb:
		push_error("Harpoon sequence mismatch seed=%d" % seed)
		return false
	if OS.has_feature("editor") or OS.is_debug_build():
		print("[course] seed %d: %d pipes + %d harpoon lanes identical" % [seed, la.size(), ha.size()])
	return true


# Each shot leaves one of the four lanes safe. A volley of HARPOON_SHOTS
# uses distinct safe lanes, and the next shot never repeats the previous one.
static func _harpoon_lanes(course_rng: RandomNumberGenerator, volleys: int) -> PackedInt32Array:
	var lanes := PackedInt32Array()
	var prev := -1
	var count := RR.HARPOON_LANES
	for _volley in volleys:
		var used := PackedInt32Array()
		for _shot in RR.HARPOON_SHOTS:
			var lane := course_rng.randi_range(0, count - 1)
			var spins := 0
			while (lane == prev or used.has(lane)) and spins < count:
				lane = (lane + 1 + course_rng.randi_range(0, count - 2)) % count
				spins += 1
			if lane == prev or used.has(lane):
				for candidate in count:
					if candidate != prev and not used.has(candidate):
						lane = candidate
						break
			used.append(lane)
			lanes.append(lane)
			prev = lane
	return lanes


static func extension_seed(course_seed: int, layout_size: int) -> int:
	return course_seed + layout_size * 13 + 3


static func continuation(course_seed: int, layout_size: int) -> Dictionary:
	return generate(extension_seed(course_seed, layout_size), CHUNK_PIPES, layout_size)


# Rebased copies. The caller appends them so a typed layout array is not copied.
static func placed_specs(layout: Array, extra: Array) -> Array:
	var placed: Array = []
	if extra.is_empty():
		return placed
	var spacing := RR.PIPE_SPEED * RR.PIPE_INTERVAL
	var base := spacing
	if not layout.is_empty():
		base = float(layout[layout.size() - 1]["x"]) + spacing
	var origin := float(extra[0]["x"])
	for spec in extra:
		var copy: Dictionary = (spec as Dictionary).duplicate()
		copy["x"] = base + float(copy["x"]) - origin
		placed.append(copy)
	return placed


static func specs_equal(a: Dictionary, b: Dictionary) -> bool:
	return (
		is_equal_approx(float(a.get("x", 0.0)), float(b.get("x", 0.0)))
		and is_equal_approx(float(a.get("gap_y", 0.0)), float(b.get("gap_y", 0.0)))
		and is_equal_approx(float(a.get("gap_h", 0.0)), float(b.get("gap_h", 0.0)))
		and str(a.get("style", "")) == str(b.get("style", ""))
	)
