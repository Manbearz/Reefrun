extends SceneTree

const DT := 0.05


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
