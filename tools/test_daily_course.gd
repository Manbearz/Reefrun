extends SceneTree

const CourseBuilderScript := preload("res://scripts/course_builder.gd")
const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")
const DailyAttemptScript := preload("res://scripts/daily_attempt.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _check("three attempts, one course", _three_attempts()) and ok
	ok = _check("two players, one course", _two_players()) and ok
	ok = _check("restart keeps the course", _restart()) and ok
	ok = _check("next day is a different course", _next_day()) and ok
	ok = _check("60 and 120 use the same sequence", _frame_rates()) and ok
	ok = _check("harpoon timing follows the physics step", _harpoons()) and ok
	ok = _check("visual randomness leaves the course", _visual()) and ok
	ok = _check("a run crossing reset keeps its course", _cross_reset()) and ok
	ok = _check("unlimited still rolls its own seed", _unlimited()) and ok
	ok = _check("daily and unlimited share deep dives", _shared_dives()) and ok
	ok = _check("dive obstacles match at 60 and 120", _dive_frames()) and ok
	ok = _check("daily attempts and scoring stay put", _attempts_unchanged()) and ok
	print("[daily-course] ok=%s" % ok)
	quit(0 if ok else 1)


func _check(name: String, passed: bool) -> bool:
	if not passed:
		push_error("[daily-course] %s failed" % name)
	return passed


func _payload(day: String) -> Array:
	var made := DailyChallengeScript.make(day, true, DailyChallengeScript.unix_utc(2026, 10, 12, 16, 0))
	return [{
		"challenge_id": made["challenge_id"],
		"challenge_date": day,
		"course_seed": made["course_seed"],
		"course_version": RR.COURSE_VERSION,
		"physics_version": RR.PHYSICS_VERSION,
		"as_of": "2026-10-12T16:00:00+00:00",
	}]


func _events_for(day: String) -> Array:
	var parsed: Dictionary = DailyChallengeScript.from_server(_payload(day))
	return CourseBuilderScript.course_events(int(parsed.get("course_seed", 0)), 80)


func _three_attempts() -> bool:
	var first := _events_for("2026-10-12")
	if first.is_empty():
		return false
	for _attempt in 2:
		if not _same(first, _events_for("2026-10-12")):
			return false
	var store := DailyAttemptScript.empty_store()
	var challenge: Dictionary = DailyChallengeScript.from_server(_payload("2026-10-12"))
	var seed := int(challenge.get("course_seed", 0))
	for i in 3:
		var claimed: Dictionary = DailyAttemptScript.claim(store, "player-a", "try-%d" % i, challenge)
		if not bool(claimed.get("claimed", false)):
			return false
		if int(challenge.get("course_seed", 0)) != seed:
			return false
		DailyAttemptScript.start(store, "player-a", str(claimed.get("attempt_id", "")))
	return (
		_pipes_differ(first)
		and _has("harpoon:", first)
		and _has("coin:", first)
		and _has("dive:1", first)
		and _has("dive:1:obs:", first)
		and _has("dive:1:exit", first)
		and _has("dive:2", first)
	)


func _two_players() -> bool:
	var a: Dictionary = DailyChallengeScript.from_server(_payload("2026-10-12"))
	var b: Dictionary = DailyChallengeScript.from_server(_payload("2026-10-12"))
	return (
		int(a.get("course_seed", 0)) == int(b.get("course_seed", 1))
		and _same(CourseBuilderScript.course_events(int(a["course_seed"]), 80), CourseBuilderScript.course_events(int(b["course_seed"]), 80))
	)


func _restart() -> bool:
	var before := _events_for("2026-10-12")
	var again: Dictionary = DailyChallengeScript.from_server(_payload("2026-10-12"))
	var after := CourseBuilderScript.course_events(int(again.get("course_seed", 0)), 80)
	return _same(before, after)


func _next_day() -> bool:
	var monday := _events_for("2026-10-12")
	var tuesday := _events_for("2026-10-13")
	if _same(monday, tuesday):
		return false
	var changed := false
	for i in mini(monday.size(), tuesday.size()):
		if str(monday[i].get("id", "")) != str(tuesday[i].get("id", "")):
			continue
		if not is_equal_approx(float(monday[i].get("gap_y", 0.0)), float(tuesday[i].get("gap_y", 0.0))):
			changed = true
			break
		if int(monday[i].get("lane", -1)) != int(tuesday[i].get("lane", -2)) and str(monday[i].get("id", "")).begins_with("harpoon:"):
			changed = true
			break
	return changed


func _frame_rates() -> bool:
	var seed := int(DailyChallengeScript.make("2026-10-12")["course_seed"])
	var slow := CourseBuilderScript.spawn_ids(seed, 1.0 / 60.0, 25.0)
	var fast := CourseBuilderScript.spawn_ids(seed, 1.0 / 120.0, 25.0)
	if slow != fast or slow.is_empty():
		return false
	var course := CourseBuilderScript.course_events(seed, 40)
	var again := CourseBuilderScript.course_events(seed, 40)
	return (
		_same(course, again)
		and is_equal_approx(float(course[0].get("t", -1.0)), float(again[0].get("t", -2.0)))
		and _has("dive:1", course)
	)


func _harpoons() -> bool:
	var at_60 := CourseBuilderScript.warning_fire_time(1.0 / 60.0)
	var at_120 := CourseBuilderScript.warning_fire_time(1.0 / 120.0)
	var game := FileAccess.get_file_as_string("res://scenes/game/game.gd")
	var process := _between(game, "func _process", "func _spawn_pipes")
	var clock := _between(game, "func _tick_harpoons", "func _begin_harpoon_warn")
	var seed := int(DailyChallengeScript.make("2026-10-12")["course_seed"])
	var events := CourseBuilderScript.course_events(seed, 60)
	var lanes: PackedInt32Array = PackedInt32Array()
	for event in events:
		if str(event.get("id", "")).begins_with("harpoon:"):
			lanes.append(int(event.get("lane", -1)))
	return (
		is_equal_approx(at_60, RR.HARPOON_WARN)
		and is_equal_approx(at_120, RR.HARPOON_WARN)
		and process.find("_warn_t") < 0
		and clock.find("_warn_t = maxf(_warn_t - delta, 0.0)") >= 0
		and clock.find("tick_flight") >= 0
		and lanes.size() >= RR.HARPOON_SHOTS
		and _lanes_repeat(lanes)
	)


func _visual() -> bool:
	var seed := int(DailyChallengeScript.make("2026-10-12")["course_seed"])
	var before := CourseBuilderScript.course_events(seed, 50)
	var visual := RandomNumberGenerator.new()
	visual.randomize()
	for _i in 40:
		visual.randf()
		visual.randi()
		randi()
	var after := CourseBuilderScript.course_events(seed, 50)
	return _same(before, after)


func _cross_reset() -> bool:
	var monday: Dictionary = DailyChallengeScript.from_server(_payload("2026-10-12"))
	var tuesday: Dictionary = DailyChallengeScript.from_server(_payload("2026-10-13"))
	var held: Dictionary = DailyChallengeScript.hold(monday, tuesday)
	var started := CourseBuilderScript.course_events(int(monday.get("course_seed", 0)), 40)
	var kept := CourseBuilderScript.course_events(int(held.get("course_seed", 0)), 40)
	var nxt := CourseBuilderScript.course_events(int(tuesday.get("course_seed", 0)), 40)
	var store := DailyAttemptScript.empty_store()
	var book := DailyChallengeScript.empty_book()
	var claimed: Dictionary = DailyAttemptScript.claim(store, "player-a", "late", monday)
	var attempt_id := str(claimed.get("attempt_id", ""))
	DailyAttemptScript.start(store, "player-a", attempt_id)
	var when := DailyChallengeScript.unix_utc(2026, 10, 13, 5, 0)
	var done: Dictionary = DailyAttemptScript.finalize(store, book, "player-a", attempt_id, 30, "REEF", when)
	var old_day: Array = DailyChallengeScript.visible_board(book, "daily", DailyChallengeScript.unix_utc(2026, 10, 12, 22, 0))
	var new_day: Array = DailyChallengeScript.visible_board(book, "daily", when)
	var fresh: Dictionary = DailyAttemptScript.status_of(store, "player-a", tuesday)
	return (
		_same(started, kept)
		and not _same(started, nxt)
		and bool(done.get("accepted", false))
		and old_day.size() == 1
		and new_day.is_empty()
		and int(fresh.get("attempts_remaining", 0)) == 3
	)


func _unlimited() -> bool:
	var session := FileAccess.get_file_as_string("res://autoload/game_session.gd")
	var body := _between(session, "func start_match", "func begin_practice_daily")
	var daily_at := body.find("MODE_DAILY")
	var roll_at := body.find("var seed := randi()")
	var left := CourseBuilderScript.course_events(91001, 30)
	var right := CourseBuilderScript.course_events(91002, 30)
	return (
		daily_at >= 0
		and roll_at > daily_at
		and body.find("derive_seed") < 0
		and not _same(left, right)
	)


func _shared_dives() -> bool:
	if not GameplayEvents.applies_to("daily", false) or not GameplayEvents.applies_to("unlimited", false):
		return false
	if GameplayEvents.applies_to("daily", true) or GameplayEvents.applies_to("unlimited", true):
		return false
	for id in DiveAssets.IDS:
		if not ResourceLoader.exists("res://assets/deep_dive/%s.png" % id):
			push_error("[daily-course] missing dive art %s" % id)
			return false
	var session := root.get_node("GameSession")
	var saved_mode: String = session.match_mode
	var saved_seed: int = session.course_seed
	var saved_practice: bool = session.practice_daily
	var seed := int(DailyChallengeScript.make("2026-10-12")["course_seed"])
	var daily: Node = _boot_shared("daily", seed)
	var unlimited: Node = _boot_shared("unlimited", seed)
	var daily_events: GameplayEvents = daily.get("_events")
	var unlimited_events: GameplayEvents = unlimited.get("_events")
	var armed := (
		daily_events != null
		and unlimited_events != null
		and daily.get("_dive_field") != null
		and unlimited.get("_dive_field") != null
		and daily.get("_dive_overlay") != null
		and unlimited.get("_dive_overlay") != null
	)
	if armed:
		daily_events.note_pipes_passed(90)
		unlimited_events.note_pipes_passed(90)
		armed = daily_events.fired_log == unlimited_events.fired_log and _log_has(daily_events.fired_log, "dive:")
	var field: Node = daily.get("_dive_field")
	if armed and field != null:
		armed = bool(field.get("_prepared"))
	daily.free()
	unlimited.free()
	session.match_mode = saved_mode
	session.course_seed = saved_seed
	session.practice_daily = saved_practice
	var listed := CourseBuilderScript.course_events(seed, 90)
	return armed and _same(listed, CourseBuilderScript.course_events(seed, 90)) and _has("dive:2:obs:", listed)


func _boot_shared(mode: String, seed: int) -> Node:
	var session := root.get_node("GameSession")
	session.match_mode = mode
	session.course_seed = seed
	session.practice_daily = false
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	game.set("debug_skip_ready", true)
	game.set_process(false)
	game.set_physics_process(false)
	root.add_child(game)
	var course := Node2D.new()
	course.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	game.set("course", course)
	game.add_child(course)
	var draw := Node2D.new()
	draw.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	game.set("course_draw", draw)
	game.add_child(draw)
	var school := Node2D.new()
	game.set("school", school)
	game.add_child(school)
	game.call("_build_layout")
	game.call("_spawn_player")
	return game


func _dive_frames() -> bool:
	var seed := int(DailyChallengeScript.make("2026-10-12")["course_seed"])
	var slow := CourseBuilderScript.dive_spawn_ids(seed, 1, 1.0 / 60.0, 8.0)
	var fast := CourseBuilderScript.dive_spawn_ids(seed, 1, 1.0 / 120.0, 8.0)
	var later := CourseBuilderScript.dive_spawn_ids(seed, 2, 1.0 / 60.0, 8.0)
	var later_again := CourseBuilderScript.dive_spawn_ids(seed, 2, 1.0 / 120.0, 8.0)
	return slow == fast and later == later_again and not slow.is_empty() and slow != later


func _attempts_unchanged() -> bool:
	var attempt := FileAccess.get_file_as_string("res://scripts/daily_attempt.gd")
	var session := FileAccess.get_file_as_string("res://autoload/game_session.gd")
	return (
		attempt.find("const ATTEMPT_LIMIT := 3") >= 0
		and session.find("func finalize") < 0
		and session.find("should_finalize") >= 0
		and session.find("var seed := randi()") >= 0
	)


func _log_has(log: PackedStringArray, prefix: String) -> bool:
	for key in log:
		if key.begins_with(prefix):
			return true
	return false


func _pipes_differ(events: Array) -> bool:
	var gaps: Array[float] = []
	for event in events:
		if not str(event.get("id", "")).begins_with("pipe:"):
			continue
		gaps.append(float(event.get("gap_y", 0.0)))
		if gaps.size() == 8:
			break
	if gaps.size() < 4:
		return false
	for i in range(1, gaps.size()):
		if not is_equal_approx(gaps[0], gaps[i]):
			return true
	return false


func _has(prefix: String, events: Array) -> bool:
	for event in events:
		if str(event.get("id", "")).begins_with(prefix):
			return true
	return false


func _lanes_repeat(lanes: PackedInt32Array) -> bool:
	var first := int(lanes[0])
	for i in range(1, lanes.size()):
		if int(lanes[i]) != first:
			return true
	return false


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for i in a.size():
		var left: Dictionary = a[i]
		var right: Dictionary = b[i]
		if str(left.get("id", "")) != str(right.get("id", "")):
			return false
		for key in left.keys():
			var lv: Variant = left[key]
			var rv: Variant = right.get(key, null)
			if typeof(lv) == TYPE_FLOAT or typeof(lv) == TYPE_INT:
				if not is_equal_approx(float(lv), float(rv)):
					return false
			elif str(lv) != str(rv):
				return false
	return true


func _between(text: String, start: String, stop: String) -> String:
	var at := text.find(start)
	if at < 0:
		return ""
	var end := text.find(stop, at + start.length())
	if end < 0:
		return text.substr(at)
	return text.substr(at, end - at)
