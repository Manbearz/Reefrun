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
	return ads.contains("const USE_TEST_ADS := true") and ads.contains("ca-app-pub-3940256099942544/5224354917")


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


func _same_aspect(art: Vector2, size: Vector2) -> bool:
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	return absf(size.x / size.y - art.x / art.y) < 0.001


func _check(name: String, passed: bool) -> bool:
	if not passed:
		push_error("[screen-fit] failed %s" % name)
	return passed
