extends SceneTree

const DailyAttempt := preload("res://scripts/daily_attempt.gd")
const OUT := "C:/Users/civis/Documents/LunarEnt/GodotGames/Reefrun/tools/daily_fish_shots"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	for _frame in 8:
		await process_frame
	menu._open_modes()
	menu._status_gen += 100
	for _frame in 20:
		await process_frame
		if menu._daily_fish_color != null:
			break
	await RenderingServer.frame_post_draw
	var ok := true
	if not await _save_loading(menu):
		ok = false
	var fresh := _apply_server(menu, {
		"challenge_id": "daily:2026-11-21:cv1:pv1",
		"challenge_date": "2026-11-21",
		"course_seed": 1,
		"attempted": false,
		"recoverable": false,
	})
	if fresh != 3 or not await _save_lives(menu, 3):
		push_error("[daily-shot] fresh day did not show 3 colored fish")
		ok = false
	if not await _save_lives(menu, _apply_server(menu, _counted(1, 2))):
		ok = false
	if not await _save_lives(menu, _apply_server(menu, _counted(2, 1))):
		ok = false
	if not await _save_lives(menu, _apply_server(menu, _counted(3, 0))):
		ok = false
	if menu._editor_test_row == null or not menu._editor_test_row.visible:
		push_error("[daily-shot] LOCAL TEST bar is missing")
		ok = false
	print("[daily-shot] ok=%s" % ok)
	quit(0 if ok else 1)


func _counted(used: int, remaining: int) -> Dictionary:
	return {
		"challenge_id": "daily:2026-11-21:cv1:pv1",
		"challenge_date": "2026-11-21",
		"course_seed": 1,
		"attempted": used > 0,
		"recoverable": false,
		"attempts_used": used,
		"attempts_remaining": remaining,
	}


func _apply_server(menu: Node, row: Dictionary) -> int:
	var parsed: Dictionary = DailyAttempt.parse_status({"ok": true, "status": 200, "data": [row]})
	var merged: Dictionary = DailyAttempt.merge_lives("", 0, parsed)
	var lives := int(merged.get("lives", -1))
	menu._last_daily_status = parsed
	menu._daily_source = str(DailyAttempt.count_verdict(parsed).get("source", "unavailable"))
	var session = root.get_node_or_null("GameSession")
	if session != null and session.has_method("set_editor_daily_test"):
		session.set_editor_daily_test(-1)
	menu._apply_attempt_fish(lives)
	return lives


func _save_loading(menu: Node) -> bool:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("[daily-shot] no viewport image for loading")
		return false
	var err := image.save_png("%s/initial_loading.png" % OUT)
	var hidden := true
	for icon in menu._daily_fish:
		if icon.visible:
			hidden = false
	print("[daily-shot] loading save=%s hidden=%s displayed=%d" % [err, hidden, menu._fish_display_lives()])
	return err == OK and hidden and menu._fish_display_lives() < 0


func _save_lives(menu: Node, lives: int) -> bool:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("[daily-shot] no viewport image lives=%d" % lives)
		return false
	var err := image.save_png("%s/lives_%d.png" % [OUT, lives])
	var colors: PackedStringArray = PackedStringArray()
	for icon in menu._daily_fish:
		colors.append(_sample(image, icon))
	var disabled: bool = menu._daily_button != null and menu._daily_button.disabled
	var expect_disabled: bool = lives <= 0
	print("[daily-shot] lives=%d save=%s disabled=%s samples=%s" % [lives, err, disabled, ",".join(colors)])
	return err == OK and disabled == expect_disabled and _samples_match(lives, colors) and menu._fish_display_lives() == lives


func _sample(image: Image, icon: TextureRect) -> String:
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
	var expect: PackedStringArray = PackedStringArray()
	for i in 3:
		expect.append("color" if lives > i else "gray")
	return ",".join(samples) == ",".join(expect)
