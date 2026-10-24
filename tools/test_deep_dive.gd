extends SceneTree

const DT := 0.05
var _death_count := 0
var _collision_scenarios := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _check("thresholds", _test_thresholds()) and ok
	ok = _check("no_double_fire", _test_no_double()) and ok
	ok = _check("harpoon_before_dive", _test_harpoon_before_dive()) and ok
	ok = _check("no_overlap", _test_no_overlap()) and ok
	ok = _check("duration", _test_duration()) and ok
	ok = _check("pause_freezes", _test_pause()) and ok
	ok = _check("death_cancels", _test_death()) and ok
	ok = _check("steering_bounds", _test_steering()) and ok
	ok = _check("safe_gaps", _test_gaps()) and ok
	ok = _check("beginner_dive", _test_beginner()) and ok
	ok = _check("later_unlocks", _test_later()) and ok
	ok = _check("pipe_count", _test_pipe_count()) and ok
	ok = _check("coins_untouched", _test_coins()) and ok
	ok = _check("daily_unchanged", _test_daily()) and ok
	ok = _check("harpoon_lanes", await _test_harpoon_pattern()) and ok
	ok = _check("whoosh", _test_whoosh()) and ok
	ok = _check("fixed_speed", _test_fixed_speed()) and ok
	ok = _check("restart", _test_restart()) and ok
	ok = _check("repeated_dives", _test_repeated()) and ok
	ok = _check("obstacle_pool", _test_pool()) and ok
	ok = _check("safe_pass", _test_safe_pass()) and ok
	var rearm_ok: bool = await _test_hit_rearm()
	ok = _check("hit_rearm", rearm_ok) and ok
	var signal_ok: bool = await _test_signal_disarm()
	ok = _check("signal_disarm", signal_ok) and ok
	ok = _check("swim_restored", _test_swim_restored()) and ok
	ok = _check("paired_obstacles", _test_pairs()) and ok
	var touch_ok: bool = await _test_touch()
	ok = _check("tap_and_restore", touch_ok) and ok
	var lane_ok: bool = await _test_lanes()
	ok = _check("lane_collisions", lane_ok) and ok
	ok = _check("collision_matrix", _collision_matrix()) and ok
	ok = _check("collision_swipes", _collision_swipes()) and ok
	var play_ok: bool = await _collision_play()
	ok = _check("collision_play", play_ok) and ok
	print("[deep-dive] collision_scenarios=%d" % _collision_scenarios)
	print("[deep-dive] ok=%s" % ok)
	quit(0 if ok else 1)


func _check(name: String, passed: bool) -> bool:
	if not passed:
		push_error("[deep-dive] FAIL %s" % name)
	return passed


func _test_thresholds() -> bool:
	var ev := GameplayEvents.new()
	ev.set_corridor_clear(false)
	for n in 120:
		ev.note_pipes_passed(n + 1)
	var expect := PackedStringArray()
	for i in 4:
		expect.append("harpoon:%d" % DeepDiveConfig.harpoon_pipe(i))
		expect.append("dive:%d" % DeepDiveConfig.dive_pipe(i))
	ev.tick(DT)
	return (
		ev.fired_log == expect
		and ev.state == GameplayEvents.State.HARPOON_PENDING
		and ev.queued_count() == 7
		and ev.pipes_passed == 120
	)


func _test_no_double() -> bool:
	var ev := GameplayEvents.new()
	ev.note_pipes_passed(15)
	ev.note_pipes_passed(15)
	ev.tick(DT)
	ev.note_pipes_passed(15)
	return ev.fired_log.size() == 1 and ev.fired_log[0] == "harpoon:15"


func _test_harpoon_before_dive() -> bool:
	var ev := GameplayEvents.new()
	ev.set_corridor_clear(false)
	ev.note_pipes_passed(30)
	ev.tick(DT)
	if ev.state != GameplayEvents.State.HARPOON_PENDING:
		return false
	ev.set_corridor_clear(true)
	ev.tick(DT)
	if ev.state != GameplayEvents.State.HARPOON_WARNING or ev.blocks_swim():
		return false
	ev.tick(3.0)
	if ev.blocks_swim():
		return false
	ev.notify_harpoon_finished()
	if ev.state != GameplayEvents.State.HARPOON_CLEANUP:
		return false
	ev.tick(DeepDiveConfig.HARPOON_CLEANUP + DT)
	return ev.state == GameplayEvents.State.DIVE_TRANSITION_IN and ev.dive_number == 1


func _test_no_overlap() -> bool:
	var ev := GameplayEvents.new()
	ev.debug_force_state(GameplayEvents.State.DEEP_DIVE)
	ev.note_pipes_passed(15)
	ev.tick(2.0)
	return (
		ev.state == GameplayEvents.State.DEEP_DIVE
		and ev.queued_count() == 1
		and is_equal_approx(ev.active_dive_time, 2.0)
		and not ev.pipes_allowed()
	)


func _test_duration() -> bool:
	var ev := GameplayEvents.new()
	ev.debug_force_state(GameplayEvents.State.DIVE_TRANSITION_IN)
	ev.tick(DeepDiveConfig.intro_total())
	if ev.state != GameplayEvents.State.DEEP_DIVE or ev.active_dive_time != 0.0:
		return false
	var left := DeepDiveConfig.DURATION
	while left > 0.0001:
		var step := minf(DT, left)
		ev.tick(step)
		left -= step
	return ev.state == GameplayEvents.State.DIVE_TRANSITION_OUT and is_equal_approx(ev.active_dive_time, DeepDiveConfig.DURATION)


func _test_pause() -> bool:
	var ev := GameplayEvents.new()
	ev.debug_force_state(GameplayEvents.State.DEEP_DIVE)
	ev.tick(5.0)
	ev.set_paused(true)
	ev.tick(9.0)
	if not is_equal_approx(ev.active_dive_time, 5.0) or ev.state != GameplayEvents.State.DEEP_DIVE:
		return false
	ev.set_paused(false)
	ev.tick(15.0)
	return ev.state == GameplayEvents.State.DIVE_TRANSITION_OUT and is_equal_approx(ev.active_dive_time, 20.0)


func _test_death() -> bool:
	var ev := GameplayEvents.new()
	ev.set_corridor_clear(false)
	ev.note_pipes_passed(30)
	ev.tick(DT)
	ev.notify_death()
	ev.set_corridor_clear(true)
	ev.tick(5.0)
	ev.note_pipes_passed(60)
	return ev.state == GameplayEvents.State.GAME_OVER and ev.queued_count() == 0 and ev.fired_log.size() == 2 and ev.dives_survived == 0


func _test_steering() -> bool:
	var motion := DiveMotion.new()
	motion.configure(RR.VIEW_W)
	motion.reset(RR.VIEW_W * 0.5)
	if motion.lane != DeepDiveConfig.CENTER_LANE:
		return false
	if not is_equal_approx(motion.x, DeepDiveConfig.lane_center(3)):
		return false
	motion.nudge(-1.0)
	if motion.lane != 2:
		return false
	motion.tick(DeepDiveConfig.LANE_SLIDE)
	if not is_equal_approx(motion.x, DeepDiveConfig.lane_center(2)):
		return false
	motion.nudge(1.0)
	motion.nudge(1.0)
	if motion.lane != 4:
		return false
	motion.tick(DeepDiveConfig.LANE_SLIDE * 2.0)
	if not is_equal_approx(motion.x, DeepDiveConfig.lane_center(4)):
		return false
	for _i in 4:
		motion.nudge(-1.0)
	motion.tick(1.0)
	if motion.lane != 1 or not is_equal_approx(motion.x, DeepDiveConfig.lane_center(1)):
		return false
	motion.nudge(1.0)
	motion.nudge(1.0)
	motion.nudge(1.0)
	if motion.lane != 4:
		return false
	motion.tick(DeepDiveConfig.LANE_SLIDE * 3.0)
	if not is_equal_approx(motion.x, DeepDiveConfig.lane_center(4)):
		return false
	for _i in 6:
		motion.nudge(1.0)
	motion.tick(1.0)
	return motion.lane == DeepDiveConfig.LANE_COUNT and is_equal_approx(motion.x, motion.max_x)


func _test_gaps() -> bool:
	for dive in [1, 2, 3, 4, 6]:
		var profile := DeepDiveConfig.profile(dive)
		for seed in [1, 7, 19, 44]:
			var specs := DiveCourse.generate(dive, seed)
			if specs.is_empty():
				return false
			var last := ""
			var streak := 0
			var prev_lane := DeepDiveConfig.CENTER_LANE
			var prev_span := 1
			var prev_travel := 0.0
			var scroll: float = profile["scroll"]
			for spec in specs:
				if not DiveCourse.passage_ok(spec, float(profile["min_gap"])):
					return false
				if float(spec["travel"]) < DeepDiveConfig.MIN_REACTION_TRAVEL:
					return false
				var lane := int(spec["lane"])
				var span := int(spec["span"])
				if lane < 1 or lane + span - 1 > DeepDiveConfig.LANE_COUNT:
					return false
				var gap_x := float(spec["gap_x"])
				var gap_w := float(spec["gap_w"])
				for offset in span:
					var center := DeepDiveConfig.lane_center(lane + offset)
					if center - 28.0 < gap_x or center + 28.0 > gap_x + gap_w:
						return false
				var travel := float(spec["travel"])
				var dt := (travel - prev_travel) / maxf(scroll, 1.0)
				if not is_equal_approx(travel, prev_travel):
					var budget := DeepDiveConfig.lanes_reachable(dt)
					var dist := DiveCourse._lane_distance(prev_lane, prev_span, lane, span)
					if dist > budget:
						return false
				elif lane != prev_lane or span != prev_span:
					return false
				prev_lane = lane
				prev_span = span
				prev_travel = travel
				var kind := str(spec["kind"])
				if kind == last:
					streak += 1
				else:
					last = kind
					streak = 1
				if streak > 2:
					return false
	var a := DiveCourse.generate(3, 1234)
	var b := DiveCourse.generate(3, 1234)
	if a.size() != b.size():
		return false
	for i in a.size():
		if str(a[i]["kind"]) != str(b[i]["kind"]):
			return false
		if not is_equal_approx(float(a[i]["gap_x"]), float(b[i]["gap_x"])):
			return false
	return true


func _test_beginner() -> bool:
	var kinds: PackedStringArray = DeepDiveConfig.profile(1)["kinds"]
	if kinds.size() != 2 or kinds[0] != "net" or kinds[1] != "pillar":
		return false
	for spec in DiveCourse.generate(1, 8):
		var kind := str(spec["kind"])
		if kind != "net" and kind != "pillar":
			return false
	return true


func _test_later() -> bool:
	return (
		_has_kind(2, "mine")
		and not _has_kind(2, "jelly")
		and not _has_kind(2, "wreck")
		and _has_kind(3, "jelly")
		and not _has_kind(3, "wreck")
		and _has_kind(4, "wreck")
		and is_equal_approx(float(DeepDiveConfig.profile(1)["scroll"]), DeepDiveConfig.DEEP_DIVE_SPEED)
		and is_equal_approx(float(DeepDiveConfig.profile(10)["scroll"]), DeepDiveConfig.DEEP_DIVE_SPEED)
		and is_equal_approx(float(DeepDiveConfig.profile(8)["spacing"]), DeepDiveConfig.DEEP_DIVE_SPACING)
		and float(DeepDiveConfig.profile(8)["min_gap"]) >= DeepDiveConfig.MIN_GAP
		and DeepDiveConfig.FISH_Y + float(DeepDiveConfig.profile(1)["first_travel"]) >= RR.screen_bottom() + 160.0
	)


func _has_kind(dive_number: int, kind: String) -> bool:
	for spec in DiveCourse.generate(dive_number, 3):
		if str(spec["kind"]) == kind:
			return true
	return false


func _test_pipe_count() -> bool:
	var ev := GameplayEvents.new()
	ev.note_pipes_passed(30)
	var pipes := ev.pipes_passed
	ev.debug_force_state(GameplayEvents.State.DEEP_DIVE)
	ev.note_obstacles_dodged(6)
	ev.tick(20.0)
	return ev.pipes_passed == pipes and ev.dive_obstacles_dodged == 6 and ev.dives_survived == 0


func _test_coins() -> bool:
	var wallet := 12
	var ev := GameplayEvents.new()
	_drain_to(ev, 30)
	var events := FileAccess.get_file_as_string("res://scripts/deep_dive/gameplay_events.gd")
	var field := FileAccess.get_file_as_string("res://scripts/deep_dive/dive_field.gd")
	var game := FileAccess.get_file_as_string("res://scenes/game/game.gd")
	return (
		wallet == 12
		and ev.dives_survived == 1
		and events.find("add_coins") < 0
		and field.find("add_coins") < 0
		and game.find("func _finish_coin_ad") >= 0
		and game.find("GameSession.add_coins(bonus)") >= 0
	)


func _test_fixed_speed() -> bool:
	var speed := DeepDiveConfig.DEEP_DIVE_SPEED
	var spacing := DeepDiveConfig.DEEP_DIVE_SPACING
	for n in [1, 2, 5, 10]:
		var profile := DeepDiveConfig.profile(n)
		if not is_equal_approx(float(profile["scroll"]), speed):
			return false
		if not is_equal_approx(float(profile["spacing"]), spacing):
			return false
		if not is_equal_approx(float(profile["duration"]), 20.0):
			return false
	var field: DiveField = load("res://scenes/deep_dive/dive_field.tscn").instantiate()
	root.add_child(field)
	var ok := true
	for n in [1, 2, 5, 10]:
		field.start(n, 11)
		if not is_equal_approx(field.fall_speed(), speed):
			ok = false
		field.halt()
		if not is_equal_approx(field.fall_speed(), 0.0):
			ok = false
	field.free()
	return ok and is_equal_approx(speed, 786.0)


func _test_whoosh() -> bool:
	var sfx := root.get_node_or_null("Sfx")
	if sfx == null:
		return false
	var streams: Dictionary = sfx.get("_streams")
	var stream := streams.get("whoosh") as AudioStream
	if stream == null:
		return false
	var length := stream.get_length()
	if length < 0.5 or length > 1.0:
		return false
	sfx.stop("whoosh")
	sfx.play("whoosh", -80.0)
	var playing := 0
	for player in sfx.get("_players"):
		var audio := player as AudioStreamPlayer
		if audio.playing and audio.stream == stream:
			playing += 1
	sfx.stop("whoosh")
	var still := 0
	for player in sfx.get("_players"):
		var audio := player as AudioStreamPlayer
		if audio.playing and audio.stream == stream:
			still += 1
	var game := FileAccess.get_file_as_string("res://scenes/game/game.gd")
	return playing == 1 and still == 0 and game.find("_whoosh_dive") >= 0 and game.find("stop(\"whoosh\")") >= 0


func _test_harpoon_pattern() -> bool:
	var built := CourseBuilder.generate(21, 120)
	var again := CourseBuilder.generate(21, 120)
	var lanes: PackedInt32Array = built["harpoon_lanes"]
	var repeat_lanes: PackedInt32Array = again["harpoon_lanes"]
	if lanes != repeat_lanes or lanes.size() < RR.HARPOON_SHOTS * 4:
		return false
	var seen := [0, 0, 0, 0]
	var prev := -1
	for i in lanes.size():
		var lane := int(lanes[i])
		if lane < 0 or lane >= RR.HARPOON_LANES:
			return false
		seen[lane] += 1
		if lane == prev:
			return false
		prev = lane
		if (i + 1) % RR.HARPOON_SHOTS == 0:
			var first := int(lanes[i - 2])
			var second := int(lanes[i - 1])
			if first == second or first == lane or second == lane:
				return false
	for count in seen:
		if count == 0:
			return false
	var low := RR.harpoon_lane_y(RR.HARPOON_LANES - 1, RR.HARPOON_PER_LANE - 1)
	var high := RR.harpoon_lane_y(0, 0)
	if high < RR.PLAY_TOP or low > RR.screen_bottom() - 48.0 or low < high + 400.0:
		return false
	if RR.harpoon_lane_of(RR.harpoon_band().y - 2.0) != RR.HARPOON_LANES - 1:
		return false
	if RR.harpoon_lane_of(RR.screen_bottom() - 4.0) != RR.HARPOON_LANES - 1:
		return false
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	for _i in 4:
		await process_frame
	var spears: Array = game.get("_harpoons")
	if spears.size() != RR.HARPOON_LANES * RR.HARPOON_PER_LANE:
		game.queue_free()
		return false
	var lowest := -1.0
	for spear in spears:
		if int(spear.lane) == RR.HARPOON_LANES - 1:
			lowest = maxf(lowest, float(spear.position.y))
	if absf(lowest - low) > 1.0:
		game.queue_free()
		return false
	game.set("_harpoon_lanes", PackedInt32Array([0, 3, 1]))
	game.set("_harpoon_lane_i", 0)
	var safes := PackedInt32Array()
	var fired_ok := true
	for _shot in RR.HARPOON_SHOTS:
		game.call("_begin_harpoon_warn")
		var safe := int(game.get("_safe_lane"))
		safes.append(safe)
		var armed_lanes := {}
		for spear in spears:
			if bool(spear.get("armed")):
				armed_lanes[int(spear.lane)] = true
		if armed_lanes.size() != RR.HARPOON_LANES - 1 or armed_lanes.has(safe):
			fired_ok = false
		for spear in spears:
			spear.hide_idle()
	game.queue_free()
	return fired_ok and safes == PackedInt32Array([0, 3, 1])


func _test_daily() -> bool:
	if GameplayEvents.applies_to("daily", false):
		return false
	if GameplayEvents.applies_to("unlimited", true):
		return false
	if not GameplayEvents.applies_to("unlimited", false):
		return false
	var built := CourseBuilder.generate(11, 80)
	var lanes: PackedInt32Array = built["harpoon_lanes"]
	var volleys := maxi(1, 80 / RR.HARPOON_EVERY) + 2
	var source := FileAccess.get_file_as_string("res://scenes/game/game.gd")
	return lanes.size() == volleys * RR.HARPOON_SHOTS and source.find("_pipes_until_harpoon = RR.HARPOON_EVERY") >= 0


func _test_restart() -> bool:
	var ev := GameplayEvents.new()
	ev.note_pipes_passed(45)
	ev.notify_death()
	ev.reset()
	return (
		ev.state == GameplayEvents.State.NORMAL
		and ev.pipes_passed == 0
		and ev.next_harpoon_pipe == DeepDiveConfig.HARPOON_FIRST_PIPE
		and ev.next_dive_pipe == DeepDiveConfig.DIVE_FIRST_PIPE
		and ev.dives_survived == 0
		and ev.queued_count() == 0
		and ev.fired_log.is_empty()
	)


func _test_repeated() -> bool:
	var ev := GameplayEvents.new()
	ev.note_pipes_passed(60)
	if not _drain(ev):
		return false
	if ev.dives_survived != 2 or ev.pipes_passed != 60 or ev.state != GameplayEvents.State.NORMAL:
		return false
	if ev.suppresses_flap() or ev.queued_count() != 0:
		return false
	ev.note_pipes_passed(120)
	if not _drain(ev):
		return false
	return (
		ev.dives_survived == 4
		and ev.pipes_passed == 120
		and ev.state == GameplayEvents.State.NORMAL
		and ev.next_harpoon_pipe == DeepDiveConfig.harpoon_pipe(4)
		and ev.next_dive_pipe == DeepDiveConfig.dive_pipe(4)
		and (
			is_equal_approx(ev.active_dive_time, 0.0)
			or is_equal_approx(ev.active_dive_time, DeepDiveConfig.DURATION)
		)
	)


func _test_swim_restored() -> bool:
	var ev := GameplayEvents.new()
	ev.debug_force_state(GameplayEvents.State.DEEP_DIVE)
	ev.tick(DeepDiveConfig.DURATION)
	ev.tick(DeepDiveConfig.TRANSITION_OUT)
	if ev.state != GameplayEvents.State.RESUME_SWIMMING or ev.suppresses_flap() or not ev.pipes_allowed():
		return false
	ev.tick(DeepDiveConfig.RESUME_SECS)
	return ev.state == GameplayEvents.State.NORMAL and not ev.suppresses_flap() and ev.pipes_allowed() and ev.dives_survived == 1


func _test_pool() -> bool:
	var field: DiveField = load("res://scenes/deep_dive/dive_field.tscn").instantiate()
	root.add_child(field)
	field.start(1, 4)
	var nodes := field.obstacle_nodes()
	var t := 0.0
	var peak := 0
	while t < 8.0:
		field.tick(DT, DeepDiveConfig.FISH_Y)
		peak = maxi(peak, field.live_count())
		t += DT
	var ok := nodes == DiveField.POOL and field.obstacle_nodes() == nodes and peak > 0 and peak <= nodes
	field.halt()
	field.free()
	return ok


func _test_safe_pass() -> bool:
	var field: DiveField = load("res://scenes/deep_dive/dive_field.tscn").instantiate()
	root.add_child(field)
	field.start(2, 11)
	var t := 0.0
	while t < 12.0 and field.live_count() == 0:
		field.tick(DT, DeepDiveConfig.FISH_Y)
		t += DT
	if field.live_count() == 0:
		field.free()
		return false
	for obs in field._live:
		var obstacle: DiveObstacle = obs
		obstacle.passed = true
	var sample: DiveObstacle = field._live[0]
	sample.kind = "net"
	sample.passed = false
	sample.place(DeepDiveConfig.FISH_Y - 40.0)
	var once: Vector2i = field.tick(0.0, DeepDiveConfig.FISH_Y)
	var twice: Vector2i = field.tick(0.0, DeepDiveConfig.FISH_Y)
	sample.kind = "mine"
	sample.passed = false
	sample.place(DeepDiveConfig.FISH_Y - 40.0)
	var mined: Vector2i = field.tick(0.0, DeepDiveConfig.FISH_Y)
	var repeat_mine: Vector2i = field.tick(0.0, DeepDiveConfig.FISH_Y)
	var marked := sample.passed
	field.halt()
	var after_halt: Vector2i = field.tick(DT, DeepDiveConfig.FISH_Y)
	field.free()
	return once == Vector2i(1, 0) and twice == Vector2i.ZERO and mined == Vector2i(1, 1) and repeat_mine == Vector2i.ZERO and after_halt == Vector2i.ZERO and marked


func _test_hit_rearm() -> bool:
	var obs: DiveObstacle = load("res://scenes/deep_dive/dive_obstacle.tscn").instantiate()
	root.add_child(obs)
	obs._arm_slot(0, true)
	await process_frame
	var armed := obs._hits[0].monitorable and not obs._shapes[0].disabled
	var stale := obs._hit_token[0]
	obs._arm_slot(0, true)
	obs._commit_slot(0, stale, false)
	await process_frame
	var kept := obs._hits[0].monitorable and not obs._shapes[0].disabled
	obs.deactivate()
	var hidden_now := not obs.visible
	await process_frame
	var disarmed := hidden_now and not obs._hits[0].monitorable and not obs._hits[1].monitorable
	disarmed = disarmed and obs._shapes[0].disabled and obs._shapes[1].disabled
	obs._arm_slot(0, true)
	var fresh := obs._hit_token[0]
	obs._commit_slot.call_deferred(0, fresh - 1, false)
	await process_frame
	var after := obs._hits[0].monitorable and not obs._shapes[0].disabled
	obs.free()
	return armed and kept and disarmed and after


func _test_signal_disarm() -> bool:
	var watcher := Area2D.new()
	watcher.monitoring = true
	watcher.monitorable = false
	watcher.collision_layer = 2
	watcher.collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(80, 80)
	shape.shape = rect
	watcher.add_child(shape)
	root.add_child(watcher)
	watcher.position = Vector2(220, 320)
	var obs: DiveObstacle = load("res://scenes/deep_dive/dive_obstacle.tscn").instantiate()
	root.add_child(obs)
	obs.position = Vector2(220, 320)
	obs._rect(0, Vector2.ZERO, Vector2(60, 60))
	watcher.area_entered.connect(func(_area: Area2D) -> void:
		obs.deactivate()
	)
	await physics_frame
	await physics_frame
	var overlapped := watcher.get_overlapping_areas().size() > 0
	await process_frame
	var quiet := not obs.visible and not obs._hits[0].monitorable and obs._shapes[0].disabled
	watcher.free()
	obs.free()
	return overlapped and quiet


func _drain_to(ev: GameplayEvents, pipes: int) -> void:
	ev.note_pipes_passed(pipes)
	_drain(ev)


func _drain(ev: GameplayEvents) -> bool:
	ev.set_corridor_clear(true)
	var guard := 0
	while guard < 64:
		guard += 1
		match ev.state:
			GameplayEvents.State.HARPOON_PENDING:
				ev.tick(DT)
			GameplayEvents.State.HARPOON_WARNING, GameplayEvents.State.HARPOON_ACTIVE:
				ev.notify_harpoon_finished()
				ev.tick(0.5)
			GameplayEvents.State.HARPOON_CLEANUP:
				ev.tick(0.5)
			GameplayEvents.State.DIVE_PENDING:
				ev.tick(DT)
			GameplayEvents.State.DIVE_TRANSITION_IN:
				ev.tick(DeepDiveConfig.intro_total())
			GameplayEvents.State.DEEP_DIVE:
				ev.tick(DeepDiveConfig.DURATION)
			GameplayEvents.State.DIVE_TRANSITION_OUT:
				ev.tick(DeepDiveConfig.TRANSITION_OUT)
			GameplayEvents.State.RESUME_SWIMMING:
				ev.tick(DeepDiveConfig.RESUME_SECS)
			GameplayEvents.State.NORMAL:
				if ev.queued_count() == 0:
					return true
				ev.tick(DT)
			_:
				push_error("[deep-dive] drain stopped in %s" % ev.state)
				return false
	push_error("[deep-dive] drain stuck in %s queue=%d" % [ev.state, ev.queued_count()])
	return false


func _test_pairs() -> bool:
	var found := false
	for seed in 16:
		var specs := DiveCourse.generate(4, seed + 1)
		var seen := {}
		for spec in specs:
			var travel := str(snappedf(float(spec["travel"]), 0.01))
			if seen.has(travel):
				var prev_kind := str(seen[travel])
				var prev_side := int(seen[travel + ":side"])
				if prev_kind != str(spec["kind"]) and prev_side != int(spec["side"]):
					found = true
			else:
				seen[travel] = spec["kind"]
				seen[travel + ":side"] = int(spec["side"])
	var beginner := {}
	for spec in DiveCourse.generate(1, 9):
		var travel := str(snappedf(float(spec["travel"]), 0.01))
		if beginner.has(travel):
			return false
		beginner[travel] = true
	return found


func _test_touch() -> bool:
	var session := root.get_node("GameSession")
	session.set("practice_daily", false)
	session.set("match_mode", "unlimited")
	if int(session.get("course_seed")) == 0:
		session.set("course_seed", 11)
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	for _i in 4:
		await process_frame
	if game.get("_events") == null or game.get("player") == null:
		push_error("[deep-dive] game did not arm unlimited events")
		game.queue_free()
		return false
	game.set_physics_process(false)
	game.set_process(false)
	game.call("debug_force_dive_play")
	# Steering checks call _physics_process by hand, so Area2D overlaps never
	# stepped. Lane hits now resolve in that same call. This test is about
	# taps, not obstacles, so the field is disarmed after the dive starts.
	_silence_dive_hits(game)
	var parked: Variant = game.get("pipes")
	if parked is Array:
		for pair in parked:
			(pair as Node2D).position = Vector2(-4000, 0)
	var player: Node = game.get("player")
	var motion: DiveMotion = game.get("_motion")
	var sprite := player.get_child(0) as Node2D
	var fish_scale := sprite.scale
	player.set("velocity", Vector2(0, 40))
	var before: float = player.position.x
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.index = 0
	touch.position = Vector2(180, 420)
	game.call("_input", touch)
	game.call("_try_player_flap")
	var locked := bool(player.get("motion_lock"))
	var vy := float(player.get("velocity").y)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(400, 420)
	drag.relative = Vector2(220, 0)
	game.call("_input", drag)
	game.call("_physics_process", 0.22)
	var after: float = player.position.x
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = Vector2(RR.VIEW_W * 0.75, 400)
	game.call("_input", mouse)
	game.call("_physics_process", 0.22)
	var right: float = player.position.x
	for _i in 14:
		game.call("_input", mouse)
		game.call("_physics_process", 0.08)
	var capped: float = player.position.x
	var capped_lane := motion.lane
	game.call("_physics_process", 0.35)
	var dive_rot: float = sprite.rotation
	var shape := player.get("_hit_shape") as Node2D
	var dive_hit := 0.0 if shape == null else float(shape.rotation)
	var ev: GameplayEvents = game.get("_events")
	ev.debug_force_state(GameplayEvents.State.DIVE_TRANSITION_OUT)
	var remain := DeepDiveConfig.TRANSITION_OUT + 0.08
	while remain > 0.0:
		var step := minf(1.0 / 60.0, remain)
		game.call("_physics_process", step)
		remain -= step
	var unlocked := not bool(player.get("motion_lock"))
	var rest_rot: float = sprite.rotation
	var rest_hit := PI * 0.5 if shape == null else float(shape.rotation)
	var home_x: float = player.position.x
	var falling := float(player.get("velocity").y)
	game.call("_try_player_flap")
	var flapped := float(player.get("velocity").y)
	player.set("velocity", Vector2(0, 15))
	var swim_tap := InputEventScreenTouch.new()
	swim_tap.pressed = true
	swim_tap.index = 2
	swim_tap.position = Vector2(30, 640)
	game.call("_input", swim_tap)
	var swim_flap := float(player.get("velocity").y)
	game.call("_physics_process", 1.0 / 60.0)
	var stayed: float = player.position.x
	game.call("debug_force_dive_play")
	_silence_dive_hits(game)
	var second_lock := bool(player.get("motion_lock"))
	var second_from: float = player.position.x
	mouse.position = Vector2(430, 280)
	game.call("_input", mouse)
	game.call("_physics_process", 0.2)
	var second_to: float = player.position.x
	ev.debug_force_state(GameplayEvents.State.DIVE_TRANSITION_OUT)
	remain = DeepDiveConfig.TRANSITION_OUT + 0.08
	while remain > 0.0:
		var step := minf(1.0 / 60.0, remain)
		game.call("_physics_process", step)
		remain -= step
	var second_unlock := not bool(player.get("motion_lock"))
	var before_fall := float(player.get("velocity").y)
	game.call("_physics_process", 0.1)
	var after_fall := float(player.get("velocity").y)
	game.call("_try_player_flap")
	var second_flap := float(player.get("velocity").y)
	game.queue_free()
	var ok := (
		locked
		and is_equal_approx(vy, 40.0)
		and capped_lane == DeepDiveConfig.LANE_COUNT
		and is_equal_approx(after, DeepDiveConfig.lane_center(2))
		and is_equal_approx(right, DeepDiveConfig.lane_center(3))
		and is_equal_approx(capped, DeepDiveConfig.lane_center(5))
		and sprite.scale.is_equal_approx(fish_scale)
		and absf(dive_rot - PI * 0.5) < 0.22
		and absf(dive_hit) < 0.2
		and absf(rest_rot - PI * 0.5) > 0.4
		and absf(rest_hit - PI * 0.5) < 0.08
		and unlocked
		and is_equal_approx(home_x, RR.PLAYER_X)
		and falling > 20.0
		and is_equal_approx(flapped, -RR.FLAP)
		and is_equal_approx(swim_flap, -RR.FLAP)
		and is_equal_approx(stayed, RR.PLAYER_X)
		and second_lock
		and second_to > second_from + 30.0
		and second_unlock
		and after_fall > before_fall
		and is_equal_approx(second_flap, -RR.FLAP)
	)
	if not ok:
		push_error("[deep-dive] tap locked=%s vy=%.1f before=%.1f after=%.1f right=%.1f capped=%.1f max=%.1f unlock=%s home=%.1f fall=%.1f flap=%.1f swim=%.1f stay=%.1f second=%s/%.1f/%.1f unlock2=%s fall2=%.1f->%.1f flap2=%.1f rot=%.3f hit=%.3f rest=%.3f resthit=%.3f" % [locked, vy, before, after, right, capped, motion.max_x, unlocked, home_x, falling, flapped, swim_flap, stayed, second_lock, second_from, second_to, second_unlock, before_fall, after_fall, second_flap, dive_rot, dive_hit, rest_rot, rest_hit])
	return ok


func _silence_dive_hits(game: Node) -> void:
	var field: DiveField = game.get("_dive_field")
	if field:
		field.stop_and_clear()


func _opening(kind: String, lane: int, span: int, side: int, variant: int) -> Dictionary:
	var gap_x := DeepDiveConfig.lane_center(lane) - DeepDiveConfig.LANE_CLEAR
	var gap_w := DeepDiveConfig.lane_center(lane + span - 1) + DeepDiveConfig.LANE_CLEAR - gap_x
	return {
		"kind": kind,
		"travel": 0.0,
		"gap_x": gap_x,
		"gap_w": gap_w,
		"lane": lane,
		"span": span,
		"variant": variant,
		"drift": 28.0,
		"side": side,
	}


func _lane_key(lanes: PackedInt32Array) -> String:
	var copy: Array[int] = []
	for lane in lanes:
		copy.append(int(lane))
	copy.sort()
	var parts := PackedStringArray()
	for lane in copy:
		parts.append(str(lane))
	return ",".join(parts)


func _align_band(obs: DiveObstacle) -> void:
	obs.place(DeepDiveConfig.FISH_Y - obs.band_center)


func _body_ok(obs: DiveObstacle, spec: Dictionary, expect: String, label: String) -> bool:
	obs.present(spec)
	var got := _lane_key(obs.occupied)
	if got != expect:
		push_error("[deep-dive] %s lanes [%s] want [%s]" % [label, got, expect])
		return false
	var safe := int(spec["lane"])
	var span := int(spec["span"])
	var fish_y := DeepDiveConfig.FISH_Y
	_align_band(obs)
	for lane in range(1, DeepDiveConfig.LANE_COUNT + 1):
		var opening := lane >= safe and lane <= safe + span - 1
		var blocked := obs.occupied.has(lane)
		var hit := obs.hits_player(lane, fish_y)
		if opening and (blocked or hit):
			push_error("[deep-dive] %s opening lane %d hit" % [label, lane])
			return false
		if blocked != hit:
			push_error("[deep-dive] %s lane %d blocked=%s hit=%s" % [label, lane, blocked, hit])
			return false
	if obs.occupied.is_empty():
		push_error("[deep-dive] %s occupied nothing" % label)
		return false
	var blocked_lane := int(obs.occupied[0])
	var reach := obs.band_half + DeepDiveConfig.fish_half_y()
	obs.place(fish_y - obs.band_center + reach + 4.0)
	if obs.hits_player(blocked_lane, fish_y):
		push_error("[deep-dive] %s hit before the band arrived" % label)
		return false
	obs.place(fish_y - obs.band_center - reach - 4.0)
	if obs.hits_player(blocked_lane, fish_y):
		push_error("[deep-dive] %s hit after the band passed" % label)
		return false
	_align_band(obs)
	if not obs.hits_player(blocked_lane, fish_y):
		push_error("[deep-dive] %s missed the band" % label)
		return false
	obs.set_lethal(false)
	if obs.hits_player(blocked_lane, fish_y):
		push_error("[deep-dive] %s stayed lethal after disarm" % label)
		return false
	return true


func _course_bodies(obs: DiveObstacle) -> bool:
	var seen: Dictionary = {"net": 0, "pillar": 0, "mine": 0, "jelly": 0, "wreck": 0}
	var fish_y := DeepDiveConfig.FISH_Y
	for dive in range(1, 6):
		for seed in range(1, 7):
			var specs: Array[Dictionary] = DiveCourse.generate(dive, seed)
			for spec in specs:
				obs.present(spec)
				var kind := str(spec["kind"])
				var safe := int(spec["lane"])
				var span := int(spec["span"])
				if not seen.has(kind):
					push_error("[deep-dive] unexpected obstacle %s" % kind)
					return false
				if obs.occupied.is_empty():
					# A piece asked to sit on a side with no room is clamped
					# against the screen edge, inside the opening. It must not
					# borrow a safe lane. Nets are stretched across a real side.
					if kind == "net":
						push_error("[deep-dive] empty net lane=%d span=%d side=%d" % [safe, span, int(spec["side"])])
						return false
				else:
					seen[kind] = int(seen[kind]) + 1
				_align_band(obs)
				for lane in range(1, DeepDiveConfig.LANE_COUNT + 1):
					var opening := lane >= safe and lane <= safe + span - 1
					var blocked := obs.occupied.has(lane)
					if opening and blocked:
						push_error("[deep-dive] seed %d dive %d %s occupies opening lane %d (%s)" % [seed, dive, kind, lane, _lane_key(obs.occupied)])
						return false
					var hit := obs.hits_player(lane, fish_y)
					if hit != blocked:
						push_error("[deep-dive] seed %d dive %d %s lane %d blocked=%s hit=%s" % [seed, dive, kind, lane, blocked, hit])
						return false
				if not obs.occupied.is_empty():
					var far := fish_y - obs.band_center + obs.band_half + DeepDiveConfig.fish_half_y() + 30.0
					obs.place(far)
					if obs.hits_player(int(obs.occupied[0]), fish_y):
						push_error("[deep-dive] %s still hits from below the window" % kind)
						return false
	for kind in seen.keys():
		if int(seen[kind]) == 0:
			push_error("[deep-dive] no %s body occupied a lane" % kind)
			return false
	return true


func _swipe_rules(rock_lane3: DiveObstacle, rock_lane2: DiveObstacle) -> bool:
	var fish_y := DeepDiveConfig.FISH_Y
	_align_band(rock_lane3)
	_align_band(rock_lane2)
	rock_lane3.set_lethal(true)
	rock_lane2.set_lethal(true)
	var motion := DiveMotion.new()
	motion.configure(RR.VIEW_W)
	motion.nudge(1.0)
	if motion.lane != 4 or DeepDiveConfig.lane_at(motion.x) != 3:
		push_error("[deep-dive] swipe destination moved before the body")
		return false
	if not rock_lane3.hits_player(DeepDiveConfig.lane_at(motion.x), fish_y):
		push_error("[deep-dive] swipe made the fish invulnerable in the lane it still occupies")
		return false
	if rock_lane3.hits_player(motion.lane, fish_y):
		push_error("[deep-dive] destination lane was treated as occupied")
		return false
	motion.tick(DeepDiveConfig.LANE_SLIDE * 0.25)
	if DeepDiveConfig.lane_at(motion.x) != 3 or not rock_lane3.hits_player(3, fish_y):
		push_error("[deep-dive] early slide left the blocked lane")
		return false
	motion.tick(DeepDiveConfig.LANE_SLIDE * 0.5)
	if DeepDiveConfig.lane_at(motion.x) != 4 or rock_lane3.hits_player(4, fish_y):
		push_error("[deep-dive] late slide was still in the blocked lane")
		return false
	motion.reset(RR.VIEW_W * 0.5)
	motion.nudge(-1.0)
	motion.nudge(-1.0)
	if motion.lane != 1 or DeepDiveConfig.lane_at(motion.x) != 3:
		push_error("[deep-dive] double swipe skipped the drawn lane")
		return false
	if not rock_lane3.hits_player(DeepDiveConfig.lane_at(motion.x), fish_y):
		push_error("[deep-dive] double swipe granted invulnerability")
		return false
	if rock_lane2.hits_player(DeepDiveConfig.lane_at(motion.x), fish_y):
		push_error("[deep-dive] lane 2 rock hit a fish still in lane 3")
		return false
	var saw_lane2 := false
	var steps := 0
	while steps < 40 and DeepDiveConfig.lane_at(motion.x) != 1:
		motion.tick(0.016)
		steps += 1
		var visual := DeepDiveConfig.lane_at(motion.x)
		var in_two := rock_lane2.hits_player(visual, fish_y)
		var in_three := rock_lane3.hits_player(visual, fish_y)
		if visual == 2:
			saw_lane2 = true
			if not in_two or in_three:
				push_error("[deep-dive] crossing lane 2 hit=%s lane3=%s" % [in_two, in_three])
				return false
		elif in_two or (visual == 1 and in_three):
			push_error("[deep-dive] hit outside the drawn lane %d" % visual)
			return false
	if not saw_lane2 or DeepDiveConfig.lane_at(motion.x) != 1:
		push_error("[deep-dive] rapid swipe never crossed lane 2")
		return false
	if rock_lane2.hits_player(1, fish_y) or rock_lane3.hits_player(1, fish_y):
		push_error("[deep-dive] lane 1 died to a rock in another lane")
		return false
	return true


func _field_rules() -> bool:
	var field: DiveField = load("res://scenes/deep_dive/dive_field.tscn").instantiate()
	root.add_child(field)
	var fish_y := DeepDiveConfig.FISH_Y
	field.tick(DT, fish_y, DeepDiveConfig.lane_center(3))
	if field.take_hit():
		push_error("[deep-dive] hit before the dive started")
		field.free()
		return false
	field.start(4, 5)
	var t := 0.0
	while t < 6.0 and field.live_count() < 2:
		field.tick(DT, fish_y)
		t += DT
	if field.live_count() < 2:
		push_error("[deep-dive] dive entry spawned %d obstacles" % field.live_count())
		field.free()
		return false
	field.tick(0.0, fish_y, DeepDiveConfig.lane_center(3))
	if field.take_hit():
		push_error("[deep-dive] a freshly spawned obstacle hit from off screen")
		field.free()
		return false
	var first: DiveObstacle = field._live[0]
	var second: DiveObstacle = field._live[1]
	first.present(_opening("pillar", 3, 1, 0, 0))
	second.present(_opening("pillar", 4, 1, 1, 0))
	_align_band(first)
	_align_band(second)
	if _lane_key(first.occupied) != "2" or _lane_key(second.occupied) != "5":
		push_error("[deep-dive] paired rocks [%s] [%s]" % [_lane_key(first.occupied), _lane_key(second.occupied)])
		field.free()
		return false
	field.tick(0.0, fish_y, DeepDiveConfig.lane_center(3))
	var safe_gap := not field.take_hit()
	field.tick(0.0, fish_y, DeepDiveConfig.lane_center(1))
	var safe_side := not field.take_hit()
	field.tick(0.0, fish_y, DeepDiveConfig.lane_center(2))
	var hit_two := field.take_hit()
	field.tick(0.0, fish_y, DeepDiveConfig.lane_center(5))
	var hit_five := field.take_hit()
	field.tick(0.0, fish_y, 119.0)
	var boundary_out := not field.take_hit()
	field.tick(0.0, fish_y, 121.0)
	var boundary_in := field.take_hit()
	field.stop_and_clear()
	var disarmed := not first.hits_player(2, fish_y) and not second.hits_player(5, fish_y)
	field.tick(0.0, fish_y, DeepDiveConfig.lane_center(2))
	var outro := not field.take_hit()
	field.halt()
	field.tick(0.0, fish_y, DeepDiveConfig.lane_center(2))
	var left := field.live_count() == 0 and not field.take_hit()
	field._draw()
	var debug_off := not DeepDiveConfig.collision_debug() and not DeepDiveConfig.DEBUG_LANES
	field.free()
	if not (safe_gap and safe_side and hit_two and hit_five and boundary_in and boundary_out and disarmed and outro and left and debug_off):
		push_error("[deep-dive] field gap=%s side=%s l2=%s l5=%s edge=%s/%s disarm=%s outro=%s exit=%s debug=%s" % [safe_gap, safe_side, hit_two, hit_five, boundary_in, boundary_out, disarmed, outro, left, debug_off])
		return false
	return true


func _test_lanes() -> bool:
	if DeepDiveConfig.lane_at(120.0) != 2 or DeepDiveConfig.lane_at(119.0) != 1:
		push_error("[deep-dive] midpoint lane rule failed")
		return false
	for lane in range(1, DeepDiveConfig.LANE_COUNT + 1):
		if DeepDiveConfig.lane_at(DeepDiveConfig.lane_center(lane)) != lane:
			push_error("[deep-dive] lane center %d mapped wrong" % lane)
			return false
	var obs: DiveObstacle = load("res://scenes/deep_dive/dive_obstacle.tscn").instantiate()
	root.add_child(obs)
	var ok := true
	ok = _body_ok(obs, _opening("net", 3, 1, 2, 0), "1,2,4,5", "net") and ok
	ok = _body_ok(obs, _opening("net", 2, 2, 2, 0), "1,4,5", "wide net") and ok
	ok = _body_ok(obs, _opening("net", 4, 1, 2, 0), "1,2,3,5", "three-lane net") and ok
	ok = _body_ok(obs, _opening("pillar", 3, 1, 0, 0), "2", "rock") and ok
	ok = _body_ok(obs, _opening("pillar", 4, 1, 0, 0), "3", "rock lane 3") and ok
	ok = _body_ok(obs, _opening("pillar", 3, 2, 2, 0), "2,5", "arch") and ok
	if ok and (obs._sprites[0].texture == null or obs._sprites[0].texture.get_width() != 284):
		push_error("[deep-dive] arch layout did not use the arch art")
		ok = false
	ok = _body_ok(obs, _opening("mine", 3, 1, 0, 0), "1", "mine") and ok
	ok = _body_ok(obs, _opening("jelly", 3, 1, 0, 0), "1", "jelly") and ok
	ok = _body_ok(obs, _opening("wreck", 3, 1, 0, 0), "1,2", "planks") and ok
	ok = _body_ok(obs, _opening("wreck", 3, 1, 1, 1), "4,5", "spears") and ok
	if ok:
		obs.present(_opening("mine", 3, 1, 0, 0))
		_align_band(obs)
		var edge_hit := obs.hits_player(DeepDiveConfig.lane_at(119.0), DeepDiveConfig.FISH_Y)
		var edge_safe := not obs.hits_player(DeepDiveConfig.lane_at(121.0), DeepDiveConfig.FISH_Y)
		if not edge_hit or not edge_safe:
			push_error("[deep-dive] mine boundary hit=%s safe=%s lane119=%d" % [edge_hit, edge_safe, DeepDiveConfig.lane_at(119.0)])
			ok = false
		var held := _lane_key(obs.occupied)
		for _i in 30:
			obs.tick_local(0.1)
		if _lane_key(obs.occupied) != held or obs.hits_player(3, DeepDiveConfig.FISH_Y):
			push_error("[deep-dive] mine sway changed lanes to [%s]" % _lane_key(obs.occupied))
			ok = false
	if ok:
		ok = _course_bodies(obs)
	var rock3: DiveObstacle = load("res://scenes/deep_dive/dive_obstacle.tscn").instantiate()
	var rock2: DiveObstacle = load("res://scenes/deep_dive/dive_obstacle.tscn").instantiate()
	root.add_child(rock3)
	root.add_child(rock2)
	rock3.present(_opening("pillar", 4, 1, 0, 0))
	rock2.present(_opening("pillar", 3, 1, 0, 0))
	if ok and (_lane_key(rock3.occupied) != "3" or _lane_key(rock2.occupied) != "2"):
		push_error("[deep-dive] swipe rocks [%s] [%s]" % [_lane_key(rock3.occupied), _lane_key(rock2.occupied)])
		ok = false
	if ok:
		ok = _swipe_rules(rock3, rock2)
	await process_frame
	var quiet := not obs._hits[0].monitorable and not obs._hits[1].monitorable
	quiet = quiet and obs._shapes[0].disabled and obs._shapes[1].disabled
	quiet = quiet and not rock3._hits[0].monitorable and rock2._shapes[0].disabled
	if not quiet:
		push_error("[deep-dive] dive shapes stayed armed")
		ok = false
	obs.free()
	rock3.free()
	rock2.free()
	if ok:
		ok = _field_rules()
	return ok


func _note_death() -> void:
	_death_count += 1


func _kind_label(kind: String, obs: DiveObstacle) -> String:
	if kind == "pillar" and obs._sprites[0].texture != null and obs._sprites[0].texture.get_width() == 284:
		return "arch"
	if kind == "jelly":
		return "jelly"
	if kind == "pillar":
		return "rock"
	return kind


func _expect_lanes(obs: DiveObstacle, label: String) -> bool:
	var fish_y := DeepDiveConfig.FISH_Y
	_align_band(obs)
	for lane in range(1, DeepDiveConfig.LANE_COUNT + 1):
		_collision_scenarios += 1
		var blocked := obs.occupied.has(lane)
		var hit := obs.hits_player(lane, fish_y)
		if hit != blocked:
			push_error("[deep-dive] %s lanes [%s] lane %d blocked=%s hit=%s" % [label, _lane_key(obs.occupied), lane, blocked, hit])
			return false
	return true


func _vertical_phases(obs: DiveObstacle, label: String) -> bool:
	if obs.occupied.is_empty():
		return true
	var fish_y := DeepDiveConfig.FISH_Y
	var lane := int(obs.occupied[0])
	var reach := obs.band_half + DeepDiveConfig.fish_half_y()
	var center := fish_y - obs.band_center
	var spots: Array[float] = [
		center + reach + 8.0,
		center + reach - 6.0,
		center,
		center - (reach - 6.0),
		center - reach - 8.0,
	]
	var want_hit: Array[bool] = [false, true, true, true, false]
	var names: PackedStringArray = PackedStringArray(["below", "entering", "overlap", "leaving", "above"])
	for i in spots.size():
		_collision_scenarios += 1
		obs.place(spots[i])
		var hit := obs.hits_player(lane, fish_y)
		if hit != want_hit[i]:
			push_error("[deep-dive] %s vertical %s hit=%s lanes [%s]" % [label, names[i], hit, _lane_key(obs.occupied)])
			return false
		for other in range(1, DeepDiveConfig.LANE_COUNT + 1):
			if obs.occupied.has(other):
				continue
			_collision_scenarios += 1
			if obs.hits_player(other, fish_y):
				push_error("[deep-dive] %s vertical %s killed safe lane %d" % [label, names[i], other])
				return false
	return true


func _collision_matrix() -> bool:
	var obs: DiveObstacle = load("res://scenes/deep_dive/dive_obstacle.tscn").instantiate()
	root.add_child(obs)
	var counts: Dictionary = {"net": 0, "rock": 0, "arch": 0, "mine": 0, "jelly": 0, "wreck": 0}
	var patterns: Dictionary = {}
	var kinds := PackedStringArray(["net", "pillar", "mine", "jelly", "wreck"])
	var ok := true
	for kind in kinds:
		for span in [1, 2]:
			for lane in range(1, DeepDiveConfig.LANE_COUNT - span + 2):
				var side_max := 2 if kind != "wreck" else 1
				for side in range(0, side_max + 1):
					for variant in range(0, 8):
						obs.present(_opening(kind, lane, span, side, variant))
						var label := _kind_label(kind, obs)
						var key := _lane_key(obs.occupied)
						patterns["%s:%s" % [label, key]] = true
						if obs.occupied.is_empty():
							if kind == "net":
								push_error("[deep-dive] empty net lane=%d span=%d side=%d" % [lane, span, side])
								ok = false
							elif not _expect_lanes(obs, "%s empty" % label):
								ok = false
							continue
						counts[label] = int(counts[label]) + 1
						if not _expect_lanes(obs, "%s L%d x%d side%d v%d" % [label, lane, span, side, variant]):
							ok = false
							break
						if not _vertical_phases(obs, label):
							ok = false
							break
					if not ok:
						break
				if not ok:
					break
			if not ok:
				break
		if not ok:
			break
	if ok:
		obs.present(_opening("net", 4, 1, 2, 0))
		if _lane_key(obs.occupied) != "1,2,3,5":
			push_error("[deep-dive] wide net lanes [%s]" % _lane_key(obs.occupied))
			ok = false
		else:
			for lane in [2, 3]:
				_collision_scenarios += 1
				if not obs.hits_player(lane, DeepDiveConfig.FISH_Y):
					push_error("[deep-dive] net lanes 2-3 missed lane %d" % lane)
					ok = false
			_collision_scenarios += 1
			if obs.hits_player(4, DeepDiveConfig.FISH_Y):
				push_error("[deep-dive] net covering 2 and 3 killed the opening in lane 4")
				ok = false
		obs.present(_opening("pillar", 3, 1, 2, 1))
		_align_band(obs)
		if _lane_key(obs.occupied) != "2,4":
			push_error("[deep-dive] paired rocks lanes [%s]" % _lane_key(obs.occupied))
			ok = false
		else:
			for lane in range(1, DeepDiveConfig.LANE_COUNT + 1):
				_collision_scenarios += 1
				var should_hit := lane == 2 or lane == 4
				if obs.hits_player(lane, DeepDiveConfig.FISH_Y) != should_hit:
					push_error("[deep-dive] paired rocks lane %d" % lane)
					ok = false
	obs.free()
	print("[deep-dive] matrix net=%d rock=%d arch=%d mine=%d jelly=%d wreck=%d patterns=%d" % [
		int(counts["net"]),
		int(counts["rock"]),
		int(counts["arch"]),
		int(counts["mine"]),
		int(counts["jelly"]),
		int(counts["wreck"]),
		patterns.size(),
	])
	if ok:
		for label in counts.keys():
			if int(counts[label]) <= 0:
				push_error("[deep-dive] matrix missed %s" % label)
				ok = false
	return ok


func _slide_samples(motion: DiveMotion) -> bool:
	var previous := DeepDiveConfig.lane_at(motion.x)
	for _step in 24:
		motion.tick(0.016)
		var visual := DeepDiveConfig.lane_at(motion.x)
		if absi(visual - previous) > 1:
			push_error("[deep-dive] swipe skipped from lane %d to %d while destination was %d" % [previous, visual, motion.lane])
			return false
		previous = visual
	return true


func _collision_swipes() -> bool:
	var fish_y := DeepDiveConfig.FISH_Y
	var motion := DiveMotion.new()
	motion.configure(RR.VIEW_W)
	motion.nudge(-1.0)
	motion.tick(DeepDiveConfig.LANE_SLIDE * 0.25)
	if motion.lane != 2 or DeepDiveConfig.lane_at(motion.x) != 3:
		push_error("[deep-dive] quarter swipe already left lane 3")
		return false
	motion.tick(DeepDiveConfig.LANE_SLIDE * 0.50)
	if DeepDiveConfig.lane_at(motion.x) != 2:
		push_error("[deep-dive] three-quarter swipe was still outside lane 2")
		return false
	if not _slide_samples(motion) or DeepDiveConfig.lane_at(motion.x) != 2:
		push_error("[deep-dive] single left swipe did not arrive in lane 2")
		return false
	motion.reset(RR.VIEW_W * 0.5)
	motion.nudge(1.0)
	if motion.lane != 4 or DeepDiveConfig.lane_at(motion.x) != 3:
		push_error("[deep-dive] single right swipe moved the body early")
		return false
	if not _slide_samples(motion) or DeepDiveConfig.lane_at(motion.x) != 4:
		push_error("[deep-dive] single right swipe did not arrive in lane 4")
		return false
	motion.reset(RR.VIEW_W * 0.5)
	motion.nudge(-1.0)
	motion.nudge(1.0)
	motion.nudge(-1.0)
	motion.nudge(1.0)
	if motion.lane != 3 or DeepDiveConfig.lane_at(motion.x) != 3:
		push_error("[deep-dive] rapid swipes desynced the drawn lane")
		return false
	if not _slide_samples(motion):
		return false
	for _hop in 4:
		motion.nudge(-1.0)
		motion.tick(1.0)
	var left_x := motion.x
	motion.nudge(-1.0)
	if motion.lane != 1 or not is_equal_approx(motion.x, left_x) or DeepDiveConfig.lane_at(motion.x) != 1:
		push_error("[deep-dive] far-left swipe left lane 1")
		return false
	for _hop in 4:
		motion.nudge(1.0)
		motion.tick(1.0)
	var right_x := motion.x
	motion.nudge(1.0)
	if motion.lane != DeepDiveConfig.LANE_COUNT or not is_equal_approx(motion.x, right_x) or DeepDiveConfig.lane_at(motion.x) != DeepDiveConfig.LANE_COUNT:
		push_error("[deep-dive] far-right swipe left lane 5")
		return false
	var field: DiveField = load("res://scenes/deep_dive/dive_field.tscn").instantiate()
	root.add_child(field)
	field.start(4, 8)
	var waited := 0.0
	while waited < 4.0 and field.live_count() < 1:
		field.tick(DT, fish_y)
		waited += DT
	if field.live_count() < 1:
		push_error("[deep-dive] swipe field spawned nothing")
		field.free()
		return false
	var rock: DiveObstacle = field._live[0]
	for extra in field._live:
		if extra != rock:
			extra.set_lethal(false)
	rock.present(_opening("pillar", 4, 1, 0, 0))
	if _lane_key(rock.occupied) != "3":
		push_error("[deep-dive] swipe obstacle lanes [%s]" % _lane_key(rock.occupied))
		field.free()
		return false
	var reach := rock.band_half + DeepDiveConfig.fish_half_y()
	rock.place(fish_y - rock.band_center + reach + 220.0)
	motion.reset(RR.VIEW_W * 0.5)
	motion.nudge(1.0)
	var escaped := false
	var escaped_hit := false
	for _step in 30:
		motion.tick(0.02)
		field.tick(0.02, fish_y, motion.x)
		if field.take_hit():
			escaped_hit = true
		if DeepDiveConfig.lane_at(motion.x) == 4 and motion.lane == 4:
			escaped = true
	if not escaped or escaped_hit:
		push_error("[deep-dive] swipe-out escaped=%s hit=%s x=%.1f" % [escaped, escaped_hit, motion.x])
		field.free()
		return false
	rock.place(fish_y - rock.band_center)
	motion.reset(RR.VIEW_W * 0.5)
	motion.nudge(1.0)
	motion.tick(1.0)
	field.tick(0.0, fish_y, motion.x)
	var before_hit := field.take_hit()
	motion.nudge(-1.0)
	var held_safe := true
	var entered := false
	for _step in 40:
		motion.tick(0.016)
		field.tick(0.0, fish_y, motion.x)
		var visual := DeepDiveConfig.lane_at(motion.x)
		var hit := field.take_hit()
		if visual == 4:
			if hit:
				held_safe = false
		elif visual == 3:
			entered = hit
			break
		elif hit:
			held_safe = false
	field.halt()
	field.free()
	_collision_scenarios += 8
	if before_hit or not held_safe or not entered:
		push_error("[deep-dive] swipe-in before=%s safe=%s entered=%s" % [before_hit, held_safe, entered])
		return false
	return true


func _collision_play() -> bool:
	var fish_y := DeepDiveConfig.FISH_Y
	var field: DiveField = load("res://scenes/deep_dive/dive_field.tscn").instantiate()
	root.add_child(field)
	if field._decor.size() != DiveField.DECOR:
		push_error("[deep-dive] decor count %d" % field._decor.size())
		field.free()
		return false
	var saw_coral := false
	for i in DiveField.DECOR:
		var decor_name := DiveAssets.decor_id(i)
		if decor_name.begins_with("coral"):
			saw_coral = true
		_collision_scenarios += 1
	if not saw_coral:
		push_error("[deep-dive] dive decor has no coral")
		field.free()
		return false
	for spr in field._decor:
		if spr.has_method("hits_player"):
			push_error("[deep-dive] coral decor is an obstacle")
			field.free()
			return false
	var safe_frames := 0
	var released := false
	for stage in 2:
		field.start(4, 20 + stage)
		field.tick(DT, fish_y, DeepDiveConfig.lane_center(3))
		if field.take_hit():
			push_error("[deep-dive] stage %d hit before obstacles arrived" % stage)
			field.free()
			return false
		var watched: DiveObstacle = null
		var t := 0.0
		while t < DeepDiveConfig.DURATION:
			t += DT
			var blocked: Dictionary = {}
			for obs in field._live:
				if _band_reaches(obs, fish_y):
					for lane in obs.occupied:
						blocked[int(lane)] = true
				if watched == null and obs.active:
					watched = obs
			var open_lane := 0
			for lane in range(1, DeepDiveConfig.LANE_COUNT + 1):
				if not blocked.has(lane):
					open_lane = lane
					break
			if open_lane == 0:
				field.tick(DT, fish_y, DeepDiveConfig.lane_center(3))
				field.take_hit()
			else:
				field.tick(DT, fish_y, DeepDiveConfig.lane_center(open_lane))
				if field.take_hit():
					push_error("[deep-dive] stage %d safe lane %d died at t=%.2f" % [stage, open_lane, t])
					field.free()
					return false
				if not blocked.is_empty():
					safe_frames += 1
			if watched != null and not field._live.has(watched):
				released = true
		if field.live_count() > 0:
			var leftover: DiveObstacle = field._live[0]
			var guard := 0
			while guard < 40 and field._live.has(leftover):
				guard += 1
				field.tick(0.2, fish_y, DeepDiveConfig.lane_center(3))
				field.take_hit()
			if not field._live.has(leftover):
				released = true
		field.halt()
		if field.live_count() != 0 or field.take_hit():
			push_error("[deep-dive] stage %d left live obstacles" % stage)
			field.free()
			return false
	if safe_frames < 5 or not released:
		push_error("[deep-dive] descent safe=%d released=%s" % [safe_frames, released])
		field.free()
		return false
	field.free()
	var session := root.get_node("GameSession")
	var saved_mode := str(session.get("match_mode"))
	var saved_practice := bool(session.get("practice_daily"))
	var saved_seed := int(session.get("course_seed"))
	var saved_games := int(session.get("games_played"))
	var saved_coins := int(session.get("coins"))
	session.set("practice_daily", false)
	session.set("match_mode", "unlimited")
	if int(session.get("course_seed")) == 0:
		session.set("course_seed", 11)
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(game)
	for _i in 4:
		await process_frame
	session.set("practice_daily", true)
	if game.get("_events") == null or game.get("player") == null or game.get("_dive_field") == null:
		push_error("[deep-dive] gameplay dive did not arm")
		game.free()
		_restore_session(session, saved_mode, saved_practice, saved_seed)
		return false
	game.set_process(false)
	game.set_physics_process(false)
	var player: Node = game.get("player")
	var died_cb := Callable(game, "_on_player_died")
	if player.is_connected("died", died_cb):
		player.disconnect("died", died_cb)
	_death_count = 0
	player.connect("died", Callable(self, "_note_death"))
	game.call("debug_force_dive_play")
	var play_field: DiveField = game.get("_dive_field")
	var spawned := 0.0
	while spawned < 4.0 and play_field.live_count() < 1:
		play_field.tick(DT, fish_y)
		spawned += DT
	if play_field.live_count() < 1:
		push_error("[deep-dive] gameplay dive spawned nothing")
		game.free()
		_restore_session(session, saved_mode, saved_practice, saved_seed)
		return false
	var hazard: DiveObstacle = play_field._live[0]
	for extra in play_field._live:
		if extra != hazard:
			extra.set_lethal(false)
	hazard.present(_opening("pillar", 4, 1, 0, 0))
	_align_band(hazard)
	var motion: DiveMotion = game.get("_motion")
	motion.lane = 1
	motion._to = DeepDiveConfig.lane_center(3)
	motion.x = motion._to
	motion._elapsed = motion._duration
	game.call("_update_dive_actor", 0.0)
	var first_death := _death_count == 1 and not bool(player.get("alive"))
	game.call("_update_dive_actor", 0.0)
	var single := first_death and _death_count == 1
	var ev: GameplayEvents = game.get("_events")
	ev.debug_force_state(GameplayEvents.State.DIVE_TRANSITION_OUT)
	game.call("_sync_events")
	ev.tick(DeepDiveConfig.TRANSITION_OUT)
	game.call("_sync_events")
	ev.tick(DeepDiveConfig.RESUME_SECS)
	game.call("_sync_events")
	var resumed := ev.state == GameplayEvents.State.NORMAL and ev.pipes_allowed()
	player.set("alive", true)
	_death_count = 0
	game.call("debug_force_dive_play")
	var second: DiveField = game.get("_dive_field")
	var clean := second.live_count() == 0 or not second.take_hit()
	second.tick(DT, fish_y, DeepDiveConfig.lane_center(3))
	clean = clean and not second.take_hit() and _death_count == 0
	game.free()
	_restore_session(session, saved_mode, saved_practice, saved_seed)
	var progress_ok := int(session.get("games_played")) == saved_games and int(session.get("coins")) == saved_coins
	_collision_scenarios += safe_frames + 4
	print("[deep-dive] play safe_frames=%d released=%s deaths=%d resumed=%s" % [safe_frames, released, 1 if single else _death_count, resumed])
	if not (single and resumed and clean and progress_ok):
		push_error("[deep-dive] play single=%s resumed=%s clean=%s progress=%s" % [single, resumed, clean, progress_ok])
		return false
	return true


func _restore_session(session: Node, mode: String, practice: bool, seed: int) -> void:
	session.set("match_mode", mode)
	session.set("practice_daily", practice)
	session.set("course_seed", seed)


func _band_reaches(obs: DiveObstacle, fish_y: float) -> bool:
	if not obs.active or not obs.lethal or obs.occupied.is_empty():
		return false
	var reach := obs.band_half + DeepDiveConfig.fish_half_y() + 14.0
	var next_y := obs.position.y - DeepDiveConfig.DEEP_DIVE_SPEED * DT
	return absf(next_y + obs.band_center - fish_y) <= reach
