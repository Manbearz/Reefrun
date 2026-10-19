extends Node

const NAME_MAX_LEN := 7

const MODE_UNLIMITED := "unlimited"
const MODE_DAILY := "daily"

var fish_index: int = 0
var coins: int = 0
var owned_fish: PackedInt32Array = PackedInt32Array()
var hat_index: int = -1
var owned_hats: PackedInt32Array = PackedInt32Array()
var player_name: String = ""
var player_id: String = ""
var course_seed: int = 0
var match_mode: String = ""
var practice_daily: bool = false
var active_challenge: Dictionary = {}
var pending_finalize_attempt: String = ""
var pending_finalize_score: int = 0
var pending_finalize_name: String = ""
var pending_unlimited_score: int = 0
var pending_unlimited_name: String = ""
var pending_claim_key: String = ""
var pending_referral_code: String = ""
var pending_first_run: bool = false
var share_run_synced: bool = false
var applied_share_reward_coins: int = 0
var pending_mission_runs: Array = []
var applied_mission_reward_coins: int = 0
var mission_board: Dictionary = {}
var referral_code: String = ""
var share_reward_qualified: int = 0
var last_score: int = 0
var last_rank: int = 100
var last_alive_at_death: int = 99
var best_score: int = 0
var best_rank: int = 100
var games_played: int = 0
var daily: Array = []
var weekly: Array = []
var monthly: Array = []
var day_key: String = ""
var week_key: String = ""
var month_key: String = ""
var web_display := ""
var _vk_lock := false
var _vk_restoring := false
var _stable_win := Vector2i.ZERO
var _practice_saved_seed := 0

const CourseBuilderScript := preload("res://scripts/course_builder.gd")
const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")
const DailyAttemptScript := preload("res://scripts/daily_attempt.gd")
const DailyTestModeScript := preload("res://scripts/daily_test_mode.gd")
const ReferralRulesScript := preload("res://scripts/share/referral_rules.gd")
const DailyMissionsScript := preload("res://scripts/daily_missions.gd")
const ReferralLinksScript := preload("res://scripts/share/referral_links.gd")
const ConfigScript := preload("res://scripts/backend/supabase_config.gd")
const SAVE_PATH := "user://reefrun.cfg"
# iPhone 14/15/16 logical points. Editor play only; exported desktop stays 540x960.
const EDITOR_PREVIEW_SIZE := Vector2i(393, 852)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 0
	_apply_phone_aspect()
	get_window().size_changed.connect(_lock_content_scale)
	_lock_web_page_zoom()
	_capture_web_display()
	if OS.has_feature("editor"):
		_bind_reload()
		CourseBuilderScript.validate_determinism(827361)
		CourseBuilderScript.validate_determinism(1)
	_load()
	if _ensure_player_id():
		_save()
	var incoming := ReferralLinksScript.capture()
	if incoming != "":
		remember_referral_code(incoming)
	refresh_boards()


func _phone_web() -> bool:
	return OS.has_feature("web") or OS.has_feature("mobile") or OS.has_feature("ios") or OS.has_feature("android")


func _editor_phone_preview() -> bool:
	return OS.has_feature("editor")


func _apply_content_scale(win: Window) -> void:
	win.content_scale_size = Vector2i(int(RR.VIEW_W), int(RR.VIEW_H))
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	if _phone_web() or _editor_phone_preview():
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
	else:
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP


func _apply_phone_aspect() -> void:
	var win := get_window()
	_apply_content_scale(win)
	_stable_win = win.size
	if _phone_web():
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var preview := EDITOR_PREVIEW_SIZE if _editor_phone_preview() else Vector2i(int(RR.VIEW_W), int(RR.VIEW_H))
		DisplayServer.window_set_size(preview)
		var screen := DisplayServer.screen_get_usable_rect()
		var origin := screen.position + (screen.size - preview) / 2
		DisplayServer.window_set_position(origin)
		_stable_win = preview


func _lock_content_scale() -> void:
	if _vk_restoring:
		return
	var win := get_window()
	var now := win.size
	if _vk_lock and _stable_win != Vector2i.ZERO:
		if absi(now.x - _stable_win.x) > 48:
			_vk_lock = false
			_stable_win = now
			_web_vk_eval("window.reefrunVkUnlock && window.reefrunVkUnlock();")
		elif now != _stable_win:
			_vk_restoring = true
			win.size = _stable_win
			_vk_restoring = false
			_apply_content_scale(win)
			return
	elif not _vk_lock:
		_stable_win = now
	_apply_content_scale(win)


func begin_virtual_keyboard_lock() -> void:
	if not _phone_web():
		return
	var win := get_window()
	if not _vk_lock:
		_stable_win = win.size
	_vk_lock = true
	_web_vk_eval("window.reefrunVkLock && window.reefrunVkLock();")


func end_virtual_keyboard_lock() -> void:
	if not _vk_lock:
		return
	_vk_lock = false
	_web_vk_eval("window.reefrunVkUnlock && window.reefrunVkUnlock();")


func _web_vk_eval(code: String) -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	Engine.get_singleton("JavaScriptBridge").eval(code, true)


func _lock_web_page_zoom() -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	Engine.get_singleton("JavaScriptBridge").eval(
		"""
		(function(){
			if (window.__reefrunVkInstalled) return;
			window.__reefrunVkInstalled = true;
			var locked = false;
			var layoutW = window.innerWidth;
			var layoutH = window.innerHeight;
			var watchRaf = 0;

			function canvasEl(){ return document.getElementById('canvas'); }
			function isText(el){
				if (!el) return false;
				var tag = (el.tagName || '').toLowerCase();
				return tag === 'input' || tag === 'textarea' || !!el.isContentEditable;
			}
			function bumpInputFont(el){
				if (!isText(el)) return;
				el.style.setProperty('font-size', '16px', 'important');
				el.style.setProperty('line-height', 'normal', 'important');
				el.style.setProperty('transform', 'none', 'important');
			}
			function captureLayout(){
				layoutW = window.innerWidth;
				layoutH = window.innerHeight;
			}
			function applyCanvasLayout(){
				var c = canvasEl();
				if (!c) return;
				c.style.width = layoutW + 'px';
				c.style.height = layoutH + 'px';
				c.style.top = '0px';
				c.style.left = '0px';
				c.style.position = c.style.position || 'absolute';
			}
			function watch(){
				watchRaf = 0;
				if (!locked) return;
				applyCanvasLayout();
				watchRaf = window.requestAnimationFrame(watch);
			}
			window.reefrunVkLock = function(){
				if (!locked) captureLayout();
				locked = true;
				applyCanvasLayout();
				if (!watchRaf) watchRaf = window.requestAnimationFrame(watch);
			};
			window.reefrunVkUnlock = function(){
				locked = false;
				if (watchRaf) {
					window.cancelAnimationFrame(watchRaf);
					watchRaf = 0;
				}
			};
			function onResize(e){
				if (!locked) {
					captureLayout();
					return;
				}
				if (Math.abs(window.innerWidth - layoutW) > 48) {
					window.reefrunVkUnlock();
					captureLayout();
					return;
				}
				e.stopImmediatePropagation();
				applyCanvasLayout();
			}
			window.addEventListener('resize', onResize, true);
			if (window.visualViewport) {
				window.visualViewport.addEventListener('resize', function(e){
					if (!locked) return;
					if (Math.abs(window.innerWidth - layoutW) > 48) {
						window.reefrunVkUnlock();
						return;
					}
					e.stopImmediatePropagation();
					applyCanvasLayout();
				}, true);
			}
			document.addEventListener('focusin', function(e){
				bumpInputFont(e.target);
				if (isText(e.target)) window.reefrunVkLock();
			}, true);
			document.addEventListener('focusout', function(e){
				if (!isText(e.target)) return;
				window.setTimeout(function(){
					if (!isText(document.activeElement)) window.reefrunVkUnlock();
				}, 50);
			}, true);
			var meta = document.querySelector('meta[name="viewport"]');
			if (!meta) {
				meta = document.createElement('meta');
				meta.name = 'viewport';
				document.head.appendChild(meta);
			}
			meta.setAttribute('content', 'width=device-width, initial-scale=1.0, viewport-fit=cover, interactive-widget=overlays-content');
			if (!document.getElementById('reefrun-vk-style')) {
				var style = document.createElement('style');
				style.id = 'reefrun-vk-style';
				style.textContent = 'html,body{margin:0;overflow:hidden;}canvas{touch-action:none;}input,textarea,[contenteditable]{font-size:16px !important;}';
				document.head.appendChild(style);
			}
			var obs = new MutationObserver(function(muts){
				for (var i = 0; i < muts.length; i++) {
					var nodes = muts[i].addedNodes;
					for (var j = 0; j < nodes.length; j++) {
						var n = nodes[j];
						if (!n || n.nodeType !== 1) continue;
						bumpInputFont(n);
						if (n.querySelectorAll) {
							var list = n.querySelectorAll('input,textarea');
							for (var k = 0; k < list.length; k++) bumpInputFont(list[k]);
						}
					}
				}
			});
			obs.observe(document.documentElement, {childList:true, subtree:true});
			var canvas = canvasEl();
			if (canvas) {
				canvas.style.touchAction = 'none';
				canvas.style.userSelect = 'none';
				canvas.style.webkitUserSelect = 'none';
				canvas.style.webkitTouchCallout = 'none';
			}
			captureLayout();
		})();
		""",
		true
	)


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
	var index := clampi(fish_index, 0, RR.FISH_IDS.size() - 1)
	return RR.FISH_IDS[index]


func owns_fish(index: int) -> bool:
	if index < 0 or index >= RR.FISH_IDS.size():
		return false
	if index < RR.FREE_FISH:
		return true
	for owned in owned_fish:
		if owned == index:
			return true
	return false


func buy_fish(index: int) -> bool:
	if index < 0 or index >= RR.FISH_IDS.size():
		return false
	if owns_fish(index):
		fish_index = index
		_save()
		return true
	var price := RR.fish_price(index)
	if coins < price:
		return false
	coins -= price
	owned_fish.append(index)
	fish_index = index
	_save()
	return true


func owns_hat(index: int) -> bool:
	if index < 0:
		return false
	for owned in owned_hats:
		if owned == index:
			return true
	return false


func add_coins(amount: int = 1) -> void:
	coins = maxi(0, coins + amount)
	_save()


func buy_hat(index: int) -> bool:
	if index < 0 or index >= RR.HAT_COUNT:
		return false
	if owns_hat(index):
		equip_hat(index)
		return true
	var price := RR.hat_price(index)
	if coins < price:
		return false
	coins -= price
	owned_hats.append(index)
	equip_hat(index)
	_save()
	return true


func equip_hat(index: int) -> void:
	if index < 0:
		hat_index = -1
		_save()
		return
	if not owns_hat(index):
		return
	hat_index = index
	_save()


func clamp_player_name(value: String) -> String:
	return value.strip_edges().substr(0, NAME_MAX_LEN)


func visible_player_name() -> String:
	var name := clamp_player_name(player_name).to_upper()
	if name.is_empty():
		return "GUEST"
	return name


func is_local_player_id(id: String = "") -> bool:
	var check := player_id if id.is_empty() else id
	return check.is_empty() or check.begins_with("local_")


func adopt_supabase_id(id: String) -> bool:
	var uid := id.strip_edges()
	if uid.is_empty() or uid.begins_with("local_"):
		return false
	player_id = uid
	_save()
	return true


func ensure_local_fallback_id() -> void:
	if not is_local_player_id():
		return
	if player_id.is_empty():
		player_id = "local_%d_%d" % [Time.get_unix_time_from_system(), randi()]
		_save()


func _ensure_player_id() -> bool:
	if not player_id.is_empty():
		return false
	if ConfigScript.is_configured():
		return false
	player_id = "local_%d_%d" % [Time.get_unix_time_from_system(), randi()]
	return true


func start_match(mode: String = "") -> void:
	end_practice_daily()
	var picked := mode if mode != "" else match_mode
	if picked == MODE_DAILY:
		push_warning("[rpc] claim_daily_attempt status=0 error=start_without_claim")
		return
	picked = MODE_UNLIMITED
	match_mode = picked
	var seed := randi()
	if seed == 0:
		seed = 1
	active_challenge = {
		"mode": MODE_UNLIMITED,
		"challenge_id": "",
		"course_seed": seed,
		"server_confirmed": false,
	}
	course_seed = seed
	last_score = 0
	last_rank = RR.GHOST_COUNT + 1
	last_alive_at_death = RR.GHOST_COUNT
	games_played += 1
	_save()


func begin_practice_daily(challenge: Dictionary) -> bool:
	if not DailyTestModeScript.enabled():
		return false
	var course := DailyTestModeScript.practice_course(challenge)
	if int(course.get("course_seed", 0)) == 0 or str(course.get("challenge_id", "")) == "":
		return false
	if not practice_daily:
		_practice_saved_seed = course_seed
	practice_daily = true
	match_mode = MODE_DAILY
	commit_match_challenge(course)
	return true


func end_practice_daily() -> void:
	if not practice_daily:
		return
	practice_daily = false
	match_mode = MODE_UNLIMITED
	active_challenge = {}
	course_seed = _practice_saved_seed


func is_practice_daily() -> bool:
	return practice_daily and match_mode == MODE_DAILY


func begin_claimed_daily(challenge: Dictionary) -> void:
	end_practice_daily()
	if str(challenge.get("attempt_id", "")).strip_edges() == "":
		push_warning("[rpc] claim_daily_attempt status=0 error=missing_attempt")
		return
	match_mode = MODE_DAILY
	commit_match_challenge(challenge)
	clear_claim_key()
	last_score = 0
	last_rank = RR.GHOST_COUNT + 1
	last_alive_at_death = RR.GHOST_COUNT
	games_played += 1
	_save()


func ensure_challenge() -> void:
	if match_mode == MODE_DAILY:
		return
	if match_mode == MODE_UNLIMITED and course_seed != 0:
		return
	start_match(MODE_UNLIMITED)


func commit_match_challenge(challenge: Dictionary) -> void:
	active_challenge = challenge.duplicate(true)
	course_seed = int(active_challenge.get("course_seed", 0))
	if course_seed == 0:
		course_seed = 1
		active_challenge["course_seed"] = course_seed


func current_challenge() -> Dictionary:
	return active_challenge


func current_challenge_id() -> String:
	return str(active_challenge.get("challenge_id", ""))


func preview_next_challenge(candidate: Dictionary) -> Dictionary:
	return candidate.duplicate(true)


func _next_challenge() -> Dictionary:
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_method("challenge_for_new_match"):
		var got: Variant = backend.challenge_for_new_match()
		if typeof(got) == TYPE_DICTIONARY and int(got.get("course_seed", 0)) != 0:
			return got
	return DailyChallengeScript.unverified_local(int(Time.get_unix_time_from_system()))


func record_run(score: int, rank: int, alive_at_death: int) -> void:
	if practice_daily:
		return
	last_score = score
	last_rank = rank
	last_alive_at_death = alive_at_death
	if score > best_score:
		best_score = score
	if rank < best_rank:
		best_rank = rank
	refresh_boards()
	var name := visible_player_name()
	_upsert(daily, name, score)
	_upsert(weekly, name, score)
	_upsert(monthly, name, score)
	if not share_run_synced:
		pending_first_run = true
	_save()
	var backend := get_node_or_null("/root/Backend")
	var attempt_id := str(active_challenge.get("attempt_id", "")).strip_edges()
	if DailyAttemptScript.should_finalize(match_mode, attempt_id):
		remember_pending_finalize(attempt_id, score, name)
		if backend and backend.has_method("finalize_daily_attempt"):
			backend.finalize_daily_attempt(attempt_id, score, name)
		return
	if match_mode == MODE_DAILY:
		push_warning("[rpc] finalize_daily_attempt status=0 error=no_attempt")
		return
	if match_mode != MODE_UNLIMITED or score <= 0:
		return
	remember_pending_unlimited(score, name)
	if backend and backend.has_method("submit_unlimited_score"):
		backend.submit_unlimited_score(score, name)


func refresh_boards() -> bool:
	var dk := current_day_key()
	var wk := current_week_key()
	var mk := current_month_key()
	var changed := false
	if dk != day_key:
		day_key = dk
		daily.clear()
		changed = true
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


func current_day_key() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [int(now.year), int(now.month), int(now.day)]


func current_week_key() -> String:
	var now := Time.get_datetime_dict_from_system()
	var back := (int(now.weekday) + 6) % 7
	var monday := _shift_date(int(now.year), int(now.month), int(now.day), -back)
	return "%04d-%02d-%02d" % [monday.year, monday.month, monday.day]


func current_month_key() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d-%02d" % [int(now.year), int(now.month)]


func _decode_json_array(text: String) -> Array:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_ARRAY:
		return parsed
	return []


func _decode_json_dict(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


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
	owned_fish = PackedInt32Array()
	var raw_fish: Variant = cfg.get_value("player", "owned_fish", PackedInt32Array())
	if raw_fish is PackedInt32Array:
		owned_fish = raw_fish
	elif raw_fish is Array:
		for v in raw_fish:
			owned_fish.append(int(v))
	fish_index = clampi(fish_index, 0, RR.FISH_IDS.size() - 1)
	if not owns_fish(fish_index):
		fish_index = 0
	player_name = clamp_player_name(str(cfg.get_value("player", "name", "")))
	player_id = str(cfg.get_value("player", "player_id", ""))
	coins = int(cfg.get_value("player", "coins", 0))
	hat_index = int(cfg.get_value("player", "hat", -1))
	owned_hats = PackedInt32Array()
	var raw_hats: Variant = cfg.get_value("player", "owned_hats", PackedInt32Array())
	if raw_hats is PackedInt32Array:
		owned_hats = raw_hats
	elif raw_hats is Array:
		for v in raw_hats:
			owned_hats.append(int(v))
	if hat_index >= 0 and not owns_hat(hat_index):
		hat_index = -1
	best_score = int(cfg.get_value("stats", "best_score", 0))
	best_rank = int(cfg.get_value("stats", "best_rank", 100))
	games_played = int(cfg.get_value("stats", "games", 0))
	course_seed = int(cfg.get_value("match", "course_seed", 0))
	day_key = str(cfg.get_value("boards", "day_key", ""))
	week_key = str(cfg.get_value("boards", "week_key", ""))
	month_key = str(cfg.get_value("boards", "month_key", ""))
	daily = _decode_board(cfg.get_value("boards", "daily", PackedStringArray()))
	weekly = _decode_board(cfg.get_value("boards", "weekly", PackedStringArray()))
	monthly = _decode_board(cfg.get_value("boards", "monthly", PackedStringArray()))
	pending_finalize_attempt = str(cfg.get_value("pending", "attempt_id", "")).strip_edges()
	pending_finalize_score = int(cfg.get_value("pending", "score", 0))
	pending_finalize_name = str(cfg.get_value("pending", "name", ""))
	pending_unlimited_score = int(cfg.get_value("pending", "unlimited_score", 0))
	pending_unlimited_name = str(cfg.get_value("pending", "unlimited_name", ""))
	pending_claim_key = str(cfg.get_value("pending", "claim_key", "")).strip_edges()
	pending_referral_code = ReferralRulesScript.normalize_code(str(cfg.get_value("share", "pending_code", "")))
	pending_first_run = bool(cfg.get_value("share", "pending_run", false))
	share_run_synced = bool(cfg.get_value("share", "run_synced", false))
	applied_share_reward_coins = int(cfg.get_value("share", "applied_reward", 0))
	referral_code = ReferralRulesScript.normalize_code(str(cfg.get_value("share", "code", "")))
	share_reward_qualified = int(cfg.get_value("share", "qualified", 0))
	pending_mission_runs = _decode_json_array(str(cfg.get_value("missions", "pending", "[]")))
	applied_mission_reward_coins = int(cfg.get_value("missions", "applied", 0))
	mission_board = _decode_json_dict(str(cfg.get_value("missions", "board", "{}")))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "fish", fish_index)
	cfg.set_value("player", "owned_fish", owned_fish)
	cfg.set_value("player", "name", player_name)
	var id_to_store := player_id
	if id_to_store.is_empty():
		var prev := ConfigFile.new()
		if prev.load(SAVE_PATH) == OK:
			var existing := str(prev.get_value("player", "player_id", ""))
			if not existing.is_empty() and not existing.begins_with("local_"):
				id_to_store = existing
				player_id = existing
	cfg.set_value("player", "player_id", id_to_store)
	cfg.set_value("player", "coins", coins)
	cfg.set_value("player", "hat", hat_index)
	cfg.set_value("player", "owned_hats", owned_hats)
	cfg.set_value("stats", "best_score", best_score)
	cfg.set_value("stats", "best_rank", best_rank)
	cfg.set_value("stats", "games", games_played)
	cfg.set_value("match", "course_seed", course_seed)
	cfg.set_value("boards", "day_key", day_key)
	cfg.set_value("boards", "week_key", week_key)
	cfg.set_value("boards", "month_key", month_key)
	cfg.set_value("boards", "daily", _encode_board(daily))
	cfg.set_value("boards", "weekly", _encode_board(weekly))
	cfg.set_value("boards", "monthly", _encode_board(monthly))
	cfg.set_value("pending", "attempt_id", pending_finalize_attempt)
	cfg.set_value("pending", "score", pending_finalize_score)
	cfg.set_value("pending", "name", pending_finalize_name)
	cfg.set_value("pending", "unlimited_score", pending_unlimited_score)
	cfg.set_value("pending", "unlimited_name", pending_unlimited_name)
	cfg.set_value("pending", "claim_key", pending_claim_key)
	cfg.set_value("share", "pending_code", pending_referral_code)
	cfg.set_value("share", "pending_run", pending_first_run)
	cfg.set_value("share", "run_synced", share_run_synced)
	cfg.set_value("share", "applied_reward", applied_share_reward_coins)
	cfg.set_value("share", "code", referral_code)
	cfg.set_value("share", "qualified", share_reward_qualified)
	cfg.set_value("missions", "pending", JSON.stringify(pending_mission_runs))
	cfg.set_value("missions", "applied", applied_mission_reward_coins)
	cfg.set_value("missions", "board", JSON.stringify(mission_board))
	cfg.save(SAVE_PATH)


func remember_referral_code(code: String) -> bool:
	var clean := ReferralRulesScript.normalize_code(code)
	if clean.is_empty() or pending_referral_code != "":
		return false
	pending_referral_code = clean
	_save()
	return true


func remember_mission_run(run_id: String, pipes: int, seconds: int, gameplay_coins: int) -> void:
	if not DailyMissionsScript.should_report(match_mode, practice_daily):
		return
	if not DailyMissionsScript.valid_run_id(run_id) or not DailyMissionsScript.accept_run(pipes, seconds, gameplay_coins):
		push_warning("[missions] run not counted pipes=%d seconds=%d coins=%d" % [pipes, seconds, gameplay_coins])
		return
	var queued: Array = DailyMissionsScript.enqueue(pending_mission_runs, run_id, pipes, seconds, gameplay_coins)
	if queued == pending_mission_runs:
		return
	pending_mission_runs = queued
	_save()
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_method("flush_daily_missions"):
		backend.flush_daily_missions()


func drop_mission_run(run_id: String) -> void:
	var kept: Array = []
	var changed := false
	for run in pending_mission_runs:
		if typeof(run) == TYPE_DICTIONARY and str(run.get("id", "")) == run_id:
			changed = true
			continue
		kept.append(run)
	if not changed:
		return
	pending_mission_runs = kept
	_save()


func apply_mission_board(board: Dictionary) -> int:
	if not bool(board.get("ok", false)):
		return 0
	mission_board = board.duplicate(true)
	mission_board["fetched_at"] = int(Time.get_unix_time_from_system())
	var total := int(board.get("mission_reward_coins", applied_mission_reward_coins))
	var delta := DailyMissionsScript.reward_delta(applied_mission_reward_coins, total)
	if delta > 0:
		applied_mission_reward_coins += delta
		add_coins(delta)
		return delta
	_save()
	return 0


func apply_share_result(parsed: Dictionary, http_status: int, ok: bool) -> int:
	if not ok:
		return 0
	var code := str(parsed.get("code", ""))
	if code != "":
		referral_code = code
	share_reward_qualified = int(parsed.get("qualified", share_reward_qualified))
	if bool(parsed.get("first_run", false)):
		pending_first_run = false
		share_run_synced = true
	if ReferralRulesScript.clear_pending_code(http_status, str(parsed.get("attach", ""))):
		pending_referral_code = ""
	var delta := ReferralRulesScript.coin_delta(applied_share_reward_coins, int(parsed.get("granted_coins", 0)))
	if delta > 0:
		applied_share_reward_coins += delta
		add_coins(delta)
		return delta
	_save()
	return 0


func remember_claim_key(key: String) -> void:
	var next := key.strip_edges()
	if next == pending_claim_key:
		return
	pending_claim_key = next
	_save()


func clear_claim_key() -> void:
	if pending_claim_key == "":
		return
	pending_claim_key = ""
	_save()


func has_pending_finalize() -> bool:
	return pending_finalize_attempt.strip_edges() != ""


func remember_pending_finalize(attempt_id: String, score: int, player_label: String) -> void:
	pending_finalize_attempt = attempt_id.strip_edges()
	pending_finalize_score = score
	pending_finalize_name = player_label
	_save()


func clear_pending_finalize() -> void:
	if pending_finalize_attempt == "":
		return
	pending_finalize_attempt = ""
	pending_finalize_score = 0
	pending_finalize_name = ""
	_save()


func has_pending_unlimited() -> bool:
	return pending_unlimited_score > 0


func remember_pending_unlimited(score: int, player_label: String) -> void:
	if score <= 0 or score < pending_unlimited_score:
		return
	pending_unlimited_score = score
	pending_unlimited_name = player_label
	_save()


func clear_pending_unlimited_if(score: int) -> void:
	if pending_unlimited_score <= 0 or pending_unlimited_score > score:
		return
	pending_unlimited_score = 0
	pending_unlimited_name = ""
	_save()


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
