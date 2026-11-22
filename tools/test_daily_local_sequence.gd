extends SceneTree

const COURSE := {
	"challenge_id": "daily:2026-11-21:cv1:pv1",
	"challenge_date": "2026-11-21",
	"course_seed": 4242,
	"attempt_id": "must-be-stripped",
	"server_confirmed": true,
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = root.get_node("GameSession")
	var allowed: bool = session.editor_daily_test_allowed()
	var expect_allowed: bool = OS.has_feature("editor") and not OS.has_feature("template")
	print("[daily-seq] features editor=%s template=%s debug=%s allowed=%s" % [
		OS.has_feature("editor"),
		OS.has_feature("template"),
		OS.has_feature("debug"),
		allowed,
	])
	if allowed != expect_allowed:
		_fail("export gate does not match editor-and-not-template")
		return
	var gate := FileAccess.get_file_as_string("res://autoload/game_session.gd")
	var gate_at := gate.find("func editor_daily_test_allowed")
	var gate_body := gate.substr(gate_at, 220)
	if gate_body.find("OS.has_feature(\"editor\")") < 0 or gate_body.find("not OS.has_feature(\"template\")") < 0:
		_fail("exported builds are not rejected by editor_daily_test_allowed")
		return
	if not allowed:
		print("[daily-seq] ok=true export_build=refused")
		quit(0)
		return
	var snap := _snap(session)
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	for _i in 20:
		await process_frame
	if menu.get_node_or_null("EditorDailyTest") == null or not menu.get_node("EditorDailyTest").visible:
		_fail("DAILY TEST button is missing from the running menu")
		return
	_push_key(KEY_F6, false, false)
	await process_frame
	if not session.editor_daily_test_enabled() or session.editor_daily_test_lives != 3:
		_fail("F6 did not reach the menu handler")
		return
	print("[daily-seq] f6_reached=true lives=%d" % session.editor_daily_test_lives)
	var server_btn := _find_button(menu, "SERVER")
	if server_btn == null:
		_fail("SERVER button missing")
		return
	server_btn.pressed.emit()
	await process_frame
	if session.editor_daily_test_enabled():
		_fail("SERVER did not turn local test off")
		return
	var enable := _find_button(menu, "ENABLE 3")
	if enable == null:
		_fail("ENABLE 3 button missing")
		return
	enable.pressed.emit()
	for _i in 30:
		await process_frame
		if menu._modes != null and menu._modes.visible and session.editor_daily_test_lives == 3:
			break
	if session.editor_daily_test_lives != 3 or not session.editor_daily_test_enabled():
		_fail("ENABLE 3 did not turn local test on")
		return
	print("[daily-seq] button_enabled=true lives=%d modes=%s" % [session.editor_daily_test_lives, menu._modes.visible])
	var lives_after: Array[int] = [2, 1, 0]
	for run_i in 3:
		var started: bool = await _play_one(menu, lives_after[run_i])
		menu = _menu()
		if not started or menu == null:
			_fail("run %d did not finish" % (run_i + 1))
			return
		if not _fish_ok(menu, lives_after[run_i]):
			_fail("fish or button wrong after run %d lives=%d disabled=%s" % [
				run_i + 1,
				menu._fish_display_lives(),
				menu._daily_button.disabled,
			])
			return
		print("[daily-seq] run=%d lives=%d button_disabled=%s fish_ok=true" % [
			run_i + 1,
			session.editor_daily_test_lives,
			menu._daily_button.disabled,
		])
	if not await _wait_absent("Game", 120):
		_fail("game was still loaded before the locked attempt")
		return
	menu = _menu()
	if menu == null:
		_fail("menu missing before the locked attempt")
		return
	menu._status_course = COURSE.duplicate(true)
	menu._choose_daily()
	for _i in 30:
		await process_frame
		if _game() != null:
			_fail("fourth local attempt started a game")
			return
	menu = _menu()
	if menu == null or session.editor_daily_test_lives != 0 or not menu._daily_button.disabled:
		_fail("fourth attempt was not locked")
		return
	print("[daily-seq] fourth_locked=true lives=0 button_disabled=true")
	_push_key(KEY_9, true, true)
	for _i in 20:
		await process_frame
		if session.editor_daily_test_lives == 3:
			break
	menu = _menu()
	if menu == null or session.editor_daily_test_lives != 3 or menu._daily_button.disabled:
		_fail("Ctrl+Shift+9 did not reset local lives to 3")
		return
	print("[daily-seq] reset=true lives=%d button_disabled=%s" % [session.editor_daily_test_lives, menu._daily_button.disabled])
	var again: bool = await _play_one(menu, 2)
	menu = _menu()
	if not again or menu == null or not _fish_ok(menu, 2):
		_fail("reset run did not spend one life")
		return
	var now := _snap(session)
	var same := _same(snap, now)
	var clean: bool = (
		not session.practice_daily
		and str(session.current_challenge().get("attempt_id", "")) == ""
		and same
	)
	print("[daily-seq] production_unchanged=%s practice=%s" % [same, session.practice_daily])
	if not clean:
		_fail("local runs changed saved progress")
		return
	print("[daily-seq] ok=true")
	quit(0)


func _play_one(menu: Node, expect_left: int) -> bool:
	var session = root.get_node("GameSession")
	if not await _wait_absent("Game", 120):
		push_error("[daily-seq] previous game was still loaded")
		return false
	if not is_instance_valid(menu):
		menu = _menu()
	if menu == null:
		return false
	menu._status_course = COURSE.duplicate(true)
	menu._status_gen += 50
	var coins: int = session.coins
	var games: int = session.games_played
	var best: int = session.best_score
	var last: int = session.last_score
	var used: int = session.daily_attempt_used
	var challenge: String = session.daily_attempt_challenge
	var pending: String = session.pending_finalize_attempt
	var unlimited: int = session.pending_unlimited_score
	var before_id := menu.get_instance_id()
	menu._choose_daily()
	var game := await _wait_current("Game", before_id, 900)
	if game == null:
		push_error("[daily-seq] no new game scene")
		return false
	var attempt_id := str(session.current_challenge().get("attempt_id", ""))
	var confirmed: bool = bool(session.current_challenge().get("server_confirmed", true))
	var local_ok: bool = (
		session.practice_daily
		and session.match_mode == session.MODE_DAILY
		and attempt_id == ""
		and not confirmed
		and session.editor_daily_test_lives == expect_left
		and int(session.course_seed) == 4242
	)
	if not local_ok:
		push_error("[daily-seq] swim failed local=false lives=%d attempt=%s mode=%s practice=%s" % [
			session.editor_daily_test_lives,
			attempt_id,
			session.match_mode,
			session.practice_daily,
		])
		return false
	session.record_run(last + 90, 1, 1)
	var isolated: bool = (
		session.practice_daily
		and session.coins == coins
		and session.games_played == games
		and session.best_score == best
		and session.last_score == last
		and session.daily_attempt_used == used
		and session.daily_attempt_challenge == challenge
		and session.pending_finalize_attempt == pending
		and session.pending_unlimited_score == unlimited
	)
	if not isolated:
		push_error("[daily-seq] swim wrote saved progress lives=%d" % session.editor_daily_test_lives)
		return false
	var game_id := game.get_instance_id()
	game._menu()
	var back := await _wait_current("MainMenu", game_id, 300)
	if not await _wait_absent("Game", 120):
		push_error("[daily-seq] game stayed loaded after returning to the menu")
		return false
	return back != null and session.editor_daily_test_lives == expect_left


func _fish_ok(menu: Node, lives: int) -> bool:
	if menu._fish_display_lives() != lives:
		return false
	if menu._daily_button == null or menu._daily_button.disabled != (lives <= 0):
		return false
	if menu._daily_fish.size() != 3:
		return false
	for i in 3:
		var lit: bool = lives > i
		var icon: TextureRect = menu._daily_fish[i]
		var gray: bool = menu._daily_fish_gray_tex != null and icon.texture == menu._daily_fish_gray_tex
		if lit == gray:
			return false
	return true


func _push_key(code: Key, ctrl: bool, shift: bool) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = code
	ev.physical_keycode = code
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ev.alt_pressed = false
	root.push_input(ev)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _menu() -> Node:
	return _named_current("MainMenu")


func _game() -> Node:
	return _named_current("Game")


func _named_current(node_name: String) -> Node:
	var scene := current_scene
	if scene == null or not is_instance_valid(scene) or scene.is_queued_for_deletion():
		return null
	if str(scene.name) != node_name:
		return null
	return scene


func _wait_current(node_name: String, previous_id: int, limit: int) -> Node:
	for _i in limit:
		var found := _named_current(node_name)
		if found != null and found.get_instance_id() != previous_id:
			return found
		await process_frame
	return null


func _wait_absent(node_name: String, limit: int) -> bool:
	for _i in limit:
		var raw := root.get_node_or_null(node_name)
		if raw == null or not is_instance_valid(raw):
			return true
		await process_frame
	return false


func _snap(session) -> Dictionary:
	return {
		"coins": session.coins,
		"games": session.games_played,
		"best": session.best_score,
		"last": session.last_score,
		"used": session.daily_attempt_used,
		"challenge": session.daily_attempt_challenge,
		"resets": session.daily_attempt_resets_unix,
		"pending": session.pending_finalize_attempt,
		"unlimited": session.pending_unlimited_score,
		"daily_board": _board_sig(session.daily),
		"weekly_board": _board_sig(session.weekly),
		"monthly_board": _board_sig(session.monthly),
	}


func _board_sig(board: Array) -> String:
	var parts: PackedStringArray = []
	for entry in board:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		parts.append("%s:%d" % [str(entry.get("name", "")), int(entry.get("score", 0))])
	return ",".join(parts)


func _same(before: Dictionary, after: Dictionary) -> bool:
	for key in before.keys():
		if before[key] != after[key]:
			push_error("[daily-seq] changed %s before=%s after=%s" % [key, before[key], after[key]])
			return false
	return true


func _fail(reason: String) -> void:
	push_error("[daily-seq] %s" % reason)
	print("[daily-seq] ok=false")
	quit(1)
