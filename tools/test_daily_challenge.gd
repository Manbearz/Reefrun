extends SceneTree

const CourseBuilderScript := preload("res://scripts/course_builder.gd")
const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")
const FallbackScript := preload("res://scripts/fallback_ghost_factory.gd")
const GhostMatchScript := preload("res://scripts/ghost_match.gd")
const GhostRunScript := preload("res://scripts/ghost_run.gd")
const DT := 1.0 / 60.0
const PINNED_SEED := 750528330


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _test_shared_seed() and ok
	ok = _test_obstacles() and ok
	ok = _test_dates() and ok
	ok = _test_midnight_lock() and ok
	ok = _test_ghost_filter() and ok
	ok = _test_replay() and ok
	ok = _test_fallback_motion() and ok
	ok = _test_network_failure() and ok
	ok = _test_ghost_cache() and ok
	ok = _test_scores() and ok
	print("[daily] ok=%s" % ok)
	quit(0 if ok else 1)


func _test_shared_seed() -> bool:
	var a := DailyChallengeScript.make("2026-10-12", true, DailyChallengeScript.unix_utc(2026, 10, 12, 12))
	var b := DailyChallengeScript.make("2026-10-12", true, a["as_of_unix"])
	var payload := [{
		"challenge_id": a["challenge_id"],
		"challenge_date": "2026-10-12",
		"course_seed": a["course_seed"],
		"course_version": RR.COURSE_VERSION,
		"physics_version": RR.PHYSICS_VERSION,
		"as_of": "2026-10-12T12:00:00+00:00",
	}]
	var from_a := DailyChallengeScript.from_server(payload)
	var from_b := DailyChallengeScript.from_server(payload.duplicate(true))
	var ok: bool = (
		a["course_seed"] == b["course_seed"]
		and a["challenge_id"] == b["challenge_id"]
		and int(a["course_seed"]) == PINNED_SEED
		and from_a["course_seed"] == from_b["course_seed"]
		and from_a["challenge_id"] == a["challenge_id"]
		and bool(from_a["server_confirmed"])
	)
	print("[daily] shared_seed=%s seed=%s id=%s" % [ok, a["course_seed"], a["challenge_id"]])
	return ok


func _test_obstacles() -> bool:
	var challenge := DailyChallengeScript.make("2026-10-12")
	var seed := int(challenge["course_seed"])
	var first := CourseBuilderScript.generate(seed)
	var cosmetic := RandomNumberGenerator.new()
	cosmetic.randomize()
	cosmetic.randi()
	FallbackScript.make(seed, 3, first["layout"], str(challenge["challenge_id"]))
	var second := CourseBuilderScript.generate(seed)
	var ok := _same_course(first, second)
	var other := CourseBuilderScript.generate(int(DailyChallengeScript.make("2026-10-13")["course_seed"]))
	if _same_course(first, other):
		ok = false
	print("[daily] obstacles=%s pipes=%d harpoons=%d" % [ok, first["layout"].size(), first["harpoon_lanes"].size()])
	return ok


func _test_dates() -> bool:
	var today := DailyChallengeScript.make("2026-10-12")
	var tomorrow := DailyChallengeScript.make("2026-10-13")
	var ok: bool = (
		today["challenge_id"] != tomorrow["challenge_id"]
		and today["course_seed"] != tomorrow["course_seed"]
		and DailyChallengeScript.week_key("2026-10-12") == "2026-10-12"
		and DailyChallengeScript.week_key("2026-10-18") == "2026-10-12"
		and DailyChallengeScript.week_key("2026-10-19") == "2026-10-19"
		and str(DailyChallengeScript.period_keys_for_date("2026-10-13")["monthly"]) == "2026-10"
		and DailyChallengeScript.challenge_date_from_unix(DailyChallengeScript.unix_utc(2026, 10, 13, 3, 30)) == "2026-10-12"
		and DailyChallengeScript.challenge_date_from_unix(DailyChallengeScript.unix_utc(2026, 10, 13, 4, 0)) == "2026-10-13"
		and DailyChallengeScript.challenge_date_from_unix(DailyChallengeScript.unix_utc(2026, 1, 15, 4, 30)) == "2026-01-14"
		and DailyChallengeScript.challenge_date_from_unix(DailyChallengeScript.unix_utc(2026, 1, 15, 5, 0)) == "2026-01-15"
		and DailyChallengeScript.eastern_midnight_unix(2026, 10, 13) == DailyChallengeScript.unix_utc(2026, 10, 13, 4)
		and DailyChallengeScript.eastern_midnight_unix(2026, 1, 15) == DailyChallengeScript.unix_utc(2026, 1, 15, 5)
		and DailyChallengeScript.eastern_midnight_unix(2026, 3, 8) == DailyChallengeScript.unix_utc(2026, 3, 8, 5)
		and DailyChallengeScript.eastern_midnight_unix(2026, 3, 9) == DailyChallengeScript.unix_utc(2026, 3, 9, 4)
		and DailyChallengeScript.eastern_midnight_unix(2026, 11, 1) == DailyChallengeScript.unix_utc(2026, 11, 1, 4)
		and DailyChallengeScript.eastern_midnight_unix(2026, 11, 2) == DailyChallengeScript.unix_utc(2026, 11, 2, 5)
	)
	print("[daily] dates=%s week=%s" % [ok, DailyChallengeScript.week_key("2026-10-12")])
	return ok


func _test_midnight_lock() -> bool:
	var started := DailyChallengeScript.make("2026-10-12", true, DailyChallengeScript.unix_utc(2026, 10, 13, 3, 50))
	var session = get_root().get_node_or_null("GameSession")
	if session == null:
		push_error("GameSession autoload missing")
		print("[daily] midnight_lock=false")
		return false
	session.commit_match_challenge(started)
	var locked_id: String = session.current_challenge_id()
	var locked_seed: int = int(session.course_seed)
	var rolled := DailyChallengeScript.make("2026-10-13", true, DailyChallengeScript.unix_utc(2026, 10, 13, 4, 5))
	var preview: Dictionary = session.preview_next_challenge(rolled)
	var held: Dictionary = DailyChallengeScript.hold(session.current_challenge(), rolled)
	var fetched_at := int(started["as_of_unix"])
	var next_match: Dictionary = DailyChallengeScript.choose_for_new_match(
		started,
		fetched_at,
		fetched_at,
		fetched_at + 20 * 60
	)
	var ok: bool = (
		locked_id == str(started["challenge_id"])
		and session.current_challenge_id() == locked_id
		and int(session.course_seed) == locked_seed
		and str(preview["challenge_id"]) == str(rolled["challenge_id"])
		and str(held["challenge_id"]) == locked_id
		and int(held["course_seed"]) == locked_seed
		and not DailyChallengeScript.may_submit(next_match)
		and str(next_match["challenge_date"]) == "2026-10-13"
	)
	print("[daily] midnight_lock=%s kept=%s" % [ok, locked_id])
	return ok


func _test_ghost_filter() -> bool:
	var challenge := DailyChallengeScript.make("2026-10-12", true)
	var seed := int(challenge["course_seed"])
	var cid := str(challenge["challenge_id"])
	var flaps := PackedInt32Array([0, 16, 38, 70])
	var filler = GhostMatchScript.new()
	var mine = _real(challenge, "local_me", "mine-1", "ME", flaps)
	var good = _real(challenge, "other_a", "real-a", "Ada", flaps)
	var dup = _real(challenge, "other_c", "real-a", "Cara", flaps)
	var wrong = _real(challenge, "other_b", "real-b", "Bea", flaps)
	wrong.challenge_id = "daily:2026-10-13:cv1:pv1"
	var bad_physics = _real(challenge, "other_d", "real-d", "Dee", flaps)
	bad_physics.physics_version = 99
	var bad_seed = _real(challenge, "other_e", "real-e", "Eve", flaps)
	bad_seed.course_seed = seed + 1
	filler.bank.save_run(mine)
	filler.bank.save_run(good)
	filler.bank.save_run(dup)
	filler.bank.save_run(wrong)
	filler.bank.save_run(bad_physics)
	filler.bank.save_run(bad_seed)
	var compat_ok: bool = (
		DailyChallengeScript.ghost_compatible(good, challenge)
		and not DailyChallengeScript.ghost_compatible(wrong, challenge)
		and not DailyChallengeScript.ghost_compatible(bad_seed, challenge)
		and not DailyChallengeScript.ghost_compatible(bad_physics, challenge)
	)
	var layout: Array = CourseBuilderScript.generate(seed)["layout"]
	var picked: Array = filler.fill_competitors(seed, layout, "local_me", "", cid)
	var real_n := 0
	var kept_flaps := PackedInt32Array()
	var ids := {}
	var ok := picked.size() == RR.GHOST_COUNT
	for run in picked:
		if run.run_id != "" and ids.has(run.run_id):
			ok = false
		if run.run_id != "":
			ids[run.run_id] = true
		if run.player_id == "local_me" or run.challenge_id != cid or run.course_seed != seed:
			ok = false
		if run.physics_version != RR.PHYSICS_VERSION or run.course_version != RR.COURSE_VERSION:
			ok = false
		if run.source == GhostRunScript.SOURCE_REAL:
			real_n += 1
			kept_flaps = run.flap_ticks
		elif run.source == GhostRunScript.SOURCE_FALLBACK:
			if run.challenge_id != cid:
				ok = false
	ok = ok and real_n == 1 and kept_flaps == flaps and compat_ok
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ghost_runs/%d.cfg" % seed))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ghost_runs/%d.cfg" % (seed + 1)))
	print("[daily] ghost_filter=%s real=%d" % [ok, real_n])
	return ok


func _test_replay() -> bool:
	var flaps := PackedInt32Array([0, 18, 41, 72, 110, 150])
	var original := _replay(flaps, 180)
	var again := _replay(flaps.duplicate(), 180)
	var ok := original.size() == again.size() and original.size() > 2
	if ok:
		for i in original.size():
			if not is_equal_approx(original[i], again[i]):
				ok = false
				break
	var rose := false
	var fell := false
	for i in range(1, original.size()):
		if original[i] < original[i - 1] - 0.05:
			rose = true
		if original[i] > original[i - 1] + 0.05:
			fell = true
	ok = ok and rose and fell and flaps == PackedInt32Array([0, 18, 41, 72, 110, 150])
	print("[daily] replay=%s samples=%d" % [ok, original.size()])
	return ok


func _test_fallback_motion() -> bool:
	var challenge := DailyChallengeScript.make("2026-10-12")
	var seed := int(challenge["course_seed"])
	var layout: Array = CourseBuilderScript.generate(seed)["layout"]
	var ok := true
	var checked := 0
	for slot in RR.GHOST_COUNT:
		var run = FallbackScript.make(seed, slot, layout, str(challenge["challenge_id"]))
		if run.flap_ticks.is_empty() or run.course_seed != seed:
			ok = false
			continue
		var before: PackedInt32Array = run.flap_ticks.duplicate()
		var path := _replay(run.flap_ticks, maxi(run.death_tick, 1))
		if run.flap_ticks != before:
			ok = false
		var rose := 0
		var fell := 0
		for i in range(1, path.size()):
			if path[i] < path[i - 1] - 0.05:
				rose += 1
			elif path[i] > path[i - 1] + 0.05:
				fell += 1
		if rose < 2 or fell < 2 or _regular_climb(run.flap_ticks):
			ok = false
			if checked < 6:
				push_error("fallback drift slot=%d rose=%d fell=%d flaps=%d" % [slot, rose, fell, run.flap_ticks.size()])
		checked += 1
	print("[daily] fallback_motion=%s checked=%d" % [ok, checked])
	return ok


func _test_network_failure() -> bool:
	var unix := DailyChallengeScript.unix_utc(2026, 10, 12, 15)
	var started := Time.get_ticks_usec()
	var playable := DailyChallengeScript.challenge_from_fetch(false, null, unix)
	var elapsed := Time.get_ticks_usec() - started
	var ok: bool = (
		int(playable["course_seed"]) == PINNED_SEED
		and not DailyChallengeScript.may_submit(playable)
		and str(playable["challenge_date"]) == "2026-10-12"
		and elapsed < 50000
	)
	print("[daily] network_failure=%s elapsed_us=%d" % [ok, elapsed])
	return ok


func _test_ghost_cache() -> bool:
	var challenge := DailyChallengeScript.make("2026-10-12", true)
	var key := DailyChallengeScript.cache_key(challenge)
	var cache := {}
	var now := 1_700_000_000
	var downloads := 0
	if DailyChallengeScript.should_download_ghosts(cache, key, now):
		downloads += 1
		DailyChallengeScript.remember_ghosts(cache, key, [{"id": "run-a"}], now)
	if DailyChallengeScript.should_download_ghosts(cache, key, now + 30):
		downloads += 1
	var rows: Array = DailyChallengeScript.cached_rows(cache, key, now + 30)
	var expired := DailyChallengeScript.should_download_ghosts(cache, key, now + DailyChallengeScript.GHOST_CACHE_TTL_SEC + 5)
	var ok := downloads == 1 and rows.size() == 1 and str(rows[0]["id"]) == "run-a" and expired
	print("[daily] ghost_cache=%s downloads=%d" % [ok, downloads])
	return ok


func _test_scores() -> bool:
	var book := DailyChallengeScript.empty_book()
	var day := DailyChallengeScript.make("2026-10-12", true)
	var noon := DailyChallengeScript.unix_utc(2026, 10, 12, 12)
	var ok := DailyChallengeScript.submit_score(book, "p1", "ADA", 10, day, noon)
	ok = DailyChallengeScript.submit_score(book, "p1", "ADA", 4, day, noon + 10) and ok
	var after_low: Array = DailyChallengeScript.visible_board(book, "daily", noon)
	ok = ok and after_low.size() == 1 and int(after_low[0]["score"]) == 10
	ok = DailyChallengeScript.submit_score(book, "p1", "ADA", 12, day, noon + 20) and ok
	ok = DailyChallengeScript.submit_score(book, "p2", "BEA", 8, day, noon + 30) and ok
	var daily: Array = DailyChallengeScript.visible_board(book, "daily", noon)
	ok = ok and daily.size() == 2 and int(daily[0]["score"]) == 12 and str(daily[0]["name"]) == "ADA"
	ok = ok and int(daily[1]["score"]) == 8
	ok = ok and DailyChallengeScript.row_count(book, "p1", "daily") == 1
	ok = ok and DailyChallengeScript.row_count(book, "p1", "weekly") == 0
	ok = ok and DailyChallengeScript.row_count(book, "p1", "monthly") == 0
	var next_noon := DailyChallengeScript.unix_utc(2026, 10, 13, 12)
	var hidden: Array = DailyChallengeScript.visible_board(book, "daily", next_noon)
	ok = ok and hidden.is_empty()
	ok = ok and DailyChallengeScript.row_count(book, "p1", "daily") == 1
	var tomorrow := DailyChallengeScript.make("2026-10-13", true)
	ok = DailyChallengeScript.submit_score(book, "p1", "ADA", 3, tomorrow, next_noon) and ok
	var daily_next: Array = DailyChallengeScript.visible_board(book, "daily", next_noon)
	var weekly: Array = DailyChallengeScript.visible_board(book, "weekly", next_noon)
	var monthly: Array = DailyChallengeScript.visible_board(book, "monthly", next_noon)
	ok = ok and daily_next.size() == 1 and int(daily_next[0]["score"]) == 3
	ok = ok and weekly.is_empty() and monthly.is_empty()
	ok = DailyChallengeScript.submit_unlimited(book, "p1", "ADA", 12, noon) and ok
	ok = DailyChallengeScript.submit_unlimited(book, "p1", "LOWNAME", 4, noon + 10) and ok
	weekly = DailyChallengeScript.visible_board(book, "weekly", next_noon)
	monthly = DailyChallengeScript.visible_board(book, "monthly", next_noon)
	ok = ok and weekly.size() == 1 and int(weekly[0]["score"]) == 12 and str(weekly[0]["name"]) == "ADA"
	ok = ok and monthly.size() == 1 and int(monthly[0]["score"]) == 12
	var offline := DailyChallengeScript.make("2026-10-12", false)
	ok = ok and not DailyChallengeScript.submit_score(book, "p1", "ADA", 99, offline, noon)
	ok = ok and int(DailyChallengeScript.visible_board(book, "daily", noon)[0]["score"]) == 12
	var grace := DailyChallengeScript.unix_utc(2026, 10, 13, 4, 10)
	ok = DailyChallengeScript.submit_score(book, "p3", "CY", 7, day, grace) and ok
	var during_grace: Array = DailyChallengeScript.visible_board(book, "daily", grace)
	var week_grace: Array = DailyChallengeScript.visible_board(book, "weekly", grace)
	ok = ok and during_grace.size() == 1 and int(during_grace[0]["score"]) == 3
	ok = ok and week_grace.size() == 1 and int(week_grace[0]["score"]) == 12 and str(week_grace[0]["name"]) == "ADA"
	var late := DailyChallengeScript.unix_utc(2026, 10, 13, 4, 21)
	ok = ok and not DailyChallengeScript.submit_score(book, "p3", "CY", 100, day, late)
	var tied := DailyChallengeScript.unix_utc(2026, 10, 12, 8)
	var tie_book := DailyChallengeScript.empty_book()
	DailyChallengeScript.submit_score(tie_book, "early", "ANN", 5, day, tied)
	DailyChallengeScript.submit_score(tie_book, "late", "BOB", 5, day, tied + 5)
	var ties: Array = DailyChallengeScript.visible_board(tie_book, "daily", tied)
	ok = ok and ties.size() == 2 and str(ties[0]["name"]) == "ANN" and str(ties[1]["name"]) == "BOB"
	print("[daily] scores=%s daily=%s weekly=%s monthly=%s" % [ok, daily_next, weekly, monthly])
	return ok


func _same_course(a: Dictionary, b: Dictionary) -> bool:
	var la: Array = a["layout"]
	var lb: Array = b["layout"]
	if la.size() != lb.size() or a["harpoon_lanes"] != b["harpoon_lanes"]:
		return false
	for i in la.size():
		if not CourseBuilderScript.specs_equal(la[i], lb[i]):
			return false
	return true


func _real(challenge: Dictionary, player_id: String, run_id: String, p_name: String, flaps: PackedInt32Array):
	var run = GhostRunScript.new()
	run.challenge_id = str(challenge["challenge_id"])
	run.course_seed = int(challenge["course_seed"])
	run.course_version = RR.COURSE_VERSION
	run.physics_version = RR.PHYSICS_VERSION
	run.display_name = p_name
	run.player_name = p_name
	run.fish_id = "fish_blue"
	run.flap_ticks = flaps.duplicate()
	run.death_tick = 90
	run.score = 2
	run.source = GhostRunScript.SOURCE_REAL
	run.player_id = player_id
	run.run_id = run_id
	return run


func _replay(flaps: PackedInt32Array, frames: int) -> PackedFloat32Array:
	var y := RR.VIEW_H * 0.42
	var v := 0.0
	var fi := 0
	var match_tick := 0
	if fi < flaps.size() and int(flaps[fi]) == match_tick:
		v = -RR.FLAP
		fi += 1
	var out := PackedFloat32Array()
	out.append(y)
	for _frame in frames:
		match_tick += 1
		while fi < flaps.size() and int(flaps[fi]) < match_tick:
			fi += 1
		if fi < flaps.size() and int(flaps[fi]) == match_tick:
			v = -RR.FLAP
			fi += 1
		v = minf(v + RR.GRAVITY * DT, RR.TERMINAL)
		y += v * DT
		out.append(y)
	return out


func _regular_climb(flaps: PackedInt32Array) -> bool:
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
