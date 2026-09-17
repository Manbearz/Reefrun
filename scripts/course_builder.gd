class_name CourseBuilder
extends RefCounted


static func generate(seed: int, pipe_count: int = RR.PIPE_COUNT) -> Dictionary:
	var course_rng := RandomNumberGenerator.new()
	course_rng.seed = seed
	var layout: Array[Dictionary] = []
	var x := RR.PIPE_SPEED * RR.FIRST_PIPE
	for i in pipe_count:
		var gap := RR.GAP - minf(float(i / 18), 18.0)
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
	var lanes := PackedInt32Array()
	var prev_lane := 1
	var volleys := maxi(1, pipe_count / RR.HARPOON_EVERY) + 2
	for _v in volleys:
		for shot in RR.HARPOON_SHOTS:
			var lane: int
			if shot == 0:
				lane = course_rng.randi_range(0, 2)
			else:
				lane = (prev_lane + 1 + course_rng.randi_range(0, 1)) % 3
			lanes.append(lane)
			prev_lane = lane
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
	print("[course] seed %d: %d pipes + %d harpoon lanes identical" % [seed, la.size(), ha.size()])
	return true


static func specs_equal(a: Dictionary, b: Dictionary) -> bool:
	return (
		is_equal_approx(float(a.get("x", 0.0)), float(b.get("x", 0.0)))
		and is_equal_approx(float(a.get("gap_y", 0.0)), float(b.get("gap_y", 0.0)))
		and is_equal_approx(float(a.get("gap_h", 0.0)), float(b.get("gap_h", 0.0)))
		and str(a.get("style", "")) == str(b.get("style", ""))
	)
