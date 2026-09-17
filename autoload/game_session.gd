extends Node

var fish_index: int = 0
var player_name: String = ""
var course_seed: int = 0
var last_score: int = 0
var last_rank: int = 100
var last_alive_at_death: int = 99
var best_score: int = 0
var best_rank: int = 100
var games_played: int = 0
var weekly: Array = []
var monthly: Array = []
var week_key: String = ""
var month_key: String = ""
var web_display := ""

const CourseBuilderScript := preload("res://scripts/course_builder.gd")
const SAVE_PATH := "user://reefrun.cfg"
# Local ghost testing: Continue / Play reuse the last course so recorded fish replay.
# Set false for production so each match gets a new seed.
const DEV_REUSE_COURSE_SEED := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 0
	_apply_phone_aspect()
	_capture_web_display()
	if OS.has_feature("editor"):
		_bind_reload()
		CourseBuilderScript.validate_determinism(827361)
		CourseBuilderScript.validate_determinism(1)
	_load()
	refresh_boards()


func _apply_phone_aspect() -> void:
	var win := get_window()
	win.content_scale_size = Vector2i(int(RR.VIEW_W), int(RR.VIEW_H))
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	win.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	if OS.has_feature("web"):
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var preview := Vector2i(int(RR.VIEW_W), int(RR.VIEW_H))
		DisplayServer.window_set_size(preview)
		var screen := DisplayServer.screen_get_usable_rect()
		var origin := screen.position + (screen.size - preview) / 2
		DisplayServer.window_set_position(origin)


func _capture_web_display() -> void:
	var win := get_window()
	web_display = "inner=%s scale_size=%s content_scale=%.3f screen=%d refresh=%.1f dpi=%d" % [
		str(win.size),
		str(win.content_scale_size),
		win.content_scale_factor,
		DisplayServer.window_get_current_screen(),
		DisplayServer.screen_get_refresh_rate(),
		DisplayServer.screen_get_dpi(),
	]
	if not OS.has_feature("web"):
		return
	var dpr: Variant = JavaScriptBridge.eval("window.devicePixelRatio")
	var inner_w: Variant = JavaScriptBridge.eval("window.innerWidth")
	var inner_h: Variant = JavaScriptBridge.eval("window.innerHeight")
	var css_w: Variant = JavaScriptBridge.eval("(function(){var c=document.getElementById('canvas');return c?c.clientWidth:0;})()")
	var css_h: Variant = JavaScriptBridge.eval("(function(){var c=document.getElementById('canvas');return c?c.clientHeight:0;})()")
	var back_w: Variant = JavaScriptBridge.eval("(function(){var c=document.getElementById('canvas');return c?c.width:0;})()")
	var back_h: Variant = JavaScriptBridge.eval("(function(){var c=document.getElementById('canvas');return c?c.height:0;})()")
	web_display = "dpr=%s inner=%sx%s css=%sx%s backing=%sx%s godot_win=%s" % [
		str(dpr), str(inner_w), str(inner_h), str(css_w), str(css_h), str(back_w), str(back_h), str(win.size)
	]


func _bind_reload() -> void:
	if InputMap.has_action("dev_reload"):
		return
	InputMap.add_action("dev_reload")
	var f5 := InputEventKey.new()
	f5.physical_keycode = KEY_F5
	InputMap.action_add_event("dev_reload", f5)
	var ctrl_r := InputEventKey.new()
	ctrl_r.physical_keycode = KEY_R
	ctrl_r.ctrl_pressed = true
	InputMap.action_add_event("dev_reload", ctrl_r)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dev_reload"):
		get_tree().paused = false
		OS.set_restart_on_exit(true)
		get_tree().quit()


func selected_fish() -> String:
	return RR.FISH_IDS[fish_index]


func start_match() -> void:
	if not (DEV_REUSE_COURSE_SEED and course_seed != 0):
		course_seed = randi()
		if course_seed == 0:
			course_seed = 1
	last_score = 0
	last_rank = RR.GHOST_COUNT + 1
	last_alive_at_death = RR.GHOST_COUNT
	games_played += 1
	_save()


func record_run(score: int, rank: int, alive_at_death: int) -> void:
	last_score = score
	last_rank = rank
	last_alive_at_death = alive_at_death
	if score > best_score:
		best_score = score
	if rank < best_rank:
		best_rank = rank
	refresh_boards()
	var name := player_name.strip_edges().to_upper()
	if name.is_empty():
		name = "YOU"
	_upsert(weekly, name, score)
	_upsert(monthly, name, score)
	_save()


func refresh_boards() -> bool:
	var wk := current_week_key()
	var mk := current_month_key()
	var changed := false
	if wk != week_key:
		week_key = wk
		weekly.clear()
		changed = true
	if mk != month_key:
		month_key = mk
		monthly.clear()
		changed = true
	if changed:
		_save()
	return changed


func current_week_key() -> String:
	var now := Time.get_datetime_dict_from_system()
	var back := (int(now.weekday) + 6) % 7
	var monday := _shift_date(int(now.year), int(now.month), int(now.day), -back)
	return "%04d-%02d-%02d" % [monday.year, monday.month, monday.day]


func current_month_key() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d-%02d" % [int(now.year), int(now.month)]


func _shift_date(year: int, month: int, day: int, delta: int) -> Dictionary:
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": year,
		"month": month,
		"day": day,
		"hour": 12,
		"minute": 0,
		"second": 0,
	})
	return Time.get_datetime_dict_from_unix_time(unix + delta * 86400)


func _upsert(board: Array, name: String, score: int) -> void:
	if score <= 0:
		return
	for entry in board:
		if str(entry.get("name", "")) == name:
			if score > int(entry.get("score", 0)):
				entry["score"] = score
			_sort_board(board)
			return
	board.append({"name": name, "score": score})
	_sort_board(board)
	if board.size() > 10:
		board.resize(10)


func _sort_board(board: Array) -> void:
	board.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0))
	)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	fish_index = int(cfg.get_value("player", "fish", 0))
	player_name = str(cfg.get_value("player", "name", ""))
	best_score = int(cfg.get_value("stats", "best_score", 0))
	best_rank = int(cfg.get_value("stats", "best_rank", 100))
	games_played = int(cfg.get_value("stats", "games", 0))
	course_seed = int(cfg.get_value("match", "course_seed", 0))
	week_key = str(cfg.get_value("boards", "week_key", ""))
	month_key = str(cfg.get_value("boards", "month_key", ""))
	weekly = _decode_board(cfg.get_value("boards", "weekly", PackedStringArray()))
	monthly = _decode_board(cfg.get_value("boards", "monthly", PackedStringArray()))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "fish", fish_index)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("stats", "best_score", best_score)
	cfg.set_value("stats", "best_rank", best_rank)
	cfg.set_value("stats", "games", games_played)
	cfg.set_value("match", "course_seed", course_seed)
	cfg.set_value("boards", "week_key", week_key)
	cfg.set_value("boards", "month_key", month_key)
	cfg.set_value("boards", "weekly", _encode_board(weekly))
	cfg.set_value("boards", "monthly", _encode_board(monthly))
	cfg.save(SAVE_PATH)


func _encode_board(board: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in board:
		out.append("%s\t%d" % [str(entry.get("name", "")), int(entry.get("score", 0))])
	return out


func _decode_board(raw: Variant) -> Array:
	var board: Array = []
	if raw is PackedStringArray:
		for line in raw:
			var parts := String(line).split("\t")
			if parts.size() < 2:
				continue
			board.append({"name": parts[0], "score": int(parts[1])})
	_sort_board(board)
	if board.size() > 10:
		board.resize(10)
	return board
