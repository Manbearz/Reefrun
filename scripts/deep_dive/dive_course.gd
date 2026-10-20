class_name DiveCourse
extends RefCounted


static func generate(dive_number: int, seed: int) -> Array[Dictionary]:
	var profile := DeepDiveConfig.profile(dive_number)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else 1
	var kinds: PackedStringArray = profile["kinds"]
	var min_gap: float = profile["min_gap"]
	var spacing: float = profile["spacing"]
	var speed: float = profile["scroll"]
	var duration: float = profile["duration"]
	var travel: float = profile["first_travel"]
	var end_travel := speed * duration + RR.VIEW_H
	var specs: Array[Dictionary] = []
	var order := _opening_order(kinds, rng)
	var cursor := 0
	var last := ""
	var streak := 0
	var prev_lane := DeepDiveConfig.CENTER_LANE
	var prev_span := 1
	while travel < end_travel:
		var kind := order[cursor] if cursor < order.size() else _pick(kinds, rng, last, streak)
		cursor += 1
		if kind == last:
			streak += 1
		else:
			last = kind
			streak = 1
		var span := _opening_span(dive_number, rng)
		var budget := DeepDiveConfig.lanes_reachable(spacing * 0.94 / maxf(speed, 1.0))
		var lane := _pick_lane(rng, prev_lane, prev_span, span, budget)
		var gap_x := DeepDiveConfig.lane_center(lane) - DeepDiveConfig.LANE_CLEAR
		var gap_w := DeepDiveConfig.lane_center(lane + span - 1) + DeepDiveConfig.LANE_CLEAR - gap_x
		var side := rng.randi_range(0, 2)
		if kind == "wreck":
			side = rng.randi_range(0, 1)
		var spec := {
			"kind": kind,
			"travel": travel,
			"gap_x": gap_x,
			"gap_w": gap_w,
			"lane": lane,
			"span": span,
			"variant": rng.randi_range(0, 7),
			"drift": rng.randf_range(12.0, 28.0) if kind == "mine" or kind == "jelly" else 0.0,
			"side": side,
		}
		if not passage_ok(spec, min_gap):
			travel += spacing
			continue
		var partner := ""
		if dive_number >= 2 and cursor > order.size() and rng.randf() < _pair_chance(dive_number):
			partner = _partner_kind(kinds, kind, rng)
		if partner != "":
			spec["side"] = 0
		specs.append(spec)
		prev_lane = lane
		prev_span = span
		if partner != "":
			var twin: Dictionary = spec.duplicate()
			twin["kind"] = partner
			twin["side"] = 1
			twin["variant"] = rng.randi_range(0, 7)
			twin["drift"] = rng.randf_range(12.0, 28.0) if partner == "mine" or partner == "jelly" else 0.0
			if passage_ok(twin, min_gap):
				specs.append(twin)
				last = partner
				streak = 1
		travel += spacing * rng.randf_range(0.94, 1.12)
	return specs


static func passage_ok(spec: Dictionary, min_gap: float) -> bool:
	var gap_w := float(spec.get("gap_w", 0.0))
	var gap_x := float(spec.get("gap_x", 0.0))
	if gap_w + 0.01 < min_gap:
		return false
	if gap_x < 20.0:
		return false
	if gap_x + gap_w > RR.VIEW_W - 20.0:
		return false
	var kind := str(spec.get("kind", ""))
	if kind != "net" and kind != "pillar" and kind != "mine" and kind != "jelly" and kind != "wreck":
		return false
	return true


static func _opening_order(kinds: PackedStringArray, rng: RandomNumberGenerator) -> PackedStringArray:
	var bag := kinds.duplicate()
	for i in range(bag.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := bag[i]
		bag[i] = bag[j]
		bag[j] = swap
	return bag


static func _opening_span(dive_number: int, rng: RandomNumberGenerator) -> int:
	var wide := 0.72
	if dive_number == 2:
		wide = 0.35
	elif dive_number >= 3:
		wide = 0.12
	if rng.randf() < wide:
		return 2
	return 1


static func _lane_distance(from_lane: int, from_span: int, to_lane: int, to_span: int) -> int:
	var from_last := from_lane + from_span - 1
	var to_last := to_lane + to_span - 1
	if to_last < from_lane:
		return from_lane - to_last
	if to_lane > from_last:
		return to_lane - from_last
	return 0


static func _pick_lane(rng: RandomNumberGenerator, prev_lane: int, prev_span: int, span: int, budget: int) -> int:
	var limit := DeepDiveConfig.LANE_COUNT - span + 1
	var choices: Array[int] = []
	for lane in range(1, limit + 1):
		if _lane_distance(prev_lane, prev_span, lane, span) <= budget:
			choices.append(lane)
	if choices.is_empty():
		return clampi(prev_lane, 1, limit)
	return choices[rng.randi_range(0, choices.size() - 1)]


static func _pair_chance(dive_number: int) -> float:
	if dive_number <= 1:
		return 0.0
	if dive_number == 2:
		return 0.14
	if dive_number == 3:
		return 0.2
	return 0.26


static func _partner_kind(kinds: PackedStringArray, current: String, rng: RandomNumberGenerator) -> String:
	var choices := PackedStringArray()
	for kind in kinds:
		if kind != current and kind != "net":
			choices.append(kind)
	if choices.is_empty():
		for kind in kinds:
			if kind != current:
				choices.append(kind)
	if choices.is_empty():
		return ""
	return choices[rng.randi_range(0, choices.size() - 1)]


static func _pick(kinds: PackedStringArray, rng: RandomNumberGenerator, last: String, streak: int) -> String:
	if kinds.is_empty():
		return "net"
	if kinds.size() == 1 or streak < 2:
		return kinds[rng.randi_range(0, kinds.size() - 1)]
	var choices: PackedStringArray = PackedStringArray()
	for kind in kinds:
		if kind != last:
			choices.append(kind)
	if choices.is_empty():
		return kinds[0]
	return choices[rng.randi_range(0, choices.size() - 1)]
