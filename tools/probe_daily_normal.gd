extends SceneTree

const DailyTestModeScript := preload("res://scripts/daily_test_mode.gd")

# Reads the real Daily Challenge status and paints the menu from it.
# Does not claim, start, finalize, or change an attempt.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = root.get_node("GameSession")
	if session.editor_daily_test_enabled():
		session.set_editor_daily_test(-1)
	var launch: Dictionary = await _watch_menu("launch")
	var shot_ok := await _save_shot(launch.get("menu"))
	_drop_menu(launch.get("menu"))
	await process_frame
	await process_frame
	var restart: Dictionary = await _watch_menu("restart")
	_drop_menu(restart.get("menu"))
	var same := int(launch.get("lives", -1)) == int(restart.get("lives", -2)) and int(launch.get("lives", -1)) >= 0
	var ok: bool = bool(launch.get("ok", false)) and bool(restart.get("ok", false)) and same and shot_ok
	print("[daily-normal] ok=%s lives=%d restart_lives=%d fish=%s button=%s saw_checking=%s blocked_click=%s override_off=%s status=%s attempted=%s counted=%s shot=%s" % [
		str(ok),
		int(launch.get("lives", -1)),
		int(restart.get("lives", -1)),
		str(launch.get("fish", "")),
		str(launch.get("button_on", false)),
		str(launch.get("saw_checking", false)),
		str(launch.get("blocked_click", false)),
		str(launch.get("override_off", false)),
		str(int(launch.get("status_code", 0))),
		str(launch.get("attempted", false)),
		str(launch.get("counted", false)),
		str(shot_ok),
	])
	quit(0 if ok else 1)


func _watch_menu(label: String) -> Dictionary:
	var session = root.get_node("GameSession")
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	var saw_checking := false
	var blocked_click := false
	var first := _observe_checking_click(menu)
	if not first.is_empty():
		saw_checking = true
		blocked_click = bool(first.get("blocked", false))
	for _frame in 20:
		await process_frame
		if saw_checking:
			continue
		var observed := _observe_checking_click(menu)
		if observed.is_empty():
			continue
		saw_checking = true
		blocked_click = bool(observed.get("blocked", false))
	menu._open_modes()
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if menu._status_busy or menu._daily_checking:
			if not saw_checking:
				var observed := _observe_checking_click(menu)
				if not observed.is_empty():
					saw_checking = true
					blocked_click = bool(observed.get("blocked", false))
			continue
		if bool(menu._last_daily_status.get("ok", false)) and menu._daily_lives >= 0:
			break
	await RenderingServer.frame_post_draw
	var status: Dictionary = menu._last_daily_status
	var lives := int(menu._daily_lives)
	var colored := 0
	if lives >= 0:
		for i in 3:
			if lives > i:
				colored += 1
	var button_disabled: bool = menu._daily_button != null and menu._daily_button.disabled
	print("[daily-probe] phase=%s" % label)
	print("[daily] checking=%s remaining=%s fish_colored=%s button_disabled=%s" % [
		str(menu._daily_checking),
		str(lives) if lives >= 0 else "absent",
		str(colored) if lives >= 0 else "loading",
		str(button_disabled),
	])
	var button_on: bool = not button_disabled
	var override_off: bool = (
		not session.editor_daily_test_enabled()
		and int(menu._daily_visual_override) < 0
		and not DailyTestModeScript.enabled()
	)
	var samples: PackedStringArray = PackedStringArray()
	var image: Image = root.get_texture().get_image()
	if image != null:
		for icon in menu._daily_fish:
			samples.append(_sample(image, icon))
	var fish_match: bool = _samples_match(lives, samples)
	var button_match: bool = button_on == (lives > 0)
	var settled: bool = not menu._daily_checking and not menu._status_busy and lives >= 0
	var ok: bool = (
		override_off
		and saw_checking
		and blocked_click
		and settled
		and bool(status.get("ok", false))
		and fish_match
		and button_match
	)
	return {
		"menu": menu,
		"ok": ok,
		"lives": lives,
		"fish": ",".join(samples),
		"button_on": button_on,
		"saw_checking": saw_checking,
		"blocked_click": blocked_click,
		"override_off": override_off,
		"status_code": int(status.get("status", 0)),
		"attempted": bool(status.get("attempted", false)),
		"counted": bool(status.get("attempts_counted", false)),
	}


func _observe_checking_click(menu) -> Dictionary:
	if not menu._daily_checking and not menu._status_busy:
		return {}
	if menu._daily_button != null and not menu._daily_button.disabled:
		print("[daily] probe refused click while button looked ready")
		return {"saw": true, "blocked": false}
	var token: int = menu._mode_token
	menu._choose_daily()
	var blocked: bool = not menu._mode_busy and menu._mode_token == token and menu._daily_button != null and menu._daily_button.disabled
	return {"saw": true, "blocked": blocked}


func _save_shot(menu) -> bool:
	if menu == null:
		return false
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var shot := "C:/Users/civis/Documents/LunarEnt/GodotGames/Reefrun/tools/daily_fish_shots/normal_live.png"
	if OS.get_environment("REEFRUN_NORMAL_SHOT") != "":
		shot = OS.get_environment("REEFRUN_NORMAL_SHOT")
	if image == null:
		return false
	return image.save_png(shot) == OK


func _drop_menu(menu) -> void:
	if menu != null and is_instance_valid(menu):
		menu.queue_free()


func _sample(image: Image, icon: TextureRect) -> String:
	if not icon.visible:
		return "hidden"
	var rect := icon.get_global_rect()
	var viewport := root.get_viewport()
	var view := viewport.get_visible_rect().size
	if view.x <= 1.0 or view.y <= 1.0:
		view = Vector2(image.get_width(), image.get_height())
	var scale := Vector2(float(image.get_width()) / view.x, float(image.get_height()) / view.y)
	rect = Rect2(rect.position * scale, rect.size * scale)
	var inset := rect.size * 0.28
	var box := Rect2(rect.position + inset, rect.size - inset * 2.0)
	var colored := 0
	var seen := 0
	var x0 := clampi(int(box.position.x), 0, image.get_width() - 1)
	var y0 := clampi(int(box.position.y), 0, image.get_height() - 1)
	var x1 := clampi(int(box.end.x), x0 + 1, image.get_width())
	var y1 := clampi(int(box.end.y), y0 + 1, image.get_height())
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			var px := image.get_pixel(x, y)
			if px.a < 0.3:
				continue
			seen += 1
			var hi := maxf(px.r, maxf(px.g, px.b))
			var lo := minf(px.r, minf(px.g, px.b))
			if hi - lo > 0.12:
				colored += 1
	return "color" if seen > 0 and float(colored) / float(seen) > 0.15 else "gray"


func _samples_match(lives: int, samples: PackedStringArray) -> bool:
	if lives < 0:
		return false
	var expect: PackedStringArray = PackedStringArray()
	for i in 3:
		expect.append("color" if lives > i else "gray")
	return ",".join(samples) == ",".join(expect)
