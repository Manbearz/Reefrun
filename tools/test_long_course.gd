extends SceneTree

# Development-only fast-forward. It never claims a daily attempt or submits a score.
# Godot --headless --path . --script res://tools/test_long_course.gd

const CourseBuilderScript := preload("res://scripts/course_builder.gd")
const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")
const DAILY_MARKS: Array[int] = [30, 60, 75, 79, 80, 81, 90, 100, 120, 200, 500, 1000]
const DAILY_TARGET := 1000
const UNLIMITED_MARKS: Array[int] = [30, 60, 75, 79, 80, 81, 90, 120, 150, 200, 220]
const UNLIMITED_TARGET := 220
const DT := 0.1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var session := root.get_node("GameSession")
	var saved_mode: String = session.match_mode
	var saved_seed: int = session.course_seed
	var saved_practice: bool = session.practice_daily
	var saved_attempt := str(session.current_challenge().get("attempt_id", ""))
	var version := Engine.get_version_info()
	print("[long-course] godot %s.%s.%s" % [version["major"], version["minor"], version["patch"]])
	var saved_games := int(session.games_played)
	var saved_coins := int(session.coins)
	var today: Dictionary = DailyChallengeScript.unverified_local(int(Time.get_unix_time_from_system()))
	var historical: Dictionary = DailyChallengeScript.make("2026-10-12")
	var historical_seed := int(historical["course_seed"])
	var seeds: Array[int] = []
	var names := PackedStringArray()
	_add_seed(seeds, names, "today:%s" % str(today["challenge_date"]), int(today["course_seed"]))
	_add_seed(seeds, names, "2026-10-12", historical_seed)
	_add_seed(seeds, names, "synthetic", 1)
	_add_seed(seeds, names, "boundary", CourseBuilderScript.extension_seed(historical_seed, RR.PIPE_COUNT))
	var ok := true
	ok = _check("builder", _test_builder(seeds, names)) and ok
	ok = _check("timeouts", _test_timeouts()) and ok
	session.practice_daily = true
	session.course_seed = historical_seed
	ok = _check("extend_without_events", _test_extend_without_events(historical_seed)) and ok
	var daily_layout: Array = []
	for i in seeds.size():
		var run_seed := seeds[i]
		var run_name := names[i]
		var daily = _boot("daily", run_seed)
		var daily_run: Dictionary = _fast_forward(daily, false, DAILY_MARKS, DAILY_TARGET, run_seed, run_name)
		var run_ok := bool(daily_run["ok"]) and _matches_grown(daily, run_seed)
		run_ok = run_ok and daily._events == null and not GameplayEvents.applies_to("daily", false)
		if i == 0:
			run_ok = run_ok and _test_harpoon_stall(daily)
		if not run_ok:
			push_error("[long-course] FAIL daily spawner seed=%d (%s) score=%d spawn=%d layout=%d" % [
				run_seed, run_name, daily.score, daily.spawn_index, daily.layout.size(),
			])
		ok = _check("daily:%s" % run_name, run_ok) and ok
		print("[long-course] measure %s seed=%d score=%d spawn=%d layout=%d pipes=%d nodes=%d coins=%d step80=%.1fus step1000=%.1fus mem=%d->%d" % [
			run_name,
			run_seed,
			int(daily_run["score"]),
			int(daily_run["spawn"]),
			int(daily_run["layout"]),
			int(daily_run["peak_pipes"]),
			int(daily_run["peak_nodes"]),
			int(daily_run["coins"]),
			float(daily_run["step80"]),
			float(daily_run["step1000"]),
			int(daily_run["mem0"]),
			int(daily_run["mem1"]),
		])
		if run_seed == historical_seed:
			daily_layout = _copy_specs(daily.layout)
			var again = _boot("daily", run_seed)
			var again_run: Dictionary = _fast_forward(again, false, DAILY_MARKS, DAILY_TARGET, run_seed, run_name + ":repeat")
			var same := bool(again_run["ok"]) and _matches_grown(again, run_seed) and _same_gaps(daily.layout, again.layout)
			if not same:
				push_error("[long-course] FAIL repeat seed=%d" % run_seed)
			ok = _check("repeat:%s" % run_name, same) and ok
			again.free()
		daily.free()
	var missing = _boot("unlimited", historical_seed)
	ok = _check("missing_dive_recovers", _test_missing_dive(missing)) and ok
	missing.free()
	var unlimited = _boot("unlimited", historical_seed)
	var unlimited_run: Dictionary = _fast_forward(unlimited, true, UNLIMITED_MARKS, UNLIMITED_TARGET, historical_seed, "unlimited")
	ok = _check("unlimited_run", bool(unlimited_run["ok"])) and ok
	ok = _check("unlimited_matches_seed", _matches_grown(unlimited, historical_seed)) and ok
	ok = _check("same_obstacles", _same_obstacles(daily_layout, unlimited.layout, UNLIMITED_TARGET)) and ok
	ok = _check("unlimited_schedule", _test_schedule(unlimited)) and ok
	unlimited.free()
	ok = _check("progress_untouched", int(session.games_played) == saved_games and int(session.coins) == saved_coins) and ok
	session.match_mode = saved_mode
	session.course_seed = saved_seed
	session.practice_daily = saved_practice
	var attempt_now := str(session.current_challenge().get("attempt_id", ""))
	ok = _check("attempt_untouched", attempt_now == saved_attempt) and ok
	print("[long-course] ok=%s seeds=%d attempt=%s" % [ok, seeds.size(), attempt_now])
	quit(0 if ok else 1)


func _check(name: String, passed: bool) -> bool:
	if not passed:
		push_error("[long-course] FAIL %s" % name)
	else:
		print("[long-course] pass %s" % name)
	return passed


func _add_seed(seeds: Array[int], names: PackedStringArray, name: String, seed: int) -> void:
	if seeds.has(seed):
		print("[long-course] %s reuses seed %d" % [name, seed])
		return
	seeds.append(seed)
	names.append(name)


func _test_builder(seeds: Array[int], names: PackedStringArray) -> bool:
	var ok := true
	var first: Array = []
	for s in seeds.size():
		var seed := seeds[s]
		var name := names[s]
		if not _builder_seed(seed, name):
			ok = false
		if s == 0:
			first = _grow(seed, DAILY_TARGET + CourseBuilderScript.CHUNK_PIPES)["layout"]
		elif not first.is_empty():
			var other: Array = _grow(seed, RR.PIPE_COUNT)["layout"]
			var distinct := false
			for i in mini(RR.PIPE_COUNT, other.size()):
				if not _same_obstacle(first[i], other[i]):
					distinct = true
					break
			if not distinct:
				push_error("[long-course] FAIL seed=%d checkpoint=0 matches %s" % [seed, names[0]])
				ok = false
	return ok


func _builder_seed(seed: int, name: String) -> bool:
	var opening := CourseBuilderScript.generate(seed)
	var again := CourseBuilderScript.generate(seed)
	var target := DAILY_TARGET + CourseBuilderScript.CHUNK_PIPES
	var grown_a := _grow(seed, target)
	var grown_b := _grow(seed, target)
	if opening["layout"].size() != RR.PIPE_COUNT:
		push_error("[long-course] FAIL seed=%d checkpoint=0 opening=%d" % [seed, opening["layout"].size()])
		return false
	if CourseBuilderScript.extension_seed(seed, RR.PIPE_COUNT) != seed + RR.PIPE_COUNT * 13 + 3:
		push_error("[long-course] FAIL seed=%d extension formula" % seed)
		return false
	var layout_a: Array = grown_a["layout"]
	var layout_b: Array = grown_b["layout"]
	if layout_a.size() < target or layout_a.size() != layout_b.size():
		push_error("[long-course] FAIL seed=%d checkpoint=%d layout=%d/%d" % [seed, DAILY_TARGET, layout_a.size(), layout_b.size()])
		return false
	var spacing := RR.PIPE_SPEED * RR.PIPE_INTERVAL
	for i in layout_a.size():
		if not CourseBuilderScript.specs_equal(layout_a[i], layout_b[i]):
			push_error("[long-course] FAIL seed=%d pipe=%d runs differ" % [seed, i])
			return false
		if i < RR.PIPE_COUNT and not CourseBuilderScript.specs_equal(layout_a[i], opening["layout"][i]):
			push_error("[long-course] FAIL seed=%d pipe=%d opening changed" % [seed, i])
			return false
		if i < RR.PIPE_COUNT and not CourseBuilderScript.specs_equal(opening["layout"][i], again["layout"][i]):
			push_error("[long-course] FAIL seed=%d pipe=%d generate differs" % [seed, i])
			return false
		if not _pipe_sane(layout_a[i], seed, i):
			return false
		if i > 0 and not is_equal_approx(float(layout_a[i]["x"]) - float(layout_a[i - 1]["x"]), spacing):
			push_error("[long-course] FAIL seed=%d pipe=%d spacing" % [seed, i])
			return false
	if grown_a["lanes"] != grown_b["lanes"]:
		push_error("[long-course] FAIL seed=%d harpoon lanes differ" % seed)
		return false
	var repeated := true
	for i in RR.PIPE_COUNT:
		if not _same_obstacle(layout_a[i], layout_a[RR.PIPE_COUNT + i]):
			repeated = false
			break
	if repeated:
		push_error("[long-course] FAIL seed=%d checkpoint=80 chunk repeated the opening" % seed)
		return false
	for mark in DAILY_MARKS:
		if layout_a.size() <= mark or not _pipe_sane(layout_a[mark], seed, mark):
			push_error("[long-course] FAIL seed=%d checkpoint=%d next pipe missing" % [seed, mark])
			return false
	for boundary in [RR.PIPE_COUNT, 120, 160, 1000]:
		if not _boundary_chunk(seed, boundary):
			return false
	print("[long-course] builder %s seed=%d pipes=%d" % [name, seed, layout_a.size()])
	return true


func _boundary_chunk(seed: int, size: int) -> bool:
	var grown := _grow(seed, size)
	var layout: Array = grown["layout"]
	if layout.size() != size:
		push_error("[long-course] FAIL seed=%d checkpoint=%d grew=%d" % [seed, size, layout.size()])
		return false
	var chunk: Dictionary = CourseBuilderScript.continuation(seed, size)
	var extra: Array = chunk.get("layout", [])
	if extra.size() != CourseBuilderScript.CHUNK_PIPES:
		push_error("[long-course] FAIL seed=%d checkpoint=%d chunk=%d" % [seed, size, extra.size()])
		return false
	var placed: Array = CourseBuilderScript.placed_specs(layout, extra)
	if placed.size() != CourseBuilderScript.CHUNK_PIPES:
		push_error("[long-course] FAIL seed=%d checkpoint=%d placed=%d" % [seed, size, placed.size()])
		return false
	var spacing := RR.PIPE_SPEED * RR.PIPE_INTERVAL
	var expect := float(layout[layout.size() - 1]["x"]) + spacing
	if not is_equal_approx(float(placed[0]["x"]), expect):
		push_error("[long-course] FAIL seed=%d checkpoint=%d chunk x" % [seed, size])
		return false
	return true


func _pipe_sane(spec: Dictionary, seed: int, index: int) -> bool:
	var gap_h := float(spec.get("gap_h", 0.0))
	var gap_y := float(spec.get("gap_y", 0.0))
	var min_h := RR.GAP - 18.0
	if gap_h + 0.01 < min_h or gap_y < RR.PLAY_TOP or gap_y > RR.PLAY_BOTTOM:
		push_error("[long-course] FAIL seed=%d pipe=%d gap y=%.1f h=%.1f" % [seed, index, gap_y, gap_h])
		return false
	if not RR.PIPE_IDS.has(str(spec.get("style", ""))):
		push_error("[long-course] FAIL seed=%d pipe=%d style" % [seed, index])
		return false
	return true


func _test_timeouts() -> bool:
	var ev := GameplayEvents.new()
	ev.set_corridor_clear(false)
	ev.note_pipes_passed(15)
	ev.tick(0.1)
	ev.tick(1.0)
	if ev.state != GameplayEvents.State.HARPOON_PENDING or not ev.fired_log.has("harpoon:15"):
		return false
	ev.set_corridor_clear(true)
	ev.tick(0.1)
	if ev.state != GameplayEvents.State.HARPOON_WARNING:
		return false
	var stalled := GameplayEvents.new()
	stalled.set_corridor_clear(false)
	stalled.note_pipes_passed(30)
	stalled.tick(0.1)
	if stalled.state != GameplayEvents.State.HARPOON_PENDING or stalled.dive_number != 0:
		return false
	stalled.tick(GameplayEvents.CORRIDOR_LIMIT)
	if stalled.state != GameplayEvents.State.DIVE_PENDING or stalled.dive_number != 1:
		return false
	stalled.tick(GameplayEvents.CORRIDOR_LIMIT)
	return (
		stalled.state == GameplayEvents.State.NORMAL
		and stalled.pipes_allowed()
		and stalled.dive_number == 0
		and stalled.fired_log.size() == 2
		and stalled.queued_count() == 0
	)


func _test_extend_without_events(seed: int) -> bool:
	var session := root.get_node("GameSession")
	session.match_mode = "daily"
	session.course_seed = seed
	var game = load("res://scenes/game/game.tscn").instantiate()
	game._build_layout()
	if game._events != null or game.layout.size() != RR.PIPE_COUNT:
		game.free()
		return false
	var opening: Array = _copy_specs(game.layout)
	game.spawn_index = 50
	game._ensure_course_ahead()
	if game.layout.size() != RR.PIPE_COUNT:
		game.free()
		return false
	game.spawn_index = RR.PIPE_COUNT - CourseBuilderScript.LOOKAHEAD
	game._ensure_course_ahead()
	var grew: bool = game.layout.size() == RR.PIPE_COUNT + CourseBuilderScript.CHUNK_PIPES
	var kept := true
	for i in RR.PIPE_COUNT:
		if not CourseBuilderScript.specs_equal(game.layout[i], opening[i]):
			kept = false
			break
	game.free()
	return grew and kept


func _test_harpoon_stall(game) -> bool:
	for spear in game._harpoons:
		spear.hide_idle()
	game._harpoon_beat = 3
	game._warn_t = 0.0
	game._recover_daily_harpoon(1.0)
	return game._harpoon_beat == 0 and game._pipes_until_harpoon == RR.HARPOON_EVERY


func _test_missing_dive(game) -> bool:
	if game._events == null or game._dive_field == null:
		push_error("[long-course] dive setup events=%s field=%s mode=%s" % [
			game._events != null,
			game._dive_field != null,
			root.get_node("GameSession").match_mode,
		])
		return false
	game._dive_field.free()
	game._dive_field = null
	game._events.debug_force_state(GameplayEvents.State.DIVE_TRANSITION_IN)
	game._synced_state = GameplayEvents.State.NORMAL
	game._sync_events()
	var ok: bool = (
		game._events.state == GameplayEvents.State.NORMAL
		and game._events.pipes_allowed()
		and game._harpoon_beat == 0
		and not game.player.motion_lock
	)
	if not ok:
		push_error("[long-course] dive recover state=%s allowed=%s beat=%s lock=%s" % [
			game._events.state,
			game._events.pipes_allowed(),
			game._harpoon_beat,
			game.player.motion_lock,
		])
	return ok


func _test_schedule(game) -> bool:
	var ev: GameplayEvents = game._events
	if ev == null or ev.state != GameplayEvents.State.NORMAL or not ev.pipes_allowed():
		return false
	var seen := {}
	for key in ev.fired_log:
		if seen.has(key):
			push_error("[long-course] duplicate stage %s" % key)
			return false
		seen[key] = true
	for i in 7:
		var harpoon := "harpoon:%d" % DeepDiveConfig.harpoon_pipe(i)
		var dive := "dive:%d" % DeepDiveConfig.dive_pipe(i)
		if not seen.has(harpoon) or not seen.has(dive):
			push_error("[long-course] missing %s / %s survived=%d" % [harpoon, dive, ev.dives_survived])
			return false
	if seen.has("harpoon:%d" % DeepDiveConfig.harpoon_pipe(7)):
		return false
	return ev.dives_survived == 7 and int(game.score) >= UNLIMITED_TARGET and game.pipes.size() > 0


func _boot(mode: String, seed: int):
	var session := root.get_node("GameSession")
	session.match_mode = mode
	session.course_seed = seed
	# Unlimited arms Deep Dive only when this is not a practice daily.
	# Turn practice back on before the fish can die, so nothing is submitted.
	session.practice_daily = mode != "unlimited"
	var game = load("res://scenes/game/game.tscn").instantiate()
	game.debug_skip_ready = true
	game.set_process(false)
	game.set_physics_process(false)
	root.add_child(game)
	game.course = Node2D.new()
	game.course.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	game.add_child(game.course)
	game.course_draw = Node2D.new()
	game.course_draw.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	game.add_child(game.course_draw)
	game.school = Node2D.new()
	game.add_child(game.school)
	game._build_layout()
	game._spawn_player()
	session.practice_daily = true
	game._setup_harpoons()
	game._prewarm_pipes()
	game.started = true
	game.finished = false
	game.paused = false
	game._in_lobby = false
	game.player.alive = true
	game.player.started = true
	var died := Callable(game, "_on_player_died")
	if game.player.died.is_connected(died):
		game.player.died.disconnect(died)
	return game


func _fast_forward(game, unlimited: bool, marks: Array[int], target: int, seed: int, label: String) -> Dictionary:
	var blank := {
		"ok": false,
		"score": 0,
		"spawn": 0,
		"layout": 0,
		"peak_pipes": 0,
		"peak_nodes": 0,
		"coins": 0,
		"step80": 0.0,
		"step1000": 0.0,
		"mem0": 0,
		"mem1": 0,
	}
	var events: GameplayEvents = game._events
	if unlimited and events == null:
		push_error("[long-course] unlimited events were not armed")
		return blank
	if not unlimited and events != null:
		push_error("[long-course] daily armed a deep dive seed=%d" % seed)
		return blank
	var seen := {}
	var spawn_at: Dictionary = {}
	var peak_obstacles := 0
	var peak_pipes := 0
	var peak_nodes := 0
	var idle := 0.0
	var last_score := 0
	var last_spawn := int(game.spawn_index)
	var steps := 0
	var ok := true
	var early_us := 0
	var early_n := 0
	var late_us := 0
	var late_n := 0
	var cap := 90000 if target > 250 else 40000
	var mem0 := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	while steps < cap:
		steps += 1
		var step_started := Time.get_ticks_usec()
		game.player.alive = true
		var diving := events != null and events.blocks_swim()
		if game._harpoon_beat >= 2 and not diving:
			game.player.position.y = RR.harpoon_lane_center(int(game._safe_lane))
		_clock_harpoons(game, DT)
		if events != null:
			events.set_corridor_clear(game._corridor_clear())
			events.tick(DT)
			if game._harpoon_live():
				game._tick_harpoons(DT)
			game._sync_events()
			diving = events.blocks_swim()
		if not diving:
			game.scroll += RR.PIPE_SPEED * DT
		if game._can_spawn_pipes():
			game._spawn_pipes()
		game._cull_pipes()
		if events == null and game._harpoon_beat != 0:
			game._tick_harpoons(DT)
			game._recover_daily_harpoon(DT)
		if diving:
			game._update_dive_actor(DT)
			if game._dive_field:
				peak_obstacles = maxi(peak_obstacles, game._dive_field.live_count())
		elif game._scoring_open():
			game._collect_coins()
			game._score_pipes()
		var score := int(game.score)
		var step_us := Time.get_ticks_usec() - step_started
		if score >= 70 and score < 90:
			early_us += step_us
			early_n += 1
		elif score >= 980 and score < target:
			late_us += step_us
			late_n += 1
		if int(game.spawn_index) < last_spawn:
			push_error("[long-course] FAIL seed=%d checkpoint=%d spawn cursor went backwards" % [seed, score])
			ok = false
			break
		last_spawn = int(game.spawn_index)
		peak_pipes = maxi(peak_pipes, game.pipes.size())
		var nodes: int = int(game.pipes.size()) + int(game._pipe_pool.size())
		peak_nodes = maxi(peak_nodes, nodes)
		if nodes > RR.PIPE_POOL_SIZE + 4:
			push_error("[long-course] FAIL seed=%d checkpoint=%d pipe nodes=%d" % [seed, score, nodes])
			ok = false
			break
		for mark in marks:
			if score < mark or seen.has(mark):
				continue
			var pipes_now: int = game.pipes.size()
			var pooled: int = game.pipes.size() + game._pipe_pool.size()
			seen[mark] = true
			spawn_at[mark] = int(game.spawn_index)
			print("[long-course] %s seed=%d checkpoint=%d spawn=%d layout=%d pipes=%d pool=%d beat=%d" % [
				label,
				seed,
				mark,
				game.spawn_index,
				game.layout.size(),
				pipes_now,
				pooled,
				game._harpoon_beat,
			])
			# spawn_index can equal the checkpoint while a harpoon pauses the
			# lead. The course still has to contain the next pipe, and a
			# pipe has to be on screen. The cursor must already be past 80
			# once the score leaves that checkpoint.
			if game.spawn_index < mark or game.layout.size() <= mark or pipes_now <= 0:
				push_error("[long-course] FAIL seed=%d checkpoint=%d spawn=%d layout=%d pipes=%d" % [
					seed, mark, game.spawn_index, game.layout.size(), pipes_now,
				])
				ok = false
			if game.layout.size() <= game.spawn_index:
				push_error("[long-course] FAIL seed=%d checkpoint=%d generator caught the cursor" % [seed, mark])
				ok = false
			if mark >= 79 and mark <= 81 and game.layout.size() <= RR.PIPE_COUNT:
				push_error("[long-course] FAIL seed=%d checkpoint=%d layout still capped at %d" % [seed, mark, RR.PIPE_COUNT])
				ok = false
			if mark >= 81 and game.spawn_index <= RR.PIPE_COUNT:
				push_error("[long-course] FAIL seed=%d checkpoint=%d spawn cursor stopped at %d" % [seed, mark, game.spawn_index])
				ok = false
			if not _live_pipes_ok(game, seed, mark):
				ok = false
		var busy: bool = diving or game._harpoon_beat != 0 or (events != null and not events.pipes_allowed())
		if busy or score != last_score:
			idle = 0.0
			last_score = score
		else:
			idle += DT
		if idle > 8.0:
			push_error("[long-course] FAIL seed=%d checkpoint=%d pipes stalled spawn=%d layout=%d beat=%d state=%s" % [
				seed, score, game.spawn_index, game.layout.size(), game._harpoon_beat, _state_name(events),
			])
			ok = false
			break
		var quiet: bool = score >= target and game._harpoon_beat == 0 and game.pipes.size() > 0 and game.spawn_index > score
		if events != null:
			quiet = quiet and events.state == GameplayEvents.State.NORMAL and events.queued_count() == 0 and events.pipes_allowed()
		if quiet:
			break
	for mark in marks:
		if not seen.has(mark):
			push_error("[long-course] FAIL seed=%d checkpoint=%d was never reached" % [seed, mark])
			ok = false
	if spawn_at.has(79) and spawn_at.has(81):
		var at_79 := int(spawn_at[79])
		var at_81 := int(spawn_at[81])
		if at_81 <= at_79 or at_81 <= RR.PIPE_COUNT:
			push_error("[long-course] FAIL seed=%d checkpoint=81 cursor %d did not pass %d (was %d at 79)" % [seed, at_81, RR.PIPE_COUNT, at_79])
			ok = false
	if unlimited and peak_obstacles <= 0:
		push_error("[long-course] deep dive spawned no obstacles")
		ok = false
	if game.layout.size() <= target or game.spawn_index <= target:
		push_error("[long-course] FAIL seed=%d checkpoint=%d layout=%d spawn=%d" % [seed, target, game.layout.size(), game.spawn_index])
		ok = false
	if steps >= cap:
		push_error("[long-course] FAIL seed=%d checkpoint=%d step cap score=%d" % [seed, int(game.score), int(game.score)])
		ok = false
	var mem1 := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	print("[long-course] %s done score=%d spawn=%d layout=%d pipes=%d steps=%d obstacles=%d state=%s" % [
		label,
		game.score,
		game.spawn_index,
		game.layout.size(),
		game.pipes.size(),
		steps,
		peak_obstacles,
		_state_name(events),
	])
	return {
		"ok": ok,
		"score": int(game.score),
		"spawn": int(game.spawn_index),
		"layout": int(game.layout.size()),
		"peak_pipes": peak_pipes,
		"peak_nodes": peak_nodes,
		"coins": game._coins.size(),
		"step80": float(early_us) / float(maxi(early_n, 1)),
		"step1000": float(late_us) / float(maxi(late_n, 1)),
		"mem0": mem0,
		"mem1": mem1,
	}


func _clock_harpoons(game, dt: float) -> void:
	if int(game._harpoon_beat) < 2:
		return
	for spear in game._harpoons:
		spear.tick(dt)
	if int(game._harpoon_beat) == 2:
		game._warn_t -= dt


func _matches_grown(game, seed: int) -> bool:
	var grown := _grow(seed, game.layout.size())
	var expected: Array = grown["layout"]
	if expected.size() != game.layout.size():
		push_error("[long-course] layout %d vs %d" % [game.layout.size(), expected.size()])
		return false
	for i in expected.size():
		if not _same_obstacle(game.layout[i], expected[i]):
			push_error("[long-course] obstacle mismatch at %d" % i)
			return false
	var lanes: PackedInt32Array = grown["lanes"]
	if game._harpoon_lanes != lanes:
		push_error("[long-course] harpoon lanes %d vs %d" % [game._harpoon_lanes.size(), lanes.size()])
		return false
	return true


func _grow(seed: int, target: int) -> Dictionary:
	var built: Dictionary = CourseBuilderScript.generate(seed)
	var layout: Array = []
	for spec in built["layout"]:
		layout.append((spec as Dictionary).duplicate())
	var lanes: PackedInt32Array = built["harpoon_lanes"]
	var guard := 0
	while layout.size() < target and guard < 40:
		guard += 1
		var chunk: Dictionary = CourseBuilderScript.continuation(seed, layout.size())
		var placed: Array = CourseBuilderScript.placed_specs(layout, chunk.get("layout", []))
		if placed.is_empty():
			break
		for spec in placed:
			layout.append(spec)
		var more: PackedInt32Array = chunk.get("harpoon_lanes", PackedInt32Array())
		var merged := PackedInt32Array()
		merged.append_array(lanes)
		merged.append_array(more)
		lanes = merged
	return {"layout": layout, "lanes": lanes}


func _copy_specs(layout: Array) -> Array:
	var copy: Array = []
	for spec in layout:
		copy.append((spec as Dictionary).duplicate())
	return copy


func _live_pipes_ok(game, seed: int, checkpoint: int) -> bool:
	var seen_x := {}
	for pair in game.pipes:
		if not is_instance_valid(pair):
			push_error("[long-course] FAIL seed=%d checkpoint=%d freed pipe" % [seed, checkpoint])
			return false
		var key := str(snappedf(pair.position.x, 0.1))
		if seen_x.has(key):
			push_error("[long-course] FAIL seed=%d checkpoint=%d duplicate pipe x=%s" % [seed, checkpoint, key])
			return false
		seen_x[key] = true
		if pair.gap_h <= 0.0 or pair.gap_y < RR.PLAY_TOP or pair.gap_y > RR.PLAY_BOTTOM:
			push_error("[long-course] FAIL seed=%d checkpoint=%d live gap y=%.1f h=%.1f" % [seed, checkpoint, pair.gap_y, pair.gap_h])
			return false
	for pair in game._pipe_pool:
		if not is_instance_valid(pair):
			push_error("[long-course] FAIL seed=%d checkpoint=%d freed pooled pipe" % [seed, checkpoint])
			return false
	return true


func _same_gaps(a: Array, b: Array) -> bool:
	if a.size() != b.size() or a.size() <= DAILY_TARGET:
		push_error("[long-course] FAIL repeat layout %d vs %d" % [a.size(), b.size()])
		return false
	for i in a.size():
		if not _same_obstacle(a[i], b[i]):
			push_error("[long-course] FAIL repeat pipe=%d" % i)
			return false
	return true


func _same_obstacles(a: Array, b: Array, minimum: int) -> bool:
	var n := mini(a.size(), b.size())
	if n <= minimum:
		return false
	for i in n:
		if not _same_obstacle(a[i], b[i]):
			return false
	return true


func _same_obstacle(a: Dictionary, b: Dictionary) -> bool:
	return (
		is_equal_approx(float(a.get("gap_y", 0.0)), float(b.get("gap_y", 0.0)))
		and is_equal_approx(float(a.get("gap_h", 0.0)), float(b.get("gap_h", 0.0)))
		and str(a.get("style", "")) == str(b.get("style", ""))
	)


func _state_name(events: GameplayEvents) -> String:
	if events == null:
		return "none"
	return str(events.state)
