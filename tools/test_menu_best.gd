extends SceneTree

## Main-menu Personal Best uses GameSession.best_score, the same record as Wiped Out NEW.

func _initialize() -> void:
	root.add_child(Runner.new())


class Runner extends Node:
	const SAVE_PATH := "user://reefrun.cfg"

	func _ready() -> void:
		var snap := _snapshot()
		var fail := await _checks()
		if fail != "":
			push_error("[menu-best] " + fail)
		_restore(snap)
		var session := get_node("/root/GameSession")
		var code := 0 if fail == "" else 1
		if int(session.best_score) != int(snap["best"]) or str(session.match_mode) != str(snap["mode"]) or bool(session.practice_daily) != bool(snap["practice"]):
			push_error("[menu-best] save was not restored best=%s mode=%s practice=%s" % [session.best_score, session.match_mode, session.practice_daily])
			code = 1
		else:
			print("[menu-best] restored personal best %s" % session.best_score)
		print("[menu-best] %s" % ("ok" if code == 0 else "failed"))
		get_tree().quit(code)

	func _checks() -> String:
		var session := get_node("/root/GameSession")
		var menu: Node = load("res://scenes/menu/main_menu.tscn").instantiate()
		add_child(menu)
		menu.set_process(false)
		menu.set_process_input(false)
		await get_tree().process_frame
		var game: Node = load("res://scenes/game/game.tscn").instantiate()
		game.set("debug_skip_ready", true)
		add_child(game)
		await get_tree().process_frame
		session.practice_daily = false
		session.match_mode = ""
		session.best_score = 0
		menu.call("_layout_personal_best")
		var shown := _label(menu)
		if shown != "PERSONAL BEST 0":
			return "new player showed %s" % shown
		session.best_score = 20
		menu.call("_layout_personal_best")
		if _label(menu) != "PERSONAL BEST 20":
			return "best 20 showed %s" % _label(menu)
		game.set("score", 15)
		game.call("_note_personal_best")
		if bool(game.get("_wipe_new_best")):
			return "score 15 was treated as a new record"
		session.record_run(15, 50, 0)
		if int(session.best_score) != 20 or _label(menu) == "":
			return "score 15 changed the saved best"
		menu.call("_layout_personal_best")
		if _label(menu) != "PERSONAL BEST 20":
			return "score 15 updated the menu to %s" % _label(menu)
		game.set("score", 25)
		game.call("_note_personal_best")
		if not bool(game.get("_wipe_new_best")):
			return "score 25 did not mark NEW from the same best"
		session.record_run(25, 50, 0)
		menu.call("_layout_personal_best")
		if int(session.best_score) != 25 or _label(menu) != "PERSONAL BEST 25":
			return "score 25 stored %s menu %s" % [session.best_score, _label(menu)]
		var saved := ConfigFile.new()
		if saved.load(SAVE_PATH) != OK or int(saved.get_value("stats", "best_score", -1)) != 25:
			return "best 25 was not written"
		session.best_score = 0
		session._load()
		menu.call("_layout_personal_best")
		if int(session.best_score) != 25 or _label(menu) != "PERSONAL BEST 25":
			return "restart lost the menu best"
		session.best_score = 25
		session.practice_daily = true
		game.set("score", 40)
		game.call("_note_personal_best")
		session.record_run(40, 1, 0)
		menu.call("_layout_personal_best")
		if bool(game.get("_wipe_new_best")) or int(session.best_score) != 25 or _label(menu) != "PERSONAL BEST 25":
			return "practice run changed the personal best"
		session.practice_daily = false
		var heights: Array[float] = [960.0, 1080.0, 1170.0, 1200.0, 1260.0]
		var scores: Array[int] = [0, 8, 45, 250, 9999]
		for height in heights:
			var resized := await _set_portrait(height)
			if resized != "":
				return resized
			menu.call("_sync_menu_anchor")
			await get_tree().process_frame
			for value in scores:
				session.best_score = value
				menu.call("_layout_personal_best")
				var fit := _measure(menu, height, value)
				if fit != "":
					return fit
		return ""

	func _set_portrait(height: float) -> String:
		var win := get_tree().root
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
		win.content_scale_size = Vector2i(int(RR.VIEW_W), int(RR.VIEW_H))
		win.size = Vector2i(int(RR.VIEW_W), int(height))
		await get_tree().process_frame
		var visible := win.get_visible_rect().size
		if absf(visible.x - RR.VIEW_W) > 1.0 or absf(visible.y - height) > 1.0:
			return "portrait %s visible %s" % [height, visible]
		if absf(RR.screen_bottom() - height) > 1.0:
			return "portrait %s screen_bottom %s" % [height, RR.screen_bottom()]
		return ""

	func _measure(menu: Node, height: float, value: int) -> String:
		var row := _find(menu, "PersonalBest") as Control
		var text := _find(menu, "BestText") as Control
		var crown := _find(menu, "BestCrown") as Control
		if row == null or text == null or crown == null:
			return "personal best nodes missing"
		if row.mouse_filter != Control.MOUSE_FILTER_IGNORE or text.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return "personal best is clickable"
		if row is BaseButton:
			return "personal best is a button"
		var expected := "PERSONAL BEST %d" % value
		if str(text.get("_text")) != expected:
			return "height %s score %s label %s" % [height, value, text.get("_text")]
		var plate: Rect2 = menu.SCORE_PLATE
		var play: Rect2 = menu.PLAY_BOX
		var card_pos: Vector2 = menu.get("_card_pos")
		var card_scale: float = menu.get("_card_scale")
		var plate_bottom := card_pos.y + plate.end.y * card_scale
		var play_h := play.size.y * card_scale
		var fish_top := float(menu.call("_fish_icon_rest_top"))
		var fish_clip := menu.get("_fish_clip") as Control
		var expected_fish := float(menu.call("_layout_fish_y", fish_clip.size.y))
		if absf(fish_clip.position.y - expected_fish) > 0.5:
			return "fish row moved at height %s" % height
		var left := crown.position.x
		var right := crown.position.x + crown.size.x
		var top := row.position.y
		var bottom := row.position.y
		var digit_h := 0.0
		var letter_h := 0.0
		var gold := 0
		var letters := 0
		for child in text.get_children():
			var glyph := child as TextureRect
			if glyph == null or glyph.texture == null:
				continue
			var gx := text.position.x + glyph.position.x
			var gy := row.position.y + text.position.y + glyph.position.y
			left = minf(left, gx)
			right = maxf(right, gx + glyph.size.x)
			top = minf(top, gy)
			bottom = maxf(bottom, gy + glyph.size.y)
			var path := glyph.texture.resource_path
			if path.contains("num_gold"):
				gold += 1
				digit_h = maxf(digit_h, glyph.size.y)
			elif path.contains("alpha_"):
				letters += 1
				letter_h = maxf(letter_h, glyph.size.y)
		var center := (left + right) * 0.5
		print("[menu-best] h=%.0f digits=%s box_h=%.1f glyph=%.1f span=%.1f..%.1f y=%.1f..%.1f fish=%.1f plate=%.1f" % [
			height, str(value).length(), row.size.y, digit_h, left, right, top, bottom, fish_top, plate_bottom,
		])
		if letters < 12 or gold != str(value).length():
			return "height %s score %s letters %s gold %s" % [height, value, letters, gold]
		if absf(digit_h - letter_h) > 0.6:
			return "height %s score digits and label differ in size" % height
		if row.size.y > play_h * 0.4:
			return "height %s personal best is too large" % height
		if absf(center - RR.VIEW_W * 0.5) > 1.5:
			return "height %s score %s not centered (%.1f)" % [height, value, center]
		if left < 2.0 or right > RR.VIEW_W - 2.0:
			return "height %s score %s leaves the screen" % [height, value]
		if top + 0.5 < plate_bottom or bottom > fish_top + 0.5:
			return "height %s score %s overlaps the menu (y %.1f..%.1f plate %.1f fish %.1f)" % [height, value, top, bottom, plate_bottom, fish_top]
		var crown_path := ""
		var crown_rect := crown as TextureRect
		if crown_rect != null and crown_rect.texture != null:
			crown_path = crown_rect.texture.resource_path
		if not crown_path.contains("crown_gold"):
			return "missing gold crown"
		if crown.size.y > digit_h + 0.5:
			return "crown is larger than the score"
		return ""

	func _label(menu: Node) -> String:
		var text := _find(menu, "BestText")
		if text == null:
			return ""
		return str(text.get("_text"))

	func _find(node: Node, wanted: String) -> Node:
		if node == null:
			return null
		if str(node.name) == wanted:
			return node
		for child in node.get_children():
			var found := _find(child, wanted)
			if found:
				return found
		return null

	func _snapshot() -> Dictionary:
		var existed := FileAccess.file_exists(SAVE_PATH)
		var bytes := PackedByteArray()
		if existed:
			bytes = FileAccess.get_file_as_bytes(SAVE_PATH)
		var session := get_node("/root/GameSession")
		return {
			"existed": existed,
			"bytes": bytes,
			"best": int(session.best_score),
			"mode": str(session.match_mode),
			"practice": bool(session.practice_daily),
		}

	func _restore(snap: Dictionary) -> void:
		var session := get_node("/root/GameSession")
		if bool(snap["existed"]):
			var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
			if f:
				f.store_buffer(snap["bytes"])
				f.close()
			session._load()
		else:
			if FileAccess.file_exists(SAVE_PATH):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
			session.best_score = int(snap["best"])
		session.match_mode = str(snap["mode"])
		session.practice_daily = bool(snap["practice"])
