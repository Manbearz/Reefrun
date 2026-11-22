extends SceneTree

const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")
const DailyAttemptScript := preload("res://scripts/daily_attempt.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _check("three_attempts_then_fourth_denied", _three()) and ok
	ok = _check("start_consumes_one_death_does_not", _death()) and ok
	ok = _check("best_score_kept", _best()) and ok
	ok = _check("third_finalizes_after_none_remain", _third()) and ok
	ok = _check("duplicate_request_one_row", _duplicate()) and ok
	ok = _check("two_devices_cannot_pass_three", _devices()) and ok
	ok = _check("restart_does_not_restore", _restart()) and ok
	ok = _check("next_day_restores_three", _reset()) and ok
	ok = _check("crossing_midnight_keeps_the_started_day", _midnight()) and ok
	ok = _check("fish_states", _fish()) and ok
	ok = _check("startup_fish_and_button_agree", _startup_agreement()) and ok
	ok = _check("status_check_blocks_the_button", _status_race()) and ok
	ok = _check("fish_textures_are_separate", _fish_textures()) and ok
	ok = _check("editor_visual_override_is_display_only", _visual_override()) and ok
	ok = _check("editor_daily_test_is_local", _editor_daily_test()) and ok
	ok = _check("unknown_status_is_not_three_lives", _unknown()) and ok
	ok = _check("production_status_shape", _production_status_shape()) and ok
	ok = _check("restart_cannot_restore_a_life", _restart_floor()) and ok
	ok = _check("locked_button_replaces_open_art", _button_art()) and ok
	ok = _check("locked_only_at_zero", _locked()) and ok
	ok = _check("active_run_is_not_stopped", _active()) and ok
	ok = _check("leaderboard_one_row", _board()) and ok
	ok = _check("unlimited_weekly_monthly", _other_modes()) and ok
	ok = _check("sql_contract", _sql()) and ok
	ok = _check("fish_fit", _fit()) and ok
	print("[daily-three] ok=%s" % ok)
	quit(0 if ok else 1)


func _check(name: String, passed: bool) -> bool:
	if not passed:
		push_error("[daily-three] %s failed" % name)
	return passed


func _today() -> Dictionary:
	return DailyChallengeScript.make("2026-10-20", true, DailyChallengeScript.unix_utc(2026, 10, 20, 18, 0))


func _tomorrow() -> Dictionary:
	return DailyChallengeScript.make("2026-10-21", true, DailyChallengeScript.unix_utc(2026, 10, 21, 16, 0))


func _play(store: Dictionary, book: Dictionary, key: String, score: int, challenge: Dictionary) -> Dictionary:
	var claimed: Dictionary = DailyAttemptScript.claim(store, "player-a", key, challenge)
	if not bool(claimed.get("claimed", false)):
		return claimed
	var attempt_id := str(claimed.get("attempt_id", ""))
	var started: Dictionary = DailyAttemptScript.start(store, "player-a", attempt_id)
	if not bool(started.get("started", false)):
		return started
	return DailyAttemptScript.finalize(store, book, "player-a", attempt_id, score, "REEF", 1)


func _three() -> bool:
	var store := DailyAttemptScript.empty_store()
	var book := DailyChallengeScript.empty_book()
	var challenge := _today()
	for i in 3:
		var done: Dictionary = _play(store, book, "key-%d" % i, 10 + i, challenge)
		if not bool(done.get("accepted", false)):
			return false
	var status: Dictionary = DailyAttemptScript.status_of(store, "player-a", challenge)
	var fourth: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-4", challenge)
	return (
		int(status.get("attempts_used", 0)) == 3
		and int(status.get("attempts_remaining", -1)) == 0
		and bool(fourth.get("already_used", false))
		and not bool(fourth.get("claimed", true))
	)


func _death() -> bool:
	var store := DailyAttemptScript.empty_store()
	var book := DailyChallengeScript.empty_book()
	var done: Dictionary = _play(store, book, "key-a", 42, _today())
	var status: Dictionary = DailyAttemptScript.status_of(store, "player-a", _today())
	return bool(done.get("accepted", false)) and int(status.get("attempts_used", 0)) == 1 and int(status.get("attempts_remaining", 0)) == 2


func _best() -> bool:
	var store := DailyAttemptScript.empty_store()
	var book := DailyChallengeScript.empty_book()
	var challenge := _today()
	if not bool(_play(store, book, "a", 42, challenge).get("accepted", false)):
		return false
	if not bool(_play(store, book, "b", 87, challenge).get("accepted", false)):
		return false
	var lower: Dictionary = _play(store, book, "c", 65, challenge)
	var rows: Array = DailyChallengeScript.visible_board(book, "daily", DailyChallengeScript.unix_utc(2026, 10, 20, 18, 0))
	return (
		bool(lower.get("accepted", false))
		and int(lower.get("best_score", 0)) == 87
		and rows.size() == 1
		and int(rows[0].get("score", 0)) == 87
	)


func _third() -> bool:
	var store := DailyAttemptScript.empty_store()
	var book := DailyChallengeScript.empty_book()
	var challenge := _today()
	var third_id := ""
	for i in 3:
		var claimed: Dictionary = DailyAttemptScript.claim(store, "player-a", "run-%d" % i, challenge)
		third_id = str(claimed.get("attempt_id", ""))
		if not bool(DailyAttemptScript.start(store, "player-a", third_id).get("started", false)):
			return false
	var status: Dictionary = DailyAttemptScript.status_of(store, "player-a", challenge)
	var done: Dictionary = DailyAttemptScript.finalize(store, book, "player-a", third_id, 65, "REEF", 1)
	var after: Dictionary = DailyAttemptScript.status_of(store, "player-a", challenge)
	return (
		int(status.get("attempts_remaining", -1)) == 0
		and bool(done.get("accepted", false))
		and int(after.get("attempts_used", 0)) == 3
		and int(done.get("best_score", 0)) == 65
	)


func _duplicate() -> bool:
	var store := DailyAttemptScript.empty_store()
	var challenge := _today()
	var first: Dictionary = DailyAttemptScript.claim(store, "player-a", "same", challenge)
	var retry: Dictionary = DailyAttemptScript.claim(store, "player-a", "same", challenge)
	var attempt_id := str(first.get("attempt_id", ""))
	var started: Dictionary = DailyAttemptScript.start(store, "player-a", attempt_id)
	var again: Dictionary = DailyAttemptScript.start(store, "player-a", attempt_id)
	var book := DailyChallengeScript.empty_book()
	DailyAttemptScript.finalize(store, book, "player-a", attempt_id, 20, "REEF", 1)
	var replay: Dictionary = DailyAttemptScript.finalize(store, book, "player-a", attempt_id, 99, "REEF", 1)
	var rows: Array = DailyChallengeScript.visible_board(book, "daily", DailyChallengeScript.unix_utc(2026, 10, 20, 18, 0))
	return (
		str(retry.get("attempt_id", "")) == attempt_id
		and bool(started.get("started", false))
		and bool(again.get("already_started", false))
		and not bool(again.get("started", true))
		and bool(replay.get("duplicate", false))
		and rows.size() == 1
		and int(rows[0].get("score", 0)) == 20
		and int(DailyAttemptScript.status_of(store, "player-a", challenge).get("attempts_used", 0)) == 1
	)


func _devices() -> bool:
	var store := DailyAttemptScript.empty_store()
	var challenge := _today()
	var phone: Dictionary = DailyAttemptScript.claim(store, "player-a", "phone", challenge)
	var tablet: Dictionary = DailyAttemptScript.claim(store, "player-a", "tablet", challenge)
	if str(phone.get("attempt_id", "")) != str(tablet.get("attempt_id", "")):
		return false
	for i in 3:
		var claimed: Dictionary = DailyAttemptScript.claim(store, "player-a", "device-%d" % i, challenge)
		if not bool(DailyAttemptScript.start(store, "player-a", str(claimed.get("attempt_id", ""))).get("started", false)):
			return false
	var extra: Dictionary = DailyAttemptScript.claim(store, "player-a", "device-extra", challenge)
	return bool(extra.get("already_used", false)) and int(DailyAttemptScript.status_of(store, "player-a", challenge).get("attempts_used", 0)) == 3


func _restart() -> bool:
	var store := DailyAttemptScript.empty_store()
	var book := DailyChallengeScript.empty_book()
	_play(store, book, "before-restart", 15, _today())
	var fresh: Dictionary = DailyAttemptScript.claim(store, "player-a", "after-restart", _today())
	return (
		bool(fresh.get("claimed", false))
		and int(fresh.get("attempts_used", -1)) == 1
		and int(fresh.get("attempts_remaining", -1)) == 2
	)


func _reset() -> bool:
	var store := DailyAttemptScript.empty_store()
	var book := DailyChallengeScript.empty_book()
	for i in 3:
		if not bool(_play(store, book, "old-%d" % i, 5, _today()).get("accepted", false)):
			return false
	var locked: Dictionary = DailyAttemptScript.status_of(store, "player-a", _today())
	var fresh: Dictionary = DailyAttemptScript.claim(store, "player-a", "new-day", _tomorrow())
	var opened: Dictionary = DailyAttemptScript.status_of(store, "player-a", _tomorrow())
	return (
		int(locked.get("attempts_remaining", -1)) == 0
		and bool(fresh.get("claimed", false))
		and int(opened.get("attempts_remaining", 0)) == 3
		and int(opened.get("attempts_used", -1)) == 0
	)


func _midnight() -> bool:
	var store := DailyAttemptScript.empty_store()
	var book := DailyChallengeScript.empty_book()
	var claimed: Dictionary = DailyAttemptScript.claim(store, "player-a", "late", _today())
	var attempt_id := str(claimed.get("attempt_id", ""))
	DailyAttemptScript.start(store, "player-a", attempt_id)
	var when := DailyChallengeScript.unix_utc(2026, 10, 21, 5, 0)
	var done: Dictionary = DailyAttemptScript.finalize(store, book, "player-a", attempt_id, 30, "REEF", when)
	var started_day: Array = DailyChallengeScript.visible_board(book, "daily", DailyChallengeScript.unix_utc(2026, 10, 20, 22, 0))
	var next_day: Array = DailyChallengeScript.visible_board(book, "daily", when)
	var next: Dictionary = DailyAttemptScript.status_of(store, "player-a", _tomorrow())
	return (
		bool(done.get("accepted", false))
		and started_day.size() == 1
		and int(started_day[0].get("score", 0)) == 30
		and next_day.is_empty()
		and int(next.get("attempts_remaining", 0)) == 3
	)


func _startup_agreement() -> bool:
	var bad := DailyAttemptScript.count_verdict({
		"ok": true,
		"attempts_counted": true,
		"attempts_used": 1,
		"attempts_remaining": 3,
	})
	var both := DailyAttemptScript.count_verdict({
		"ok": true,
		"attempts_counted": true,
		"attempts_used": 1,
		"attempts_remaining": 2,
	})
	var only_remaining := DailyAttemptScript.count_verdict({
		"ok": true,
		"attempts_counted": true,
		"attempts_remaining": 1,
	})
	var legacy := DailyAttemptScript.count_verdict(DailyAttemptScript.parse_status({
		"ok": true,
		"status": 200,
		"data": [{"attempted": false, "challenge_id": "daily:2026-11-21:cv1:pv1", "course_seed": 1}],
	}))
	if (
		bool(bad.get("consistent", true))
		or not bool(both.get("consistent", false))
		or int(both.get("remaining", -1)) != 2
		or str(both.get("source", "")) != "supabase"
		or int(only_remaining.get("used", -1)) != 2
		or str(legacy.get("source", "")) != "legacy_unattempted"
		or int(legacy.get("remaining", -1)) != 3
	):
		return false
	var menu_script: GDScript = load("res://scenes/menu/main_menu.gd") as GDScript
	if menu_script == null:
		return false
	var menu = menu_script.new()
	var host := Control.new()
	var button := Button.new()
	menu._modes = host
	menu._daily_button = button
	menu._daily_lives = 3
	menu._daily_source = "supabase"
	menu._build_daily_fish()
	if menu._daily_lives != 3:
		host.free()
		button.free()
		menu.free()
		return false
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.45, 0.95, 1.0))
	menu._remember_fish_color(ImageTexture.create_from_image(img))
	var color_tex: Texture2D = menu._daily_fish_color
	var agreed := true
	for remaining in [3, 2, 1, 0]:
		menu._apply_attempt_fish(remaining)
		var enabled: bool = not button.disabled and not menu._mode_shows_locked()
		var fish_ok: bool = _fish_icons_match(menu, [remaining > 0, remaining > 1, remaining > 2], color_tex)
		if enabled != (remaining > 0) or menu._daily_locked != (remaining == 0) or not fish_ok:
			agreed = false
	menu._apply_attempt_fish(2)
	menu._daily_paint_reason = "layout"
	menu._repaint_attempt_fish()
	if button.disabled or menu._daily_lives != 2 or not _fish_icons_match(menu, [true, true, false], color_tex):
		agreed = false
	menu._apply_attempt_fish(2)
	menu._clear_daily_lock()
	if button.disabled or menu._daily_locked or not _fish_icons_match(menu, [true, true, false], color_tex):
		agreed = false
	menu._apply_attempt_fish(0)
	menu._clear_daily_lock()
	if not button.disabled or not menu._daily_locked or not _fish_icons_match(menu, [false, false, false], color_tex):
		agreed = false
	var session = get_root().get_node("GameSession")
	var was_active: bool = session.editor_daily_test_active
	session.set_editor_daily_test(-1)
	var normal: bool = not session.editor_daily_test_enabled() and menu._daily_visual_override < 0
	session.editor_daily_test_active = was_active
	host.free()
	button.free()
	menu.free()
	return agreed and normal


func _fish_hidden(menu) -> bool:
	if menu._daily_fish.size() != 3:
		return false
	for icon in menu._daily_fish:
		if icon.visible:
			return false
	return true


func _status_race() -> bool:
	# The menu stays out of the tree, so _ready cannot start a live status
	# request. Nothing here claims, starts, or finalizes an attempt.
	var session = get_root().get_node("GameSession")
	var was_active: bool = session.editor_daily_test_active
	var was_lives: int = session.editor_daily_test_lives
	session.set_editor_daily_test(-1)
	var menu_script: GDScript = load("res://scenes/menu/main_menu.gd") as GDScript
	if menu_script == null:
		session.editor_daily_test_active = was_active
		session.editor_daily_test_lives = was_lives
		return false
	var menu = menu_script.new()
	var host := Control.new()
	var button := Button.new()
	var card := TextureRect.new()
	menu._modes = host
	menu._daily_button = button
	menu._mode_card = card
	menu._build_daily_fish()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.45, 0.95, 1.0))
	menu._remember_fish_color(ImageTexture.create_from_image(img))
	var color_tex: Texture2D = menu._daily_fish_color
	if menu._editor_daily_test_active() or color_tex == null:
		host.free()
		button.free()
		card.free()
		menu.free()
		session.editor_daily_test_active = was_active
		session.editor_daily_test_lives = was_lives
		return false
	var passed := true
	button.disabled = false
	menu._daily_checking = true
	menu._status_busy = false
	menu._mode_busy = false
	menu._mode_token = 0
	menu._daily_lives = 3
	menu._apply_attempt_fish(3)
	passed = passed and button.disabled and menu._mode_shows_locked() and _fish_hidden(menu) and menu._daily_checking
	menu._choose_daily()
	passed = (
		passed
		and not menu._mode_busy
		and menu._mode_token == 0
		and button.disabled
		and menu._daily_checking
		and menu._daily_lives == 3
	)
	menu._status_gen = 4
	menu._finish_daily_status({"ok": false, "status": 500, "error": "stale"}, 3)
	passed = passed and menu._daily_checking and menu._daily_lives == 3 and menu._status_gen == 4 and button.disabled
	menu._status_busy = true
	menu._status_again = false
	menu._refresh_daily_status(false)
	passed = passed and not menu._status_again and menu._status_busy and menu._status_gen == 4
	menu._refresh_daily_status(true)
	passed = passed and menu._status_again and menu._status_gen == 4
	menu._status_again = false
	menu._daily_needs_session = false
	menu._launching = false
	menu._on_daily_status_refresh()
	passed = passed and menu._status_again and menu._status_gen == 4
	menu._status_again = false
	menu._on_identity_ready()
	passed = passed and not menu._status_again and menu._status_busy and menu._status_gen == 4
	menu._mode_card = null
	menu._open_modes()
	passed = passed and not menu._status_again and menu._status_busy and button.disabled and menu._daily_checking
	menu._fail_daily_status({"ok": false, "status": 404, "error": "missing"})
	passed = (
		passed
		and not menu._daily_checking
		and menu._daily_lives < 0
		and button.disabled
		and menu._mode_shows_locked()
		and menu._daily_net_retry_msec == 0
		and not menu._daily_status_settled()
	)
	menu._fail_daily_status({"ok": false, "status": 0, "error": "offline"})
	passed = (
		passed
		and not menu._daily_checking
		and not menu._status_busy
		and menu._daily_lives < 0
		and button.disabled
		and _fish_hidden(menu)
		and menu._daily_net_retry_msec > Time.get_ticks_msec()
	)
	menu._commit_daily_lives(3)
	passed = passed and _race_settled(menu, 3, false, [true, true, true], color_tex)
	menu._commit_daily_lives(2)
	passed = passed and _race_settled(menu, 2, false, [true, true, false], color_tex)
	menu._commit_daily_lives(1)
	passed = passed and _race_settled(menu, 1, false, [true, false, false], color_tex)
	menu._commit_daily_lives(0)
	passed = passed and _race_settled(menu, 0, true, [false, false, false], color_tex)
	menu._commit_daily_lives(3)
	menu._last_daily_status = {"ok": true}
	menu._status_gen = 9
	menu._status_busy = false
	menu._daily_checking = false
	menu._daily_net_retry_msec = 0
	menu._daily_needs_session = false
	menu._on_identity_ready()
	menu._open_modes()
	passed = (
		passed
		and menu._status_gen == 9
		and not menu._status_busy
		and not menu._daily_checking
		and menu._daily_lives == 3
		and not button.disabled
		and _fish_icons_match(menu, [true, true, true], color_tex)
	)
	host.free()
	button.free()
	card.free()
	menu.free()
	session.editor_daily_test_active = was_active
	session.editor_daily_test_lives = was_lives
	return passed


func _race_fish_visible(menu) -> bool:
	for icon in menu._daily_fish:
		if not icon.visible:
			return false
	return menu._daily_fish.size() == 3


func _race_settled(menu, lives: int, locked: bool, lit: Array, color_tex: Texture2D) -> bool:
	return (
		not menu._daily_checking
		and not menu._status_busy
		and menu._daily_lives == lives
		and menu._daily_net_retry_msec == 0
		and menu._daily_button.disabled == locked
		and menu._mode_shows_locked() == locked
		and _fish_icons_match(menu, lit, color_tex)
		and _race_fish_visible(menu)
	)


func _fish() -> bool:
	if not DailyAttemptScript.fish_lit(0, 3) or not DailyAttemptScript.fish_lit(2, 3):
		return false
	if not DailyAttemptScript.fish_lit(1, 2) or DailyAttemptScript.fish_lit(2, 2):
		return false
	if not DailyAttemptScript.fish_lit(0, 1) or DailyAttemptScript.fish_lit(1, 1):
		return false
	if DailyAttemptScript.fish_lit(0, 0):
		return false
	var menu_script: GDScript = load("res://scenes/menu/main_menu.gd") as GDScript
	if menu_script == null:
		return false
	var menu = menu_script.new()
	var shader := str(menu.DAILY_FISH_SHADER)
	menu.free()
	return shader.find("c.a") >= 0 and shader.find("COLOR = vec4(vec3(g), c.a)") >= 0


func _fish_textures() -> bool:
	var menu_script: GDScript = load("res://scenes/menu/main_menu.gd") as GDScript
	if menu_script == null:
		return false
	var menu = menu_script.new()
	var host := Control.new()
	menu._modes = host
	menu._build_daily_fish()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.45, 0.92, 1.0))
	var color_tex := ImageTexture.create_from_image(img)
	menu._remember_fish_color(color_tex)
	menu._apply_attempt_fish(3)
	if not _fish_icons_match(menu, [true, true, true], color_tex):
		host.free()
		return false
	menu._apply_attempt_fish(2)
	if not _fish_icons_match(menu, [true, true, false], color_tex):
		host.free()
		return false
	menu._apply_attempt_fish(1)
	if not _fish_icons_match(menu, [true, false, false], color_tex):
		host.free()
		return false
	menu._apply_attempt_fish(0)
	if not _fish_icons_match(menu, [false, false, false], color_tex):
		host.free()
		return false
	var separate: bool = menu._daily_fish_gray_tex != color_tex and menu._texture_has_color(color_tex) and not menu._texture_has_color(menu._daily_fish_gray_tex)
	host.free()
	return separate


func _fish_icons_match(menu, lit: Array, color_tex: Texture2D) -> bool:
	if menu._daily_fish.size() != 3:
		return false
	for i in 3:
		var icon: TextureRect = menu._daily_fish[i]
		if icon.material != null or icon.modulate != Color.WHITE or icon.self_modulate != Color.WHITE:
			return false
		if icon.use_parent_material:
			return false
		var want_color: bool = bool(lit[i])
		if want_color and icon.texture != color_tex:
			return false
		if not want_color and icon.texture != menu._daily_fish_gray_tex:
			return false
	return true


func _fn_body(source: String, name: String) -> String:
	var at := source.find(name)
	if at < 0:
		return ""
	var body := source.substr(at)
	var next := body.find("\nfunc ")
	if next > 0:
		body = body.substr(0, next)
	return body


func _visual_override() -> bool:
	var source := FileAccess.get_file_as_string("res://scenes/menu/main_menu.gd")
	var gate := _fn_body(source, "func _editor_daily_debug_allowed")
	var setter := _fn_body(source, "func _set_daily_visual_override")
	var paint := _fn_body(source, "func _repaint_attempt_fish")
	var choose := _fn_body(source, "func _choose_daily")
	var keys := _fn_body(source, "func _try_daily_visual_override")
	var gated := (
		gate.find("OS.has_feature(\"editor\")") >= 0
		and gate.find("not OS.has_feature(\"template\")") >= 0
		and gate.find("has_feature(\"debug\")") < 0
		and gate.find("is_debug_build") < 0
		and gate.find("is_editor_hint") < 0
	)
	var display_only := (
		setter.find("_daily_lives") < 0
		and setter.find("note_ranked") < 0
		and setter.find("claim") < 0
		and setter.find("finalize") < 0
		and setter.find("start_daily") < 0
		and paint.find("_daily_lives =") < 0
		and choose.find("if _daily_lives <= 0:") >= 0
		and keys.find("KEY_F6") >= 0
		and keys.find("KEY_F7") >= 0
		and keys.find("KEY_F8") >= 0
		and keys.find("KEY_F9") >= 0
		and keys.find("KEY_F10") >= 0
	)
	var menu_script: GDScript = load("res://scenes/menu/main_menu.gd") as GDScript
	if menu_script == null:
		return false
	var menu = menu_script.new()
	var host := Control.new()
	var button := Button.new()
	menu._modes = host
	menu._daily_button = button
	menu._daily_locked = true
	button.disabled = true
	menu._build_daily_fish()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.45, 0.92, 1.0))
	var color_tex := ImageTexture.create_from_image(img)
	menu._remember_fish_color(color_tex)
	menu._apply_attempt_fish(0)
	var session: Node = get_root().get_node("GameSession")
	var allowed: bool = menu._editor_daily_debug_allowed()
	var accepted: bool = menu._set_daily_visual_override(3)
	var painted := false
	if allowed:
		painted = (
			accepted
			and menu._daily_lives == 0
			and menu._daily_locked
			and not button.disabled
			and menu._daily_visual_override == 3
			and int(session.get("editor_daily_test_lives")) == 3
			and not menu._mode_shows_locked()
			and _fish_icons_match(menu, [true, true, true], color_tex)
		)
		menu._set_daily_visual_override(2)
		painted = painted and menu._daily_lives == 0 and not button.disabled and _fish_icons_match(menu, [true, true, false], color_tex)
		menu._set_daily_visual_override(1)
		painted = painted and menu._daily_lives == 0 and not button.disabled and _fish_icons_match(menu, [true, false, false], color_tex)
		menu._set_daily_visual_override(0)
		painted = painted and menu._daily_lives == 0 and button.disabled and menu._mode_shows_locked() and _fish_icons_match(menu, [false, false, false], color_tex)
		var blocked: bool = not bool(session.call("begin_editor_daily_test", {
			"challenge_id": "daily:2026-11-20:cv1:pv1",
			"course_seed": 9,
			"attempt_id": "should-be-stripped",
		}))
		menu._set_daily_visual_override(3)
		menu._apply_attempt_fish(0)
		painted = painted and blocked and menu._daily_lives == 0 and menu._daily_locked and not button.disabled and _fish_icons_match(menu, [true, true, true], color_tex)
		var off: bool = menu._set_daily_visual_override(-1)
		painted = painted and off and menu._daily_visual_override == -1 and not bool(session.call("editor_daily_test_enabled")) and menu._daily_lives == 0 and button.disabled and menu._mode_shows_locked() and _fish_icons_match(menu, [false, false, false], color_tex)
	else:
		painted = (
			not accepted
			and menu._daily_visual_override == -1
			and menu._daily_lives == 0
			and button.disabled
			and _fish_icons_match(menu, [false, false, false], color_tex)
		)
	var echo := InputEventKey.new()
	echo.pressed = true
	echo.echo = true
	echo.keycode = KEY_F6
	var ignored: bool = not menu._try_daily_visual_override(echo)
	if allowed:
		menu._set_daily_visual_override(-1)
	host.free()
	button.free()
	menu.free()
	return gated and display_only and painted and ignored


func _editor_daily_test() -> bool:
	var session = get_root().get_node("GameSession")
	var before_games: int = session.games_played
	var before_coins: int = session.coins
	var before_best: int = session.best_score
	var before_last: int = session.last_score
	var before_mode: String = session.match_mode
	var before_seed: int = session.course_seed
	var before_challenge: String = session.daily_attempt_challenge
	var before_used: int = session.daily_attempt_used
	var before_pending: String = session.pending_finalize_attempt
	var source := FileAccess.get_file_as_string("res://scenes/menu/main_menu.gd")
	var start := _fn_body(source, "func _start_editor_daily_test")
	var isolated := (
		start.find("claim_daily_attempt") < 0
		and start.find("start_daily_attempt") < 0
		and start.find("finalize_daily_attempt") < 0
		and start.find("note_ranked_attempts") < 0
		and start.find("add_coins") < 0
		and start.find("upload_ghost") < 0
	)
	var day_fn := _fn_body(FileAccess.get_file_as_string("res://autoload/game_session.gd"), "func simulate_editor_daily_new_day")
	var day_isolated := (
		day_fn.find("editor_daily_test_allowed") >= 0
		and day_fn.find("claim_daily_attempt") < 0
		and day_fn.find("finalize_daily_attempt") < 0
		and day_fn.find("note_ranked_attempts") < 0
		and day_fn.find("add_coins") < 0
		and day_fn.find("_save") < 0
	)
	if not session.editor_daily_test_allowed():
		return isolated and day_isolated and not session.set_editor_daily_test(3) and not session.begin_editor_daily_test({
			"challenge_id": "daily:2026-11-20:cv1:pv1",
			"course_seed": 9,
		}) and not session.simulate_editor_daily_new_day()
	session.set_editor_daily_test(3)
	var started: bool = session.begin_editor_daily_test({
		"challenge_id": "daily:2026-11-20:cv1:pv1",
		"challenge_date": "2026-11-20",
		"course_seed": 9,
		"attempt_id": "6f1e8c2a-9b34-4d5e-8f70-123456789abc",
		"server_confirmed": true,
	})
	var left: int = int(session.consume_editor_daily_test_life())
	session.record_run(before_last + 40, 1, 1)
	var clean: bool = (
		started
		and session.practice_daily
		and session.course_seed == 9
		and str(session.current_challenge().get("attempt_id", "")) == ""
		and not bool(session.current_challenge().get("server_confirmed", true))
		and left == 2
		and session.games_played == before_games
		and session.coins == before_coins
		and session.best_score == before_best
		and session.last_score == before_last
		and session.daily_attempt_challenge == before_challenge
		and session.daily_attempt_used == before_used
		and session.pending_finalize_attempt == before_pending
	)
	session.editor_daily_test_lives = 0
	var fourth: bool = not session.begin_editor_daily_test({
		"challenge_id": "daily:2026-11-20:cv1:pv1",
		"course_seed": 9,
	})
	session.set_editor_daily_test(3)
	var reset: bool = session.editor_daily_test_lives == 3 and session.begin_editor_daily_test({
		"challenge_id": "daily:2026-11-20:cv1:pv1",
		"course_seed": 9,
	})
	session.end_practice_daily()
	var seed_back: bool = session.course_seed == before_seed
	session.match_mode = before_mode
	session.course_seed = before_seed
	session.set_editor_daily_test(0)
	var day_reset: bool = (
		session.simulate_editor_daily_new_day()
		and session.editor_daily_test_lives == 3
		and session.editor_daily_test_day == 1
		and session.coins == before_coins
		and session.daily_attempt_used == before_used
		and session.begin_editor_daily_test({
			"challenge_id": "daily:2026-11-21:cv1:pv1",
			"course_seed": 11,
		})
	)
	session.end_practice_daily()
	session.match_mode = before_mode
	session.course_seed = before_seed
	session.set_editor_daily_test(-1)
	var restored: bool = (
		not session.editor_daily_test_enabled()
		and not session.practice_daily
		and seed_back
		and session.games_played == before_games
		and session.coins == before_coins
	)
	return isolated and day_isolated and clean and fourth and reset and day_reset and restored


func _unknown() -> bool:
	var missing: Dictionary = DailyAttemptScript.parse_status({"ok": false, "status": 0, "error": "offline"})
	var old_open: Dictionary = DailyAttemptScript.parse_status({
		"ok": true,
		"status": 200,
		"data": [{"attempted": false, "recoverable": false, "challenge_id": "daily:2026-10-20:cv1:pv1", "course_seed": 1}],
	})
	var old_used: Dictionary = DailyAttemptScript.parse_status({
		"ok": true,
		"status": 200,
		"data": [{"attempted": true, "recoverable": false, "challenge_id": "daily:2026-10-20:cv1:pv1", "course_seed": 1}],
	})
	return (
		DailyAttemptScript.lives_from_status(missing) == -1
		and not DailyAttemptScript.fish_lit(0, DailyAttemptScript.lives_from_status(missing))
		and 		DailyAttemptScript.lives_from_status(old_open) == 3
		and int(old_open.get("attempts_used", -1)) == 0
		and int(old_open.get("attempts_remaining", -1)) == 3
		and DailyAttemptScript.fish_lit(0, DailyAttemptScript.lives_from_status(old_open))
		and DailyAttemptScript.fish_lit(1, DailyAttemptScript.lives_from_status(old_open))
		and DailyAttemptScript.fish_lit(2, DailyAttemptScript.lives_from_status(old_open))
		and DailyAttemptScript.lives_from_status(old_used) == 0
		and bool(old_open.get("attempts_counted", false))
	)


# The columns below are the PostgREST row from get_daily_attempt_status.
# The old function stops at recoverable. The three-attempt function adds
# attempts_used, attempts_remaining, and best_score.
func _production_status_shape() -> bool:
	var old_fresh := _status_row(false, -1)
	var old_parsed: Dictionary = DailyAttemptScript.parse_status({"ok": true, "status": 200, "data": [old_fresh]})
	var old_merged: Dictionary = DailyAttemptScript.merge_lives("", 0, old_parsed)
	var counted_fresh := _status_row(true, 3)
	var fresh_parsed: Dictionary = DailyAttemptScript.parse_status({"ok": true, "status": 200, "data": [counted_fresh]})
	var fresh_merged: Dictionary = DailyAttemptScript.merge_lives("", 0, fresh_parsed)
	var one_left: Dictionary = DailyAttemptScript.merge_lives("", 0, DailyAttemptScript.parse_status({
		"ok": true,
		"status": 200,
		"data": [_status_row(true, 1)],
	}))
	var none_left: Dictionary = DailyAttemptScript.merge_lives("", 0, DailyAttemptScript.parse_status({
		"ok": true,
		"status": 200,
		"data": [_status_row(true, 0)],
	}))
	var offline: Dictionary = DailyAttemptScript.merge_lives("", 0, DailyAttemptScript.parse_status({
		"ok": false,
		"status": 0,
		"error": "offline",
	}))
	var menu := FileAccess.get_file_as_string("res://scenes/menu/main_menu.gd")
	var old_lives := int(old_merged.get("lives", 1))
	var fresh_lives := int(fresh_merged.get("lives", -1))
	return (
		not old_fresh.has("attempts_remaining")
		and bool(old_parsed.get("attempts_counted", false))
		and bool(old_parsed.get("attempts_inferred", false))
		and int(old_parsed.get("attempts_used", -1)) == 0
		and int(old_parsed.get("attempts_remaining", -1)) == 3
		and old_lives == 3
		and bool(old_merged.get("store", false))
		and int(old_merged.get("used", -1)) == 0
		and DailyAttemptScript.fish_lit(0, old_lives)
		and DailyAttemptScript.fish_lit(1, old_lives)
		and DailyAttemptScript.fish_lit(2, old_lives)
		and bool(fresh_parsed.get("attempts_counted", false))
		and not bool(fresh_parsed.get("attempts_inferred", false))
		and int(fresh_parsed.get("attempts_remaining", -1)) == 3
		and fresh_lives == 3
		and int(fresh_merged.get("used", -1)) == 0
		and bool(fresh_merged.get("store", false))
		and DailyAttemptScript.fish_lit(0, fresh_lives)
		and DailyAttemptScript.fish_lit(1, fresh_lives)
		and DailyAttemptScript.fish_lit(2, fresh_lives)
		and int(one_left.get("lives", -1)) == 1
		and DailyAttemptScript.fish_lit(0, 1)
		and not DailyAttemptScript.fish_lit(1, 1)
		and int(none_left.get("lives", -1)) == 0
		and not DailyAttemptScript.fish_lit(0, 0)
		and int(offline.get("lives", 0)) == -1
		and menu.find("if _daily_lives <= 0:") >= 0
	)


func _status_row(counted: bool, remaining: int) -> Dictionary:
	var course := DailyChallengeScript.make("2026-11-20", true, DailyChallengeScript.unix_utc(2026, 11, 20, 18, 0))
	var row := {
		"challenge_id": str(course.get("challenge_id", "")),
		"challenge_date": str(course.get("challenge_date", "")),
		"course_seed": int(course.get("course_seed", 0)),
		"course_version": int(course.get("course_version", 0)),
		"physics_version": int(course.get("physics_version", 0)),
		"as_of": "2026-11-20T23:00:00+00:00",
		"as_of_unix": int(course.get("as_of_unix", 0)),
		"resets_at": "2026-11-21T05:00:00+00:00",
		"resets_unix": int(course.get("as_of_unix", 0)) + 6 * 3600,
		"attempted": counted and remaining < 3,
		"recoverable": false,
	}
	if counted:
		row["attempts_used"] = 3 - remaining
		row["attempts_remaining"] = remaining
		row["best_score"] = 0
	return row


func _counted(cid: String, remaining: int) -> Dictionary:
	return {
		"ok": true,
		"attempts_counted": true,
		"attempts_remaining": remaining,
		"attempted": remaining < 3,
		"challenge_id": cid,
	}


func _restart_floor() -> bool:
	var cid := "daily:2026-10-20:cv1:pv1"
	var next := "daily:2026-10-21:cv1:pv1"
	var spent: Dictionary = DailyAttemptScript.merge_lives("", 0, _counted(cid, 0))
	if int(spent.get("lives", -1)) != 0 or int(spent.get("used", 0)) != 3:
		return false
	# Closing and reopening with a late or old payload must not light a fish.
	var again: Dictionary = DailyAttemptScript.merge_lives(cid, 3, _counted(cid, 1))
	var delayed: Dictionary = DailyAttemptScript.merge_lives(cid, 3, _counted(cid, 3))
	var offline: Dictionary = DailyAttemptScript.merge_lives(cid, 3, {"ok": false, "status": 0})
	var legacy: Dictionary = DailyAttemptScript.merge_lives(cid, 3, DailyAttemptScript.parse_status({
		"ok": true,
		"status": 200,
		"data": [{"attempted": false, "challenge_id": cid, "course_seed": 1}],
	}))
	var opened: Dictionary = DailyAttemptScript.merge_lives("", 0, _counted(cid, 2))
	var after_one: Dictionary = DailyAttemptScript.merge_lives(cid, int(opened.get("used", 0)), _counted(cid, 2))
	var two_left: Dictionary = DailyAttemptScript.merge_lives(cid, 1, _counted(cid, 2))
	var one_left: Dictionary = DailyAttemptScript.merge_lives(cid, 2, _counted(cid, 1))
	var unfinalized: Dictionary = DailyAttemptScript.merge_lives(cid, 3, _counted(cid, 0))
	var fresh_day: Dictionary = DailyAttemptScript.merge_lives(cid, 3, _counted(next, 3))
	var menu := FileAccess.get_file_as_string("res://scenes/menu/main_menu.gd")
	var attempt := FileAccess.get_file_as_string("res://scripts/daily_attempt.gd")
	var session := FileAccess.get_file_as_string("res://autoload/game_session.gd")
	var practice := FileAccess.get_file_as_string("res://scripts/daily_test_mode.gd")
	return (
		int(again.get("lives", -1)) == 0
		and int(again.get("used", 0)) == 3
		and int(delayed.get("lives", -1)) == 0
		and int(offline.get("lives", -1)) == 0
		and int(legacy.get("lives", -1)) == 0
		and int(legacy.get("used", 0)) == 3
		and int(DailyAttemptScript.merge_lives("", 0, DailyAttemptScript.parse_status({
			"ok": true,
			"status": 200,
			"data": [{"attempted": false, "challenge_id": cid, "course_seed": 1}],
		})).get("lives", 1)) == 3
		and bool(DailyAttemptScript.merge_lives("", 0, DailyAttemptScript.parse_status({
			"ok": true,
			"status": 200,
			"data": [{"attempted": false, "challenge_id": cid, "course_seed": 1}],
		})).get("store", false))
		and int(DailyAttemptScript.merge_lives(cid, 1, DailyAttemptScript.parse_status({
			"ok": true,
			"status": 200,
			"data": [{"attempted": false, "challenge_id": cid, "course_seed": 1}],
		})).get("lives", -1)) == 2
		and int(after_one.get("lives", -1)) == 2
		and int(two_left.get("lives", -1)) == 2
		and int(one_left.get("lives", -1)) == 1
		and int(unfinalized.get("lives", -1)) == 0
		and int(fresh_day.get("lives", -1)) == 3
		and int(fresh_day.get("used", -1)) == 0
		and str(fresh_day.get("challenge_id", "")) == next
		and menu.find("merge_lives") >= 0
		and menu.find("note_ranked_attempts") >= 0
		and menu.find("DAILY_CHALLENGE_TEST_MODE") < 0
		and attempt.find("else 1") < 0
		and session.find("func note_ranked_attempts") >= 0
		and session.find("if DailyTestModeScript.enabled():") >= 0
		and practice.find("const DAILY_CHALLENGE_TEST_MODE := false") >= 0
	)


func _button_art() -> bool:
	var menu_script: GDScript = load("res://scenes/menu/main_menu.gd") as GDScript
	if menu_script == null:
		return false
	var menu = menu_script.new()
	var card := TextureRect.new()
	var button := Button.new()
	menu._mode_card = card
	menu._daily_button = button
	menu._daily_locked = false
	menu._daily_lives = 3
	menu._apply_mode_art()
	var open_art: Texture2D = card.texture
	menu._apply_attempt_fish(3)
	var three: bool = menu._daily_lives == 3 and not menu._mode_shows_locked() and card.texture == open_art
	menu._apply_attempt_fish(2)
	var two: bool = menu._daily_lives == 2 and not menu._mode_shows_locked() and card.texture == open_art
	menu._apply_attempt_fish(1)
	var one: bool = menu._daily_lives == 1 and not menu._mode_shows_locked() and card.texture == open_art
	menu._daily_locked = true
	menu._apply_attempt_fish(0)
	button.disabled = true
	button.modulate = Color.WHITE
	menu._apply_mode_art()
	var zero: bool = (
		menu._mode_shows_locked()
		and menu._daily_lives == 0
		and button.disabled
		and button.modulate == Color.WHITE
		and card.texture != null
		and card.texture != open_art
	)
	menu._daily_locked = false
	menu._apply_mode_art()
	var restored: bool = not menu._mode_shows_locked() and card.texture == open_art
	var source := FileAccess.get_file_as_string("res://scenes/menu/main_menu.gd")
	var locked_fn := source.substr(source.find("func _show_daily_completed"))
	locked_fn = locked_fn.substr(0, locked_fn.find("\nfunc _clear_daily_lock"))
	var note_fn := source.substr(source.find("func _set_mode_note"))
	note_fn = note_fn.substr(0, note_fn.find("\nfunc "))
	var fish_ignore: bool = (
		source.find("icon.mouse_filter = Control.MOUSE_FILTER_IGNORE") >= 0
		and locked_fn.find("_apply_mode_art()") >= 0
		and locked_fn.find("0.45") < 0
		and locked_fn.find("COMPLETED_LABEL") < 0
		and note_fn.find("_mode_note.visible = false") >= 0
		and source.find("_set_mode_reset(_daily_reset_text") < 0
	)
	menu.free()
	card.free()
	button.free()
	return three and two and one and zero and restored and fish_ignore and open_art != null


func _locked() -> bool:
	var open_status := {"ok": true, "attempts_remaining": 2, "attempted": true}
	var closed_status := {"ok": true, "attempts_remaining": 0, "attempted": true}
	return DailyAttemptScript.lives_from_status(open_status) == 2 and DailyAttemptScript.lives_from_status(closed_status) == 0


func _active() -> bool:
	var game := FileAccess.get_file_as_string("res://scenes/game/game.gd")
	return game.find("attempts_remaining") < 0 and game.find("attempts_used") < 0


func _board() -> bool:
	return _best()


func _other_modes() -> bool:
	var book := DailyChallengeScript.empty_book()
	var when := DailyChallengeScript.unix_utc(2026, 10, 20, 18, 0)
	DailyAttemptScript.submit_unlimited(book, "player-a", "REEF", 12, when)
	DailyAttemptScript.submit_unlimited(book, "player-a", "REEF", 4, when)
	var weekly: Array = DailyChallengeScript.visible_board(book, "weekly", when)
	var monthly: Array = DailyChallengeScript.visible_board(book, "monthly", when)
	var daily: Array = DailyChallengeScript.visible_board(book, "daily", when)
	return (
		not DailyAttemptScript.attempt_required("unlimited")
		and weekly.size() == 1
		and int(weekly[0].get("score", 0)) == 12
		and monthly.size() == 1
		and int(monthly[0].get("score", 0)) == 12
		and daily.is_empty()
	)


func _sql() -> bool:
	var sql := FileAccess.get_file_as_string("res://tools/supabase/daily_three_attempts.sql")
	return (
		sql.find("greatest(0, 3 - v_used)") >= 0
		and sql.find("unique (player_id, challenge_id, idempotency_key)") >= 0
		and sql.find("drop constraint daily_attempts_player_challenge") >= 0
		and sql.find("score = greatest(public.leaderboard_scores.score, excluded.score)") >= 0
		and sql.find("pg_advisory_xact_lock") >= 0
		and sql.find("America/New_York") < 0
		and sql.find("grant execute on function public.claim_daily_attempt(uuid) to authenticated") >= 0
	)


func _fit() -> bool:
	var menu_script: GDScript = load("res://scenes/menu/main_menu.gd") as GDScript
	var menu = menu_script.new()
	var screens: Array[Vector2] = [
		Vector2(540, 960),
		Vector2(540, 1080),
		Vector2(540, 1170),
		Vector2(540, 1260),
	]
	if menu.daily_fish_slots().size() != 3:
		menu.free()
		return false
	for screen in screens:
		var cover: Rect2 = menu._mode_cover_rect(screen)
		var scale := Vector2(cover.size.x / menu.MODE_W, cover.size.y / menu.MODE_H)
		var unlimited := Rect2(cover.position + menu.MODE_UNLIMITED.position * scale, menu.MODE_UNLIMITED.size * scale)
		var note := Rect2(cover.position + menu.MODE_NOTE.position * scale, menu.MODE_NOTE.size * scale)
		var bounds := Rect2(Vector2.ZERO, screen)
		for fish in menu.daily_fish_screen_rects(cover):
			if not bounds.encloses(fish) or fish.intersects(unlimited) or fish.intersects(note):
				menu.free()
				return false
			if absf(fish.size.x - fish.size.y) > 0.01:
				menu.free()
				return false
	menu.free()
	return true
