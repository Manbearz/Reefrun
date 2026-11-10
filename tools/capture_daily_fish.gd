extends SceneTree

const OUT := "C:/Users/civis/Documents/LunarEnt/GodotGames/Reefrun/tools/daily_fish_shots"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu._open_modes()
	menu._status_gen += 100
	await RenderingServer.frame_post_draw
	var ok := true
	for lives in [3, 2, 1, 0]:
		if lives == 0:
			menu._daily_locked = true
			if menu._daily_button:
				menu._daily_button.disabled = true
				menu._daily_button.modulate = Color.WHITE
			menu._apply_mode_art()
		else:
			menu._daily_locked = false
			if menu._daily_button:
				menu._daily_button.disabled = false
				menu._daily_button.modulate = Color.WHITE
			menu._apply_mode_art()
		menu._apply_attempt_fish(lives)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image == null:
			push_error("[daily-shot] no viewport image lives=%d" % lives)
			ok = false
			continue
		var path := "%s/lives_%d.png" % [OUT, lives]
		var err := image.save_png(path)
		var colors: PackedStringArray = PackedStringArray()
		for icon in menu._daily_fish:
			colors.append(_sample(image, icon))
		print("[daily-shot] lives=%d save=%s samples=%s" % [lives, err, ",".join(colors)])
		if not _samples_match(lives, colors):
			ok = false
	print("[daily-shot] ok=%s" % ok)
	quit(0 if ok else 1)


func _sample(image: Image, icon: TextureRect) -> String:
	var rect := icon.get_global_rect()
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
