extends SceneTree

const RATIOS := [16.0 / 9.0, 18.0 / 9.0, 19.5 / 9.0, 20.0 / 9.0, 21.0 / 9.0]
const MODE_ART := Vector2(845.0, 1860.0)
const SCORE_ART := Vector2(941.0, 1672.0)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _check("portrait heights", _heights()) and ok
	ok = _check("uniform art", _uniform()) and ok
	ok = _check("safe art", _safe()) and ok
	ok = _check("gameplay constants", _constants()) and ok
	ok = _check("headless insets", _insets()) and ok
	ok = _check("android preset", _preset()) and ok
	ok = _check("keyboard lock", _keyboard()) and ok
	ok = _check("game content", _features()) and ok
	ok = _check("scripts parse", _parse()) and ok
	ok = _check("mode cover", _mode_cover()) and ok
	ok = _check("mission counters", _mission_counters()) and ok
	print("[screen-fit] ok=%s" % ok)
	quit(0 if ok else 1)


func _heights() -> bool:
	var expected := [960.0, 1080.0, 1170.0, 1200.0, 1260.0]
	for i in RATIOS.size():
		var height := RR.portrait_content_height(RATIOS[i])
		if not is_equal_approx(height, expected[i]):
			push_error("[screen-fit] ratio %s height %s expected %s" % [RATIOS[i], height, expected[i]])
			return false
		if height + 0.01 < RR.VIEW_H and i > 0:
			return false
	return is_equal_approx(RR.portrait_content_height(16.0 / 9.0), RR.VIEW_H)


func _uniform() -> bool:
	for ratio in RATIOS:
		var screen := Vector2(RR.VIEW_W, RR.portrait_content_height(ratio))
		for art in [MODE_ART, SCORE_ART]:
			var fitted := RR.uniform_fit(art, screen, Vector4.ZERO)
			if not _same_aspect(art, fitted.size):
				push_error("[screen-fit] stretched %s on %s" % [art, screen])
				return false
			if fitted.position.x < -0.01 or fitted.position.y < -0.01:
				return false
			if fitted.end.x > screen.x + 0.01 or fitted.end.y > screen.y + 0.01:
				push_error("[screen-fit] art left the screen %s -> %s" % [screen, fitted])
				return false
	return true


func _safe() -> bool:
	var screen := Vector2(RR.VIEW_W, RR.portrait_content_height(20.0 / 9.0))
	var margins := Vector4(18.0, 84.0, 18.0, 72.0)
	for art in [MODE_ART, SCORE_ART]:
		var fitted := RR.uniform_fit(art, screen, margins)
		if not _same_aspect(art, fitted.size):
			return false
		if fitted.position.x + 0.01 < margins.x or fitted.position.y + 0.01 < margins.y:
			push_error("[screen-fit] art entered the notch %s" % fitted)
			return false
		if fitted.end.x > screen.x - margins.z + 0.01 or fitted.end.y > screen.y - margins.w + 0.01:
			push_error("[screen-fit] art entered the nav bar %s" % fitted)
			return false
	return true


func _constants() -> bool:
	return (
		is_equal_approx(RR.PLAY_TOP, 53.0)
		and is_equal_approx(RR.VIEW_W, 540.0)
		and is_equal_approx(RR.VIEW_H, 960.0)
		and is_equal_approx(RR.PIPE_SPEED, 200.0)
		and is_equal_approx(RR.GAP, 211.0)
		and is_equal_approx(RR.PIPE_INTERVAL, 1.5)
		and is_equal_approx(RR.GRAVITY, 1840.0)
		and is_equal_approx(RR.FLAP, 573.0)
		and is_equal_approx(RR.PLAYER_X, 108.0)
	)


func _insets() -> bool:
	var insets := RR.display_insets(RR.screen_size())
	if insets != Vector4.ZERO:
		push_error("[screen-fit] headless insets %s" % insets)
		return false
	return is_equal_approx(RR.screen_bottom(), RR.VIEW_H)


func _preset() -> bool:
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var workflow := FileAccess.get_file_as_string("res://.github/workflows/android-build.yml")
	var ads := FileAccess.get_file_as_string("res://scripts/ads/ad_config.gd")
	if preset.is_empty() or workflow.is_empty() or ads.is_empty():
		return false
	var android_at := preset.find('name="Android"')
	if android_at < 0:
		return false
	var android := preset.substr(android_at)
	var needles := [
		'package/unique_name="com.lunarentertainment.reefrun"',
		'exclude_filter="res://tools/*,tools/*"',
		'keystore/release_password=""',
		"screen/edge_to_edge=true",
		"version/code=1",
	]
	for needle in needles:
		if not android.contains(needle):
			push_error("[screen-fit] preset missing %s" % needle)
			return false
	if not preset.contains('application/bundle_identifier="com.lunarentertainment.reefrun"'):
		return false
	if workflow.contains("GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=") and not workflow.contains("secrets.ANDROID_KEYSTORE_PASSWORD"):
		return false
	if not workflow.contains("secrets.ANDROID_KEYSTORE_BASE64"):
		return false
	if not workflow.contains("LAST_PUBLISHED_VERSION_CODE"):
		return false
	if not workflow.contains("must be greater than the last published Play version code"):
		return false
	if not workflow.contains("Google Play publishing is disabled"):
		return false
	var mode := FileAccess.get_file_as_string("res://scripts/ads/ad_build_mode.gd")
	return (
		mode.contains('const ANDROID_MODE := "test"')
		and mode.contains('const ANDROID_OUTPUT_MARKER := "REEFRUN_ANDROID_AD_MODE=test"')
		and mode.contains('const IOS_MODE := "production"')
		and ads.contains('normalize_mode(mode) != "production"')
		and ads.contains("ca-app-pub-3940256099942544/5224354917")
		and workflow.contains("default: test")
		and workflow.contains("--platform android")
	)


func _keyboard() -> bool:
	var session := FileAccess.get_file_as_string("res://autoload/game_session.gd")
	return (
		session.contains('OS.has_feature("android")')
		and session.contains("CONTENT_SCALE_ASPECT_KEEP_WIDTH")
		and session.contains("win.size = _stable_win")
		and session.contains("begin_virtual_keyboard_lock")
	)


func _features() -> bool:
	var catalog: Array = DailyMissions.catalog()
	if catalog.size() != 90 or DailyMissions.mission_by_id(90).is_empty():
		push_error("[screen-fit] mission catalog size %s" % catalog.size())
		return false
	var project := FileAccess.get_file_as_string("res://project.godot")
	if not project.contains("window/handheld/orientation=1"):
		push_error("[screen-fit] portrait orientation is not set")
		return false
	var paths := [
		"res://scripts/deep_dive/dive_overlay.gd",
		"res://scripts/backend/supabase_client.gd",
		"res://scripts/ghost_match.gd",
		"res://scripts/backend/leaderboard_repository.gd",
		"res://scripts/ads/android_rewarded_ads.gd",
		"res://assets/sfx/coin.wav",
		"res://assets/sprites/hat_00.png",
		"res://assets/sprites/hat_87.png",
	]
	for path in paths:
		if path.begins_with("res://tools/") or not FileAccess.file_exists(path):
			push_error("[screen-fit] missing game content %s" % path)
			return false
	return true


func _mode_cover() -> bool:
	var menu_script: GDScript = load("res://scenes/menu/main_menu.gd") as GDScript
	if menu_script == null:
		push_error("[screen-fit] mode menu did not load")
		return false
	var menu = menu_script.new()
	var ratios: Array[float] = [16.0 / 9.0, 18.0 / 9.0, 19.5 / 9.0, 20.0 / 9.0, 21.0 / 9.0]
	var sources: Array[Rect2] = [menu.MODE_UNLIMITED, menu.MODE_DAILY, menu.MODE_MISSIONS, menu.MODE_BACK]
	for ratio in ratios:
		var screen := Vector2(RR.VIEW_W, RR.VIEW_W * ratio)
		var cover: Rect2 = menu._mode_cover_rect(screen)
		var scale := Vector2(cover.size.x / menu.MODE_W, cover.size.y / menu.MODE_H)
		var filled: bool = cover.position.is_equal_approx(Vector2.ZERO) and cover.size.is_equal_approx(screen)
		if not filled and absf(scale.x - scale.y) > 0.0001:
			push_error("[screen-fit] mode art stretched on %s" % screen)
			return false
		if cover.position.x > 0.05 or cover.position.y > 0.05 or cover.end.x < screen.x - 0.05 or cover.end.y < screen.y - 0.05:
			push_error("[screen-fit] mode art does not cover %s with %s" % [screen, cover])
			return false
		var bounds := Rect2(Vector2.ZERO, screen)
		for src in sources:
			var button := Rect2(cover.position + src.position * scale, src.size * scale)
			if not bounds.encloses(button.grow(-1.0)):
				push_error("[screen-fit] mode button %s left %s" % [button, screen])
				return false
		var unlimited := Rect2(cover.position + menu.MODE_UNLIMITED.position * scale, menu.MODE_UNLIMITED.size * scale)
		var note := Rect2(cover.position + menu.MODE_NOTE.position * scale, menu.MODE_NOTE.size * scale)
		var missions := Rect2(cover.position + menu.MODE_MISSIONS.position * scale, menu.MODE_MISSIONS.size * scale)
		for fish in menu.daily_fish_screen_rects(cover):
			if not bounds.encloses(fish.grow(-0.5)):
				push_error("[screen-fit] daily fish %s left %s" % [fish, screen])
				return false
			if absf(fish.size.x - fish.size.y) > 0.01:
				push_error("[screen-fit] daily fish stretched %s" % fish)
				return false
			if fish.intersects(unlimited) or fish.intersects(note) or fish.intersects(missions):
				push_error("[screen-fit] daily fish overlaps another control %s" % fish)
				return false
		var score: Rect2 = RR.fullscreen_plate(Vector2(menu.SCORE_W, menu.SCORE_H), screen, menu.SCORE_KEEP, Vector2(0.5, 0.5))
		if score.position.x > 0.05 or score.end.x < screen.x - 0.05 or score.end.y < screen.y - 0.05:
			push_error("[screen-fit] leaderboard does not cover %s with %s" % [screen, score])
			return false
	menu.free()
	return true


func _parse() -> bool:
	var paths := [
		"res://scenes/menu/main_menu.gd",
		"res://scenes/game/hud.gd",
		"res://scenes/game/game.gd",
		"res://scripts/deep_dive/dive_overlay.gd",
		"res://scripts/rr.gd",
	]
	for path in paths:
		if load(path) == null:
			push_error("[screen-fit] could not load %s" % path)
			return false
	return true


func _mission_counters() -> bool:
	var Overlay = load("res://scripts/daily_missions_overlay.gd")
	var capsule_right: Array[float] = [516.0, 514.0, 506.0]
	var plate_left: Array[float] = [664.0, 653.0, 653.0]
	var capsule_mid: Array[float] = [780.5, 940.0, 1097.5]
	var samples: PackedStringArray = PackedStringArray([
		"0/2", "1/2", "2/2", "0/10", "9/10", "10/10", "90/90", "40/100", "200/200", "500/500",
	])
	var overlay = Overlay.new()
	overlay.use_screen_board()
	root.add_child(overlay)
	var board := {
		"ok": true,
		"slots": [
			{"slot": "easy", "mission_id": 50, "description": "Enter 2 dives.", "goal": 2, "progress": 0, "reward": 5, "complete": false, "claimed": false},
			{"slot": "medium", "mission_id": 1, "description": "Pass 10 pipes.", "goal": 10, "progress": 0, "reward": 10, "complete": false, "claimed": false},
			{"slot": "hard", "mission_id": 32, "description": "Pass 200 pipes.", "goal": 200, "progress": 0, "reward": 20, "complete": false, "claimed": false},
		],
		"bonus": {"reward": 25, "unlocked": false, "claimed": false},
	}
	overlay.present("board", true)
	overlay.show_board(board, "")
	var counters: Array = overlay.get("_counters")
	if counters.size() != 3:
		push_error("[screen-fit] expected 3 mission counters")
		overlay.free()
		return false
	var homes: Array[Rect2] = []
	var glyph_h := -1.0
	for i in counters.size():
		var counter: Control = counters[i]
		var box := Rect2(counter.position, counter.size)
		homes.append(box)
		if counter.clip_contents:
			push_error("[screen-fit] counter %d clips its digits" % i)
			overlay.free()
			return false
		if box.size.x < 110.0 or box.size.y < 24.0:
			push_error("[screen-fit] counter %d box is too small %s" % [i, box])
			overlay.free()
			return false
		if box.position.x < capsule_right[i] + 6.0 or box.end.x > plate_left[i] - 6.0:
			push_error("[screen-fit] counter %d leaves the gap %s" % [i, box])
			overlay.free()
			return false
		if absf(box.position.y + box.size.y * 0.5 - capsule_mid[i]) > 1.5:
			push_error("[screen-fit] counter %d is not centered on its bar" % i)
			overlay.free()
			return false
		if box.intersects(Overlay.SCREEN_TRACK[i]) or box.intersects(Overlay.SCREEN_DESC[i]) or box.intersects(Overlay.SCREEN_REWARD[i]):
			push_error("[screen-fit] counter %d overlaps the row art" % i)
			overlay.free()
			return false
		var height := float(counter.get("_glyph_h"))
		if glyph_h < 0.0:
			glyph_h = height
		elif absf(height - glyph_h) > 0.1:
			push_error("[screen-fit] counter sizes differ")
			overlay.free()
			return false
	for sample in samples:
		for i in counters.size():
			var counter: Control = counters[i]
			counter.set_value(sample)
			if str(counter.get("_text")) != sample:
				push_error("[screen-fit] counter %d shows %s" % [i, counter.get("_text")])
				overlay.free()
				return false
			if not Rect2(counter.position, counter.size).is_equal_approx(homes[i]):
				push_error("[screen-fit] counter %d moved for %s" % [i, sample])
				overlay.free()
				return false
			if counter.get_child_count() < 3:
				push_error("[screen-fit] counter %d drew no digits for %s" % [i, sample])
				overlay.free()
				return false
			for child in counter.get_children():
				var glyph := child as Control
				if glyph.position.x < 3.0 or glyph.position.y < 3.0:
					push_error("[screen-fit] %s row %d glyph starts at %s" % [sample, i, glyph.position])
					overlay.free()
					return false
				if glyph.position.x + glyph.size.x > counter.size.x - 3.0 or glyph.position.y + glyph.size.y > counter.size.y - 3.0:
					push_error("[screen-fit] %s row %d glyph ends at %s in %s" % [sample, i, glyph.position + glyph.size, counter.size])
					overlay.free()
					return false
	overlay.present("hidden", true)
	overlay.present("board", true)
	for i in counters.size():
		var counter: Control = counters[i]
		if not Rect2(counter.position, counter.size).is_equal_approx(homes[i]):
			push_error("[screen-fit] counter %d moved after reopen" % i)
			overlay.free()
			return false
	var phones := [
		{"screen": Vector2(390, 844), "margins": Vector4(0, 47, 0, 34)},
		{"screen": Vector2(360, 780), "margins": Vector4(0, 44, 0, 30)},
		{"screen": Vector2(540, 960), "margins": Vector4(0, 0, 0, 0)},
		{"screen": Vector2(540, 1080), "margins": Vector4(0, 0, 0, 0)},
		{"screen": Vector2(540, 1170), "margins": Vector4(0, 0, 0, 0)},
		{"screen": Vector2(540, 1260), "margins": Vector4(0, 0, 0, 0)},
	]
	for phone in phones:
		var screen: Vector2 = phone.screen
		var placed: Rect2 = Overlay.screen_board_rect(screen, phone.margins)
		var fit: float = placed.size.x / Overlay.SCREEN_SIZE.x
		for i in homes.size():
			var on_screen := Rect2(placed.position + homes[i].position * fit, homes[i].size * fit)
			if not placed.encloses(on_screen):
				push_error("[screen-fit] counter %d leaves %s at %s" % [i, screen, on_screen])
				overlay.free()
				return false
			if on_screen.size.y * (glyph_h / homes[i].size.y) < 8.0:
				push_error("[screen-fit] counter %d is unreadably small on %s" % [i, screen])
				overlay.free()
				return false
	overlay.free()
	return true


func _same_aspect(art: Vector2, size: Vector2) -> bool:
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	return absf(size.x / size.y - art.x / art.y) < 0.001


func _check(name: String, passed: bool) -> bool:
	if not passed:
		push_error("[screen-fit] failed %s" % name)
	return passed
