extends SceneTree

# Editor-only simulated challenge day. Does not write Supabase or the save.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = root.get_node("GameSession")
	if not session.editor_daily_test_allowed():
		print("[daily-day] ok=true export_build=refused")
		quit(0)
		return
	var before_coins: int = session.coins
	var before_games: int = session.games_played
	var before_best: int = session.best_score
	var before_used: int = session.daily_attempt_used
	var before_challenge: String = session.daily_attempt_challenge
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	for _i in 20:
		await process_frame
	var enable := _find_button(menu, "ENABLE 3")
	var new_day := _find_button(menu, "NEW DAY")
	if enable == null or new_day == null:
		_fail("DAILY TEST buttons are missing")
		return
	enable.pressed.emit()
	for _i in 20:
		await process_frame
		if session.editor_daily_test_lives == 3 and menu._modes != null and menu._modes.visible:
			break
	if not _fish_ok(menu, 3):
		_fail("start did not show 3 colored fish")
		return
	for _step in 3:
		session.consume_editor_daily_test_life()
	menu._set_daily_visual_override(0)
	if session.editor_daily_test_lives != 0 or not _fish_ok(menu, 0):
		_fail("three local lives were not consumed")
		return
	new_day.pressed.emit()
	for _i in 20:
		await process_frame
		if session.editor_daily_test_lives == 3:
			break
	var unlocked: bool = session.begin_editor_daily_test({
		"challenge_id": "daily:local-day:cv1:pv1",
		"challenge_date": "2026-11-22",
		"course_seed": 4242,
		"attempt_id": "must-be-stripped",
		"server_confirmed": true,
	})
	var clean: bool = (
		unlocked
		and session.practice_daily
		and str(session.current_challenge().get("attempt_id", "")) == ""
		and not bool(session.current_challenge().get("server_confirmed", true))
		and session.editor_daily_test_day >= 1
		and session.coins == before_coins
		and session.games_played == before_games
		and session.best_score == before_best
		and session.daily_attempt_used == before_used
		and session.daily_attempt_challenge == before_challenge
		and _fish_ok(menu, 3)
		and menu._daily_button != null
		and not menu._daily_button.disabled
	)
	session.end_practice_daily()
	session.set_editor_daily_test(-1)
	if not clean:
		_fail("new day did not restore 3 local lives lives=%d day=%d" % [
			session.editor_daily_test_lives,
			session.editor_daily_test_day,
		])
		return
	print("[daily-day] lives=3 fish=colored,colored,colored button_disabled=false supabase=untouched")
	print("[daily-day] ok=true")
	quit(0)


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


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _fail(reason: String) -> void:
	push_error("[daily-day] %s" % reason)
	print("[daily-day] ok=false")
	quit(1)
