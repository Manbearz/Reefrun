extends Node2D

const HarpoonScript := preload("res://scenes/game/harpoon.gd")
const SpriteTextScript := preload("res://scripts/sprite_text.gd")
const GhostRunScript := preload("res://scripts/ghost_run.gd")
const GhostMatchScript := preload("res://scripts/ghost_match.gd")
const CourseBuilderScript := preload("res://scripts/course_builder.gd")
const ShareServiceScript := preload("res://scripts/share/share_service.gd")
const ReferralRulesScript := preload("res://scripts/share/referral_rules.gd")
const MissionOverlayScript := preload("res://scripts/daily_missions_overlay.gd")
const ButtonFeedbackScript := preload("res://scripts/button_feedback.gd")

const SHARE_CARD_CROP_H := 798
const SHARE_PLACE_RECT := Rect2(700, 398, 300, 100)
const SHARE_CHECK_RECT := Rect2(700, 528, 300, 100)
const SHARE_CLOSE_RECT := Rect2(190, 798, 400, 165)
const SHARE_SHARE_RECT := Rect2(575, 798, 500, 170)
const SHARE_REWARD_RECT := Rect2(250, 762, 653, 32)
const DEATH_SAND_BOTTOM := 1448.0

var world: ReefWorld
var hud: GameHUD
var player: ReefFish
var ghosts: Array[ReefFish] = []
var pipes: Array[PipePair] = []
var layout: Array[Dictionary] = []
var cosmetic_rng := RandomNumberGenerator.new()
var started := false
var finished := false
var paused := false
var scroll := 0.0
var spawn_index := 0
var score := 0
var overlay: CanvasLayer
var _mission_layer: CanvasLayer
var pause_layer: CanvasLayer
var _pause_dim: ColorRect
var _pause_title: SpriteText
var _pause_resume: TextureButton
var _pause_leave: TextureButton
var swimming := 100
var _feed_wait := 0.0
var school: Node2D
var course: Node2D
var course_draw: Node2D
var _pipe_pool: Array[PipePair] = []
var _warmup: Node2D
var _warmup_frames := 8
const PIPE_SPIKE_PROFILE := true
var _spike_phase := "idle"
var _spike_worst := {
	"start": 0.0,
	"pipe1_approach": 0.0,
	"score1": 0.0,
	"pipe2_approach": 0.0,
	"score2": 0.0,
}
var _spike_reported := false
var phantoms: PackedInt32Array = PackedInt32Array()
var visual_scroll := 0.0
var world_scroll := 0.0
var _harpoons: Array = []
var _pipes_until_harpoon := RR.HARPOON_EVERY
var _harpoon_beat := 0
var _warn_t := 0.0
var _safe_lane := 1
var _harpoon_checked := false
var _harpoon_round := 0
var _harpoon_lanes := PackedInt32Array()
var _harpoon_lane_i := 0
var _harpoon_stall := 0.0
var _course_extend_warned := false
# Headless course tests set this before the node enters the tree.
# Release builds ignore it, and it never starts a run or touches an attempt.
var debug_skip_ready := false
var _start_t := RR.COUNTDOWN
var _go_t := 0.0
var _in_lobby := true
var _lobby_t := 0.0
var _lobby_len := 5.0
var _shown_ghosts := 0
var match_tick := 0
var _recorded_flaps := PackedInt32Array()
var logical_death := PackedInt32Array()
var logical_alive := PackedByteArray()
var logical_names := PackedStringArray()
var _perf_n := 0
var _perf_sum := 0.0
var _perf_worst := 0.0
var _perf_phys_sum := 0.0
var _perf_phys_worst := 0.0
var _ghost_match
var _coins: Array[Sprite2D] = []
var _coin_pool: Array[Sprite2D] = []
var _run_coins := 0
var _mission_run_id := ""
var _mission_seconds := 0.0
var _mission_track := false
var _mission_dive_seconds := 0.0
var _mission_dives_entered := 0
var _mission_dives_completed := 0
var _mission_lanes := 0
var _mission_lanes_left := 0
var _mission_lanes_right := 0
var _mission_obstacles := 0
var _mission_mines := 0
var _mission_folded := false
var _over_rank := 0
var _over_remaining := 0
var _coin_reward_claimed := false
var _reward_request_active := false
var _coin_offer_open := false
# 0 means this offer is not eligible for a reward. A new show replaces it.
# Close keeps the id so the same show can still pay. Abandon, failure, a new
# offer, and a completed grant clear it.
var _reward_session := 0
var _watchdog_session := 0
# The ad is already loaded before Yes. Rewarded videos are usually 15–30s.
# 45s lets a normal ad finish and dismiss, then returns a show that never
# calls back. A longer creative can restore the offer while it is still up;
# its reward stays tied to this session and cannot pay a later Yes.
var _reward_show_timeout := 45.0
var _coin_ad_watch: Button
var _coin_ad_note: SpriteTextScript
var _eat_emulated_mouse := false
var _pending_start_flap := false
var _share_service: Node
var _share_layer: CanvasLayer
var _share_share_btn: Button
var _share_progress: SpriteText
var _wipe_again: Button
var _wipe_share: TextureButton
var _wipe_menu: TextureButton
var _share_busy := false
var _roster_ready := false
var _events: GameplayEvents
var _motion := DiveMotion.new()
var _dive_field: DiveField
var _dive_overlay: DiveOverlay
var _dive_origin := Vector2.ZERO
var _dive_leave_from := Vector2.ZERO
var _swim_home := Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42)
var _synced_state := 0
var _count_cue := 0
var _whoosh_dive := -1
var _survived_cue := false
var _dive_ghosts_hidden := false


func _ready() -> void:
	if debug_skip_ready and _dev_diag():
		set_process(false)
		set_physics_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	cosmetic_rng.randomize()
	GameSession.ensure_challenge()
	_ghost_match = GhostMatchScript.new()
	world = ReefWorld.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	course = Node2D.new()
	course.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(course)
	course_draw = Node2D.new()
	course_draw.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	course_draw.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	course_draw.z_index = 6
	add_child(course_draw)
	school = Node2D.new()
	school.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(school)
	_build_layout()
	if GameSession.match_mode == GameSession.MODE_DAILY:
		print("[daily] gameplay mode=daily seed=%d pipes=%d harpoons=%d attempt_id=%s" % [
			GameSession.course_seed,
			layout.size(),
			_harpoon_lanes.size(),
			str(GameSession.current_challenge().get("attempt_id", "")),
		])
	_spawn_player()
	var backend: Node = get_node_or_null("/root/Backend")
	if backend and backend.has_method("cancel_pre_match_requests"):
		backend.cancel_pre_match_requests()
	hud = GameHUD.new()
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(hud)
	if not get_viewport().size_changed.is_connected(_sync_screen_layout):
		get_viewport().size_changed.connect(_sync_screen_layout)
	_build_pause()
	_prewarm_pipes()
	_prime_opening_pipes()
	_sync_screen_layout()
	_setup_harpoons()
	_prewarm_gameplay_draw()
	_bind_rewarded_ads()
	_configure_web_touch()
	_share_service = ShareServiceScript.new()
	add_child(_share_service)
	_share_service.share_finished.connect(_on_share_finished)
	_begin_lobby()
	var vp := get_viewport()
	vp.snap_2d_transforms_to_pixel = false
	vp.snap_2d_vertices_to_pixel = false
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	var runs: Array = await _load_roster()
	if not is_inside_tree():
		return
	_attach_ghosts(runs)
	_roster_ready = true


func _sync_screen_layout() -> void:
	if world:
		world.apply_screen_layout()
	if hud:
		hud.apply_screen_layout()
	if _mission_layer and _mission_layer.has_method("layout_to_screen"):
		_mission_layer.layout_to_screen()
	if pause_layer and pause_layer.visible:
		_layout_pause_controls(_mission_allowed() and not finished)
	for pair in pipes:
		pair.sync_screen()
	for pair in _pipe_pool:
		pair.sync_screen()


func _build_layout() -> void:
	var built: Dictionary = CourseBuilderScript.generate(GameSession.course_seed)
	layout.clear()
	for spec in built["layout"]:
		layout.append(spec)
	_harpoon_lanes = built["harpoon_lanes"]
	_harpoon_lane_i = 0


func _spawn_player() -> void:
	player = _make_fish(GameSession.selected_fish(), true, Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42), _player_label())
	player.control = ReefFish.CTRL_PLAYER
	player.died.connect(_on_player_died)
	_setup_deep_dive()
	swimming = 1


func _load_roster() -> Array:
	var daily := GameSession.match_mode == GameSession.MODE_DAILY
	var challenge: Dictionary = GameSession.current_challenge() if daily else {}
	var backend := get_node_or_null("/root/Backend")
	if daily and backend and backend.has_method("prepared_roster"):
		var ready: Array = backend.prepared_roster(challenge)
		if ready.size() >= RR.GHOST_COUNT:
			return ready
	var challenge_id := str(challenge.get("challenge_id", "")) if daily else ""
	return await _ghost_match.fill_spread(
		get_tree(),
		GameSession.course_seed,
		layout,
		GameSession.player_id,
		"",
		challenge_id
	)


func _attach_ghosts(runs: Array) -> void:
	var vis_n := mini(runs.size(), RR.GHOST_DRAW)
	var real_n := 0
	var fallback_n := 0
	for i in runs.size():
		var run = runs[i]
		if run.source == GhostRunScript.SOURCE_REAL:
			real_n += 1
		else:
			fallback_n += 1
		if i < vis_n:
			var skin: String = run.fish_id if run.fish_id != "" else "fish_blue"
			var origin := Vector2(RR.PLAYER_X + float(i % 5) * 3.0, RR.VIEW_H * 0.42)
			var ghost := _make_fish(skin, false, origin, run.label())
			ghost.control = ReefFish.CTRL_PLAYBACK
			ghost.ghost_run = run
			ghost.apply_hat(run.hat_id)
			ghost.died.connect(_on_ghost_died.bind(ghost))
			ghost.visible = false
			ghosts.append(ghost)
		else:
			logical_death.append(run.death_tick)
			logical_alive.append(1)
			logical_names.append(run.label())
	if _dev_diag():
		print(
			"[ghosts] seed=%d challenge=%s total=%d vis=%d logical=%d real=%d fallback=%d"
			% [
				GameSession.course_seed,
				GameSession.current_challenge_id(),
				runs.size(),
				ghosts.size(),
				logical_death.size(),
				real_n,
				fallback_n,
			]
		)


func _make_fish(skin: String, is_player: bool, origin: Vector2, p_name: String) -> ReefFish:
	var fish := ReefFish.new()
	fish.setup(skin, is_player, origin, p_name)
	fish.process_mode = Node.PROCESS_MODE_PAUSABLE
	school.add_child(fish)
	return fish


func _ghost_name(i: int) -> String:
	return "%s %d" % [RR.GHOST_NAMES[i % RR.GHOST_NAMES.size()], i / RR.GHOST_NAMES.size() + 1]


func _player_label() -> String:
	return GameSession.visible_player_name()


func _roll_death_pipe() -> int:
	var u := cosmetic_rng.randf()
	if u < 0.20:
		return 0
	if u < 0.45:
		return 1
	if u < 0.66:
		return 2
	if u < 0.80:
		return 3
	if u < 0.90:
		return 4
	if u < 0.96:
		return cosmetic_rng.randi_range(5, 8)
	return cosmetic_rng.randi_range(9, 28)


func _configure_web_touch() -> void:
	if not OS.has_feature("web"):
		return
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	var js := Engine.get_singleton("JavaScriptBridge")
	js.eval(
		"""
		(function(){
			var c = document.getElementById('canvas');
			if (!c) return;
			c.style.touchAction = 'none';
			c.style.userSelect = 'none';
			c.style.webkitUserSelect = 'none';
			c.style.webkitTouchCallout = 'none';
		})();
		"""
	)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if _route_dive_pointer(event):
			return
		if event is InputEventScreenTouch and event.pressed:
			_play_press(event.position, true)
		_mark_input_handled()
		return
	if finished:
		return
	if event.is_action_pressed("pause") and event is InputEventKey:
		_set_paused(not paused)
		_mark_input_handled()
		return
	if paused:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F6 or event.physical_keycode == KEY_F6):
		if OS.has_feature("editor") and _events_on():
			_events.debug_queue_dive()
			_mark_input_handled()
			return
	if _route_dive_pointer(event):
		return
	if _events_on() and _events.steer_active() and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT or event.keycode == KEY_A or event.physical_keycode == KEY_LEFT or event.physical_keycode == KEY_A:
			_motion.nudge(-1.0)
			_mark_input_handled()
			return
		if event.keycode == KEY_RIGHT or event.keycode == KEY_D or event.physical_keycode == KEY_RIGHT or event.physical_keycode == KEY_D:
			_motion.nudge(1.0)
			_mark_input_handled()
			return
	if _events_on() and _events.suppresses_flap() and event is InputEventKey and event.pressed and event.is_action("flap"):
		_mark_input_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _eat_emulated_mouse:
			_eat_emulated_mouse = false
			_mark_input_handled()
			return
		_play_press(event.position, false)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action("flap"):
		_try_player_flap()
		_mark_input_handled()


func _mark_input_handled() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()


func _play_press(pos: Vector2, from_touch: bool) -> void:
	if from_touch:
		_eat_emulated_mouse = true
	if _button_node_at(pos):
		if from_touch:
			_press_button_at(pos)
			_mark_input_handled()
		return
	_try_player_flap()
	_mark_input_handled()


func _button_node_at(pos: Vector2) -> BaseButton:
	if _mission_layer and is_instance_valid(_mission_layer) and _mission_layer.visible:
		var mission_btn := _find_button_at(_mission_layer, pos)
		if mission_btn:
			return mission_btn
	if _share_layer and is_instance_valid(_share_layer) and _share_layer.visible:
		return _find_button_at(_share_layer, pos)
	if pause_layer and pause_layer.visible:
		var pause_btn := _find_button_at(pause_layer, pos)
		if pause_btn:
			return pause_btn
	if overlay and is_instance_valid(overlay) and overlay.visible:
		return _find_button_at(overlay, pos)
	return null


func _find_button_at(node: Node, pos: Vector2) -> BaseButton:
	var children := node.get_children()
	for i in range(children.size() - 1, -1, -1):
		var found := _find_button_at(children[i], pos)
		if found:
			return found
	if node is BaseButton:
		var btn := node as BaseButton
		if btn.visible and not btn.disabled and btn.is_visible_in_tree() and btn.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			if btn.get_global_rect().has_point(pos):
				return btn
	return null


func _press_button_at(pos: Vector2) -> void:
	if _mission_layer and is_instance_valid(_mission_layer) and _mission_layer.visible:
		if _press_button_in(_mission_layer, pos):
			return
	if _share_layer and is_instance_valid(_share_layer) and _share_layer.visible:
		_press_button_in(_share_layer, pos)
		return
	if overlay and is_instance_valid(overlay) and overlay.visible:
		if _press_button_in(overlay, pos):
			return
	if pause_layer and pause_layer.visible:
		_press_button_in(pause_layer, pos)


func _press_button_in(node: Node, pos: Vector2) -> bool:
	var children := node.get_children()
	for i in range(children.size() - 1, -1, -1):
		if _press_button_in(children[i], pos):
			return true
	if node is BaseButton:
		var btn := node as BaseButton
		if btn.visible and not btn.disabled and btn.is_visible_in_tree() and btn.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			if btn.get_global_rect().has_point(pos):
				btn.pressed.emit()
				return true
	return false


func _try_player_flap() -> void:
	if finished or paused:
		return
	if _events_on() and _events.suppresses_flap():
		_pending_start_flap = false
		return
	if player == null or not player.alive:
		return
	if not started:
		_pending_start_flap = true
		return
	player.flap(true)
	_recorded_flaps.append(match_tick)


func _begin_run() -> void:
	if started or finished:
		return
	started = true
	# Locked for this swim. A later mode change cannot turn a Daily Challenge
	# into mission progress, or an Unlimited swim into a Daily Challenge attempt.
	_mission_track = (
		GameSession.match_mode == GameSession.MODE_UNLIMITED
		and not GameSession.practice_daily
	)
	_mission_run_id = ""
	_mission_seconds = 0.0
	_mission_dive_seconds = 0.0
	_mission_dives_entered = 0
	_mission_dives_completed = 0
	_mission_lanes = 0
	_mission_lanes_left = 0
	_mission_lanes_right = 0
	_mission_obstacles = 0
	_mission_mines = 0
	if _mission_track:
		_mission_run_id = "%d-%d" % [Time.get_ticks_usec(), randi()]
		# The board already folded at 3 seconds. Starting the swim only keeps the widget.
		if not _mission_folded:
			_mission_folded = true
			_set_mission_presentation("widget")
	else:
		_set_mission_presentation("hidden")
	if GameSession.match_mode == GameSession.MODE_DAILY:
		print("[daily] gameplay run_started seed=%d pipes=%d" % [GameSession.course_seed, layout.size()])
	match_tick = 0
	_eat_emulated_mouse = false
	visual_scroll = scroll
	player.reset_for_match()
	player.started = true
	for ghost in ghosts:
		ghost.reset_for_match()
		ghost.started = true
		ghost.rest_y = ghost.position.y
	_advance_playback()
	if _pending_start_flap:
		_pending_start_flap = false
		_try_player_flap()
	_spike_phase = "start"
	_spike_reported = false
	for key in _spike_worst.keys():
		_spike_worst[key] = 0.0
	var sfx := get_node_or_null("/root/Sfx")
	if sfx:
		sfx.prewarm()


func _begin_lobby() -> void:
	_in_lobby = true
	_lobby_t = 0.0
	_mission_folded = false
	_lobby_len = RR.lobby_length(_mission_allowed())
	_shown_ghosts = 0
	swimming = 1
	if _mission_allowed():
		_set_mission_presentation("board", true)
	else:
		_set_mission_presentation("hidden")
	hud.set_lobby(true, ceili(_lobby_len))
	hud.set_coins(0)


func _mission_allowed() -> bool:
	return (
		GameSession.match_mode == GameSession.MODE_UNLIMITED
		and not GameSession.practice_daily
	)


func _set_mission_presentation(mode: String, immediate := false) -> void:
	if not _mission_allowed():
		mode = "hidden"
	elif mode == "board" and started and not paused and not finished:
		mode = "widget"
	if hud:
		var show_board := mode == "board" and not started
		var reveal := 0.0
		var was_board: bool = _mission_layer != null and is_instance_valid(_mission_layer) and _mission_layer.mode() == "board"
		if not show_board and not started and was_board and mode == "widget" and not immediate:
			reveal = MissionOverlayScript.FOLD_SECS
		hud.set_mission_card(show_board, reveal)
	if mode == "hidden":
		if _mission_layer and is_instance_valid(_mission_layer) and _mission_layer.has_method("present"):
			_mission_layer.present("hidden")
		elif _mission_layer and is_instance_valid(_mission_layer):
			_mission_layer.visible = false
		return
	_ensure_mission_layer()
	if _mission_layer.has_method("refresh_from_session"):
		_mission_layer.refresh_from_session()
	if _mission_layer.has_method("present"):
		_mission_layer.present(mode, immediate)
	else:
		_mission_layer.visible = true
	if mode == "board" and not started:
		var backend_node := get_node_or_null("/root/Backend")
		if backend_node and backend_node.has_method("refresh_daily_missions"):
			backend_node.refresh_daily_missions()


func _ensure_mission_layer() -> void:
	if _mission_layer != null and is_instance_valid(_mission_layer):
		return
	_mission_layer = MissionOverlayScript.new()
	_mission_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_mission_layer)
	var backend := get_node_or_null("/root/Backend")
	if backend == null:
		return
	if backend.has_signal("daily_missions_changed") and not backend.daily_missions_changed.is_connected(_on_daily_missions_changed):
		backend.daily_missions_changed.connect(_on_daily_missions_changed)
	if backend.has_signal("mission_reward_granted") and not backend.mission_reward_granted.is_connected(_on_mission_reward_granted):
		backend.mission_reward_granted.connect(_on_mission_reward_granted)


func _on_daily_missions_changed() -> void:
	if _mission_layer and is_instance_valid(_mission_layer) and _mission_layer.has_method("refresh_from_session"):
		_mission_layer.refresh_from_session()


func _on_mission_reward_granted(slot: String, coins: int, mission_date: String) -> void:
	if not _mission_allowed():
		return
	if _mission_layer == null or not is_instance_valid(_mission_layer):
		return
	if _mission_layer.has_method("announce_reward"):
		_mission_layer.announce_reward(slot, coins, mission_date)


func _tick_lobby(delta: float) -> void:
	_lobby_t += delta
	# Mission loading must not hold this clock. The board folds on elapsed time.
	if not _mission_folded and RR.lobby_fold_due(_lobby_t, _mission_allowed()):
		_mission_folded = true
		_set_mission_presentation("widget")
	var u := clampf(_lobby_t / _lobby_len, 0.0, 1.0)
	var filled := 1 + int(round(float(RR.GHOST_COUNT) * (1.0 - pow(1.0 - u, 2.15))))
	if u >= 1.0:
		filled = 1 + RR.GHOST_COUNT
	swimming = filled
	_reveal_ghosts(mini(ghosts.size(), filled - 1))
	hud.set_lobby(true, maxi(1, ceili(_lobby_len - _lobby_t)))
	if not RR.lobby_finished(_lobby_t, _lobby_len) or not _roster_ready:
		if _lobby_t >= _lobby_len and not _roster_ready:
			hud.set_lobby(true, 1)
		return
	_in_lobby = false
	swimming = 1 + RR.GHOST_COUNT
	_reveal_ghosts(ghosts.size())
	hud.set_lobby(false, 0)
	hud.set_countdown("GO")
	_go_t = 0.55
	_begin_run()


func _reveal_ghosts(count: int) -> void:
	var n := mini(count, ghosts.size())
	while _shown_ghosts < n:
		ghosts[_shown_ghosts].visible = true
		_shown_ghosts += 1


func _tick_countdown(delta: float) -> void:
	if finished:
		return
	if started:
		if _go_t > 0.0:
			_go_t -= delta
			if _go_t <= 0.0:
				hud.set_countdown("")
		return
	if _start_t > 0.0:
		hud.set_countdown(str(maxi(1, ceili(_start_t))))
		_start_t -= delta
		return
	hud.set_countdown("GO")
	_go_t = 0.55
	_begin_run()


func _physics_process(delta: float) -> void:
	if paused:
		return
	if _events_on():
		_events.set_corridor_clear(_corridor_clear())
		_events.tick(delta)
		if _harpoon_live():
			_tick_harpoons(delta)
		_sync_events()
	var diving := _events_on() and _events.blocks_swim()
	if started and not finished:
		if _mission_track and player != null and player.alive:
			_mission_seconds += delta
			if _events_on() and _events.state == GameplayEvents.State.DEEP_DIVE:
				_mission_dive_seconds += delta
		if not diving:
			match_tick += 1
			_advance_playback()
			scroll += RR.PIPE_SPEED * delta
			course.position.x = -scroll
		if _can_spawn_pipes():
			_spawn_pipes()
		_cull_pipes()
		if not _events_on() and _harpoon_beat != 0:
			_tick_harpoons(delta)
			_recover_daily_harpoon(delta)
		if diving:
			_update_dive_actor(delta)
		if not diving:
			_guide_ghosts()
			_collect_coins()
			if _scoring_open():
				_score_pipes()
		_sample_perf()
	if diving:
		_present_dive()
	player.tick(delta)
	if not finished and not (_events_on() and _events.ghosts_frozen()):
		for ghost in ghosts:
			if ghost.alive:
				ghost.tick(delta)
	_debug_ghost_playback()


func _process(delta: float) -> void:
	if PIPE_SPIKE_PROFILE and _dev_diag():
		_sample_pipe_spike(delta)
	if _warmup_frames > 0:
		_warmup_frames -= 1
		if _warmup_frames <= 0 and _warmup:
			_warmup.visible = false
			if hud:
				hud.hide_prewarm()
	var dive_hold := _events_on() and _events.blocks_swim()
	if world:
		var fall := 0.0
		if dive_hold and _dive_field:
			fall = _dive_field.fall_speed()
		world.set_dive_fall(fall)
	if not finished and not paused and not dive_hold:
		world_scroll += RR.PIPE_SPEED * delta
	if started and not finished and not paused and not dive_hold:
		visual_scroll += RR.PIPE_SPEED * delta
		if _harpoon_beat >= 2:
			for spear in _harpoons:
				spear.tick(delta)
			if _harpoon_beat == 2:
				_warn_t -= delta
	if paused:
		return
	course_draw.position.x = -visual_scroll
	world.follow(world_scroll)
	world.tick_decor(delta)
	_feed_wait = maxf(_feed_wait - delta, 0.0)
	if _in_lobby:
		_tick_lobby(delta)
		if _in_lobby and _lobby_len - _lobby_t > 1.0 / 60.0:
			_pending_start_flap = false
		hud.refresh(swimming, 0, false, player.alive)
		return
	_tick_countdown(delta)
	if not started:
		hud.refresh(swimming, 0, false, player.alive)
		return
	hud.refresh(swimming, score, true, player.alive)


func _spawn_pipes() -> void:
	_ensure_course_ahead()
	var lead := RR.VIEW_W + 80.0
	while spawn_index < layout.size() and layout[spawn_index]["x"] <= scroll + lead:
		_take_pipe_from_layout()
		if _harpoon_beat != 0:
			break


func _prime_opening_pipes() -> void:
	var ready := mini(4, layout.size())
	while spawn_index < ready:
		_take_pipe_from_layout()


func _take_pipe_from_layout() -> void:
	var spec: Dictionary = layout[spawn_index]
	var pair: PipePair
	if _pipe_pool.is_empty():
		pair = _make_pooled_pipe()
	else:
		pair = _pipe_pool.pop_back()
	pair.position = Vector2(spec["x"] + RR.PLAYER_X, 0)
	pair.visual.position = pair.position
	pair.rebuild(spec["style"], spec["gap_y"], spec["gap_h"])
	pair.activate()
	pipes.append(pair)
	spawn_index += 1
	if spawn_index % RR.COIN_EVERY == 0:
		_spawn_coin_after_pipe(spawn_index - 1)
	if _events_on():
		return
	_pipes_until_harpoon -= 1
	if _pipes_until_harpoon <= 0:
		_harpoon_beat = 1


func _cull_pipes() -> void:
	var cutoff := scroll - 120.0
	for i in range(pipes.size() - 1, -1, -1):
		var pair := pipes[i]
		if pair.position.x < cutoff:
			pipes.remove_at(i)
			pair.deactivate()
			_pipe_pool.append(pair)


func _guide_ghosts() -> void:
	pass


func _upcoming_gap() -> float:
	for pair in pipes:
		if pair.position.x > RR.PLAYER_X + scroll - 20.0:
			return pair.gap_y
	return (RR.PLAY_TOP + RR.PLAY_BOTTOM) * 0.5


func _spawn_coin_after_pipe(pipe_i: int) -> void:
	if pipe_i + 1 >= layout.size():
		return
	var a: Dictionary = layout[pipe_i]
	var b: Dictionary = layout[pipe_i + 1]
	var spr := _take_coin()
	spr.position = Vector2((float(a["x"]) + float(b["x"])) * 0.5 + RR.PLAYER_X, (float(a["gap_y"]) + float(b["gap_y"])) * 0.5)
	_coins.append(spr)


func _take_coin() -> Sprite2D:
	var spr: Sprite2D
	if _coin_pool.is_empty():
		spr = Sprite2D.new()
		spr.texture = Sprites.tex("coin")
		spr.centered = true
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.z_index = 7
		spr.scale = Vector2.ONE * 0.58
		course_draw.add_child(spr)
	else:
		spr = _coin_pool.pop_back()
	spr.visible = true
	return spr


func _release_coin(spr: Sprite2D) -> void:
	spr.visible = false
	if not _coin_pool.has(spr):
		_coin_pool.append(spr)


func _collect_coins() -> void:
	# Walk backward so releasing a coin cannot skip the next one.
	var alive := player != null and player.alive
	var i := _coins.size() - 1
	while i >= 0:
		var spr := _coins[i]
		if spr == null or not is_instance_valid(spr):
			_coins.remove_at(i)
			i -= 1
			continue
		var sx := spr.position.x - scroll
		if sx > RR.PLAYER_X + 24.0:
			i -= 1
			continue
		var passed := sx < RR.PLAYER_X - 48.0
		var collected := alive and not passed and absf(player.position.y - spr.position.y) <= 58.0
		if not passed and not collected:
			i -= 1
			continue
		_coins.remove_at(i)
		_release_coin(spr)
		if collected:
			_run_coins += 1
			if not GameSession.practice_daily:
				GameSession.add_coins(1)
			Sfx.play("coin", -10.0)
			if hud:
				hud.set_coins(_run_coins)
		i -= 1


func _score_pipes() -> void:
	for pair in pipes:
		if pair.scored:
			continue
		if pair.position.x < RR.PLAYER_X + scroll:
			pair.scored = true
			if player.alive:
				score += 1
				player.pipes_cleared = score
				Sfx.play("checkpoint", -10.0)
				if _events_on():
					_events.note_pipes_passed(score)


func _alive_count() -> int:
	return swimming


func _on_ghost_died(ghost: ReefFish) -> void:
	if ghost.alive:
		return
	swimming = maxi(swimming - 1, 0)
	ghost.visible = false
	if finished:
		return
	if _feed_wait > 0.0:
		return
	_feed_wait = 0.45
	hud.show_feed("%s wiped out" % ghost.display_name)


func _on_player_died() -> void:
	if finished:
		return
	if player.alive:
		return
	if _events_on():
		_events.notify_death()
		_synced_state = _events.state
		_halt_dive()
	Sfx.play_death(-10.0)
	swimming = maxi(swimming - 1, 0)
	var remaining := swimming
	var rank := remaining + 1
	if not GameSession.practice_daily:
		_save_ghost_run()
		if _mission_track:
			GameSession.remember_mission_run(_mission_run_id, score, int(_mission_seconds), _run_coins, _mission_dive_facts())
		GameSession.record_run(score, rank, remaining)
	_log_perf()
	get_tree().create_timer(0.85).timeout.connect(_after_death.bind(rank, remaining))


func _after_death(rank: int, remaining: int) -> void:
	if overlay and is_instance_valid(overlay):
		return
	_over_rank = rank
	_over_remaining = remaining
	if GameSession.practice_daily:
		_run_coins = 0
		_show_over(rank, remaining)
	elif _run_coins > 0 and RewardedAds.is_rewarded_ad_available():
		_show_coin_ad()
	else:
		# Coins picked up during the swim stay in the wallet. The extra ad
		# payout is only offered when a real rewarded ad can be completed.
		_show_over(rank, remaining)


func _bind_rewarded_ads() -> void:
	RewardedAds.reward_earned.connect(_on_rewarded_ad_earned)
	RewardedAds.ad_closed.connect(_on_rewarded_ad_closed)
	RewardedAds.ad_failed.connect(_on_rewarded_ad_failed)
	RewardedAds.ad_unavailable.connect(_on_rewarded_ad_unavailable)
	tree_exiting.connect(_unbind_rewarded_ads)


func _unbind_rewarded_ads() -> void:
	if RewardedAds.reward_earned.is_connected(_on_rewarded_ad_earned):
		RewardedAds.reward_earned.disconnect(_on_rewarded_ad_earned)
	if RewardedAds.ad_closed.is_connected(_on_rewarded_ad_closed):
		RewardedAds.ad_closed.disconnect(_on_rewarded_ad_closed)
	if RewardedAds.ad_failed.is_connected(_on_rewarded_ad_failed):
		RewardedAds.ad_failed.disconnect(_on_rewarded_ad_failed)
	if RewardedAds.ad_unavailable.is_connected(_on_rewarded_ad_unavailable):
		RewardedAds.ad_unavailable.disconnect(_on_rewarded_ad_unavailable)


func _clear_overlay() -> void:
	_close_share_overlay(false)
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null
	_wipe_again = null
	_wipe_share = null
	_wipe_menu = null


func _show_coin_ad() -> void:
	finished = true
	_invalidate_reward_session()
	_coin_offer_open = true
	_coin_reward_claimed = false
	_reward_request_active = false
	_clear_overlay()
	overlay = CanvasLayer.new()
	overlay.layer = 40
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Palette.SHADOW
	dim.size = RR.screen_size()
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var tex := Sprites.tex("coin_ad_overlay")
	var src := Vector2(1536, 1024)
	if tex:
		src = Vector2(tex.get_width(), tex.get_height())
	var scale := minf(RR.VIEW_W / src.x, RR.VIEW_H / src.y) * 0.96
	var card_size := src * scale
	var card_pos := (Vector2(RR.VIEW_W, RR.VIEW_H) - card_size) * 0.5
	var card := TextureRect.new()
	card.texture = tex
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.position = card_pos
	card.size = card_size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(card)
	overlay.add_child(_coin_ad_hotspot(card_pos, scale, Rect2(400, 720, 360, 220), _skip_coin_ad))
	_coin_ad_watch = _coin_ad_hotspot(card_pos, scale, Rect2(780, 720, 420, 220), _watch_coin_ad)
	overlay.add_child(_coin_ad_watch)
	_coin_ad_note = SpriteTextScript.new()
	_coin_ad_note.position = Vector2(24, RR.VIEW_H - 70)
	_coin_ad_note.configure("", 16, Vector2(RR.VIEW_W - 48, 28), HORIZONTAL_ALIGNMENT_CENTER)
	overlay.add_child(_coin_ad_note)
	_set_mission_presentation("aside")


func _coin_ad_hotspot(origin: Vector2, scale: float, src: Rect2, pressed: Callable) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.position = origin + src.position * scale
	btn.size = src.size * scale
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(pressed)
	var plate := Rect2(src.position + Vector2(30, 24), src.size - Vector2(60, 48))
	ButtonFeedbackScript.use_plate(btn, Sprites.tex("coin_ad_overlay"), src, plate, 0.4)
	return btn


func _skip_coin_ad() -> void:
	if _reward_request_active:
		return
	_abandon_coin_offer()


func _watch_coin_ad() -> void:
	if _reward_request_active or _coin_reward_claimed:
		return
	if not _coin_offer_open:
		return
	_reward_request_active = true
	if _coin_ad_watch:
		_coin_ad_watch.disabled = true
	_set_coin_ad_note("")
	if not RewardedAds.is_rewarded_ad_available():
		_on_rewarded_ad_unavailable(0)
		return
	# Store the id before show so a callback that returns immediately still
	# belongs to this offer, not to whatever show happens next.
	var session_id := RewardedAds.begin_show_session()
	_reward_session = session_id
	if overlay:
		overlay.visible = false
	_arm_reward_watchdog(session_id)
	RewardedAds.show_session(session_id)


func _finish_coin_ad() -> void:
	if _coin_reward_claimed:
		return
	_coin_reward_claimed = true
	_reward_request_active = false
	_coin_offer_open = false
	_invalidate_reward_session()
	var bonus := _run_coins
	if bonus > 0:
		GameSession.add_coins(bonus)
		_run_coins = 0
		if hud:
			hud.set_coins(GameSession.coins)
		print("[ReefRun ads] bonus granted %d. wallet %d" % [bonus, GameSession.coins])
	_show_over(_over_rank, _over_remaining)


func _abandon_coin_offer() -> void:
	_coin_offer_open = false
	_reward_request_active = false
	_invalidate_reward_session()
	_run_coins = 0
	_show_over(_over_rank, _over_remaining)


func _restore_coin_ad(message: String) -> void:
	var reason := message if not message.is_empty() else "closed before the reward"
	print("[ReefRun ads] bonus not granted. %s" % reason)
	_reward_request_active = false
	if not _coin_offer_open or _coin_reward_claimed:
		return
	if overlay and is_instance_valid(overlay):
		overlay.visible = true
	if _coin_ad_watch:
		_coin_ad_watch.disabled = false
	_set_coin_ad_note(message)


func _set_coin_ad_note(message: String) -> void:
	if _coin_ad_note:
		_coin_ad_note.set_value(message)
	elif hud and not message.is_empty():
		hud.show_feed(message)


func _invalidate_reward_session() -> void:
	_reward_session = 0
	_cancel_reward_watchdog()


func _cancel_reward_watchdog() -> void:
	_watchdog_session = 0


func _arm_reward_watchdog(session_id: int) -> void:
	_watchdog_session = session_id
	var timer := get_tree().create_timer(_reward_show_timeout, true)
	timer.timeout.connect(_on_reward_watchdog.bind(session_id), CONNECT_ONE_SHOT)


func _on_reward_watchdog(session_id: int) -> void:
	# Pause and resume do not grant coins or change the session. An old timer
	# no longer matches after a new offer, a new Yes, or a terminal callback.
	if session_id <= 0 or session_id != _watchdog_session or session_id != _reward_session:
		return
	if _coin_reward_claimed or not _coin_offer_open:
		return
	_cancel_reward_watchdog()
	_restore_coin_ad("Ad timed out")


func _reward_session_matches(session_id: int) -> bool:
	return session_id > 0 and session_id == _reward_session


func _on_rewarded_ad_earned(session_id: int) -> void:
	if not _reward_session_matches(session_id):
		return
	if not _coin_offer_open or _coin_reward_claimed:
		return
	_cancel_reward_watchdog()
	_finish_coin_ad()


func _on_rewarded_ad_closed(session_id: int) -> void:
	if not _reward_session_matches(session_id):
		return
	if _coin_reward_claimed or not _coin_offer_open:
		return
	_cancel_reward_watchdog()
	_restore_coin_ad("")


func _on_rewarded_ad_failed(_reason: String, session_id: int) -> void:
	if session_id != 0 and not _reward_session_matches(session_id):
		return
	if _coin_reward_claimed:
		return
	_invalidate_reward_session()
	_restore_coin_ad("No ad available")


func _on_rewarded_ad_unavailable(session_id: int = 0) -> void:
	if session_id != 0 and not _reward_session_matches(session_id):
		return
	if _coin_reward_claimed:
		return
	_invalidate_reward_session()
	_restore_coin_ad("No ad available")


func _show_over(rank: int, remaining: int) -> void:
	finished = true
	_over_rank = rank
	_over_remaining = remaining
	_clear_overlay()
	overlay = CanvasLayer.new()
	overlay.layer = 40
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Palette.SHADOW
	dim.size = RR.screen_size()
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	_set_mission_presentation("aside")
	var tex := Sprites.tex("death_overlay")
	var src_w := 1024.0
	var src_h := 1536.0
	if tex:
		src_w = float(tex.get_width())
		src_h = float(tex.get_height())
	var menu_tex := Sprites.tex("btn_main_menu")
	var menu_src := Vector2(1821, 864)
	if menu_tex:
		menu_src = Vector2(menu_tex.get_width(), menu_tex.get_height())
	var share_tex := Sprites.tex("btn_share_small")
	var share_src := Vector2(335, 377)
	if share_tex:
		share_src = Vector2(share_tex.get_width(), share_tex.get_height())
	var gap := 6.0
	var card_scale := RR.VIEW_W / src_w
	var menu_w := RR.VIEW_W * 0.92
	var menu_h := menu_w * (menu_src.y / menu_src.x)
	var card_h := src_h * card_scale
	if card_h + gap + menu_h > RR.VIEW_H - 8.0:
		card_scale *= (RR.VIEW_H - 8.0 - gap - menu_h) / card_h
		card_h = src_h * card_scale
	var card_size := Vector2(src_w, src_h) * card_scale
	var stack_h := card_h + gap + menu_h
	var stack_y := (RR.VIEW_H - stack_h) * 0.5
	var card_pos := Vector2((RR.VIEW_W - card_size.x) * 0.5, stack_y)
	var card := TextureRect.new()
	card.texture = tex
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.position = card_pos
	card.size = card_size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(card)
	overlay.add_child(_over_digits(card_pos, card_scale, Rect2(541, 652, 318, 118), [
		["num_gold", rank],
		["glyph", "/"],
		["num_white", RR.GHOST_COUNT + 1],
	]))
	overlay.add_child(_over_digits(card_pos, card_scale, Rect2(541, 824, 317, 117), [
		["num_gold", score],
	]))
	overlay.add_child(_over_digits(card_pos, card_scale, Rect2(559, 991, 296, 119), [
		["num_white", remaining],
	]))
	_wipe_again = Button.new()
	_wipe_again.flat = true
	_wipe_again.position = card_pos + Vector2(310, 1175) * card_scale
	_wipe_again.size = Vector2(430, 150) * card_scale
	_wipe_again.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_wipe_again.pressed.connect(_retry)
	ButtonFeedbackScript.use_plate(_wipe_again, tex, Rect2(310, 1175, 430, 150), Rect2(316, 1181, 418, 138), 0.46, "green")
	overlay.add_child(_wipe_again)
	_wipe_menu = TextureButton.new()
	_wipe_menu.texture_normal = menu_tex
	_wipe_menu.ignore_texture_size = true
	_wipe_menu.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_wipe_menu.position = Vector2((RR.VIEW_W - menu_w) * 0.5, stack_y + card_h + gap)
	_wipe_menu.size = Vector2(menu_w, menu_h)
	_wipe_menu.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_wipe_menu.pressed.connect(_menu)
	overlay.add_child(_wipe_menu)
	if not GameSession.practice_daily:
		var share_h := 124.0
		var share_w := share_h * (share_src.x / share_src.y)
		_wipe_share = TextureButton.new()
		_wipe_share.texture_normal = share_tex
		_wipe_share.ignore_texture_size = true
		_wipe_share.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		_wipe_share.position = Vector2((RR.VIEW_W - share_w) * 0.5, card_pos.y + DEATH_SAND_BOTTOM * card_scale + 2.0)
		_wipe_share.size = Vector2(share_w, share_h)
		_wipe_share.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_wipe_share.pressed.connect(_open_share_overlay)
		overlay.add_child(_wipe_share)


func _over_digits(card_pos: Vector2, card_scale: float, src: Rect2, parts: Array) -> Control:
	var box := Control.new()
	box.position = card_pos + src.position * card_scale
	box.size = src.size * card_scale
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var groups: Array = []
	var max_h := 1.0
	for part in parts:
		var prefix: String = part[0]
		var glyphs: Array = []
		for ch in str(part[1]):
			var glyph_tex: Texture2D
			if prefix == "glyph":
				glyph_tex = Sprites.glyph(ch)
			else:
				glyph_tex = Sprites.tex("%s_%s" % [prefix, ch])
			glyphs.append(glyph_tex)
			if glyph_tex:
				max_h = maxf(max_h, float(glyph_tex.get_height()))
		groups.append(glyphs)
	var pad := box.size.y * 0.14
	var target_h := maxf(8.0, box.size.y - pad * 2.0)
	var scale := target_h / max_h * 0.88
	var kern := 1.08
	var group_gap := target_h * 0.05
	var x_pad := box.size.x * 0.08
	var total_w := 0.0
	var group_widths: PackedFloat32Array = PackedFloat32Array()
	for glyphs in groups:
		var gw := _digit_width(glyphs, scale, kern)
		group_widths.append(gw)
		if group_widths.size() > 1:
			total_w += group_gap
		total_w += gw
	if total_w > box.size.x - x_pad * 2.0:
		scale *= (box.size.x - x_pad * 2.0) / maxf(total_w, 1.0)
		total_w = 0.0
		group_gap = target_h * 0.05 * (scale / (target_h / max_h))
		for g in groups.size():
			group_widths[g] = _digit_width(groups[g], scale, kern)
			if g > 0:
				total_w += group_gap
			total_w += group_widths[g]
	var x := (box.size.x - total_w) * 0.5
	for g in groups.size():
		if g > 0:
			x += group_gap
		_place_digit_group(box, groups[g], x, scale, kern)
		x += group_widths[g]
	return box


func _digit_width(glyphs: Array, scale: float, kern: float) -> float:
	var gw := 0.0
	for i in glyphs.size():
		var tex: Texture2D = glyphs[i]
		if tex == null:
			continue
		var dw := float(tex.get_width()) * scale
		gw += dw if gw == 0.0 else dw * kern
	return gw


func _place_digit_group(box: Control, glyphs: Array, x: float, scale: float, kern: float) -> void:
	for i in glyphs.size():
		var tex: Texture2D = glyphs[i]
		if tex == null:
			continue
		var dw := float(tex.get_width()) * scale
		var dh := float(tex.get_height()) * scale
		if i > 0:
			x -= dw * (1.0 - kern)
		var digit := TextureRect.new()
		digit.texture = tex
		digit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		digit.stretch_mode = TextureRect.STRETCH_SCALE
		digit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		digit.size = Vector2(dw, dh)
		digit.position = Vector2(x, (box.size.y - dh) * 0.5)
		box.add_child(digit)
		x += dw


func _share_open() -> bool:
	return _share_layer != null and is_instance_valid(_share_layer) and _share_layer.visible


func _set_wipe_controls_enabled(enabled: bool) -> void:
	for btn in [_wipe_again, _wipe_share, _wipe_menu]:
		if btn == null or not is_instance_valid(btn):
			continue
		btn.disabled = not enabled
		btn.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func _share_value_parts() -> Array:
	return [
		[["num_gold", _over_rank]],
		[["num_gold", score]],
	]


func _open_share_overlay() -> void:
	if not finished:
		return
	if _share_open():
		return
	_set_wipe_controls_enabled(false)
	_share_busy = false
	if _share_layer and is_instance_valid(_share_layer):
		_share_layer.queue_free()
	_share_layer = CanvasLayer.new()
	_share_layer.layer = 50
	_share_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_share_layer)
	var dim := ColorRect.new()
	dim.color = Palette.SHADOW
	dim.size = RR.screen_size()
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_share_layer.add_child(dim)
	var tex := Sprites.tex("share_overlay")
	var src := Vector2(1153, 985)
	if tex:
		src = Vector2(tex.get_width(), tex.get_height())
	var card_scale := minf(RR.VIEW_W / src.x, RR.VIEW_H / src.y) * 0.96
	var card_size := src * card_scale
	var card_pos := (Vector2(RR.VIEW_W, RR.VIEW_H) - card_size) * 0.5
	var card := TextureRect.new()
	card.texture = tex
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.position = card_pos
	card.size = card_size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_share_layer.add_child(card)
	var parts: Array = _share_value_parts()
	_share_layer.add_child(_over_digits(card_pos, card_scale, SHARE_PLACE_RECT, parts[0]))
	_share_layer.add_child(_over_digits(card_pos, card_scale, SHARE_CHECK_RECT, parts[1]))
	var close_btn := Button.new()
	close_btn.flat = true
	close_btn.position = card_pos + SHARE_CLOSE_RECT.position * card_scale
	close_btn.size = SHARE_CLOSE_RECT.size * card_scale
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.pressed.connect(_close_share_overlay.bind(true))
	ButtonFeedbackScript.use_plate(close_btn, tex, SHARE_CLOSE_RECT, Rect2(198, 806, 384, 149), 0.45, "red")
	_share_layer.add_child(close_btn)
	_share_share_btn = Button.new()
	_share_share_btn.flat = true
	_share_share_btn.position = card_pos + SHARE_SHARE_RECT.position * card_scale
	_share_share_btn.size = SHARE_SHARE_RECT.size * card_scale
	_share_share_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_share_share_btn.pressed.connect(_share_card_pressed)
	ButtonFeedbackScript.use_plate(_share_share_btn, tex, SHARE_SHARE_RECT, Rect2(583, 806, 484, 154), 0.45)
	_share_layer.add_child(_share_share_btn)
	_share_progress = SpriteTextScript.new()
	_share_progress.z_index = 2
	_share_progress.position = card_pos + SHARE_REWARD_RECT.position * card_scale
	_share_progress.configure(
		ReferralRulesScript.progress_label(GameSession.share_reward_qualified),
		SHARE_REWARD_RECT.size.y * card_scale,
		SHARE_REWARD_RECT.size * card_scale,
		HORIZONTAL_ALIGNMENT_CENTER,
		false,
		true
	)
	_share_layer.add_child(_share_progress)
	_bind_share_rewards()
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_method("refresh_share_rewards"):
		backend.refresh_share_rewards()


func _close_share_overlay(restore_wipe := true) -> void:
	_share_busy = false
	_share_share_btn = null
	_share_progress = null
	_unbind_share_rewards()
	if _share_layer and is_instance_valid(_share_layer):
		_share_layer.queue_free()
	_share_layer = null
	if restore_wipe:
		_set_wipe_controls_enabled(true)


func _texture_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		var path := tex.resource_path
		if path.is_empty():
			return null
		img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _capture_share_card_png() -> PackedByteArray:
	var tex := Sprites.tex("share_overlay")
	var src := _texture_image(tex)
	if src == null:
		return PackedByteArray()
	var crop_h := mini(SHARE_CARD_CROP_H, src.get_height())
	var card := src.get_region(Rect2i(0, 0, src.get_width(), crop_h))
	if card.get_format() != Image.FORMAT_RGBA8:
		card.convert(Image.FORMAT_RGBA8)
	var parts: Array = _share_value_parts()
	_blit_share_digits(card, SHARE_PLACE_RECT, parts[0])
	_blit_share_digits(card, SHARE_CHECK_RECT, parts[1])
	return card.save_png_to_buffer()


func _blit_share_digits(dest: Image, src: Rect2, parts: Array) -> void:
	var box := src.size
	var groups: Array = []
	var max_h := 1.0
	for part in parts:
		var prefix: String = part[0]
		var glyphs: Array = []
		for ch in str(part[1]):
			var glyph_tex: Texture2D
			if prefix == "glyph":
				glyph_tex = Sprites.glyph(ch)
			else:
				glyph_tex = Sprites.tex("%s_%s" % [prefix, ch])
			glyphs.append(glyph_tex)
			if glyph_tex:
				max_h = maxf(max_h, float(glyph_tex.get_height()))
		groups.append(glyphs)
	var pad := box.y * 0.14
	var target_h := maxf(8.0, box.y - pad * 2.0)
	var scale := target_h / max_h * 0.88
	var kern := 1.08
	var group_gap := target_h * 0.05
	var x_pad := box.x * 0.08
	var total_w := 0.0
	var group_widths: PackedFloat32Array = PackedFloat32Array()
	for glyphs in groups:
		var gw := _digit_width(glyphs, scale, kern)
		group_widths.append(gw)
		if group_widths.size() > 1:
			total_w += group_gap
		total_w += gw
	if total_w > box.x - x_pad * 2.0:
		scale *= (box.x - x_pad * 2.0) / maxf(total_w, 1.0)
		total_w = 0.0
		group_gap = target_h * 0.05 * (scale / (target_h / max_h))
		for g in groups.size():
			group_widths[g] = _digit_width(groups[g], scale, kern)
			if g > 0:
				total_w += group_gap
			total_w += group_widths[g]
	var x := src.position.x + (box.x - total_w) * 0.5
	for g in groups.size():
		if g > 0:
			x += group_gap
		var gx := x
		for i in groups[g].size():
			var glyph_tex: Texture2D = groups[g][i]
			if glyph_tex == null:
				continue
			var dw := float(glyph_tex.get_width()) * scale
			var dh := float(glyph_tex.get_height()) * scale
			if i > 0:
				gx -= dw * (1.0 - kern)
			var gimg := _texture_image(glyph_tex)
			if gimg:
				gimg.resize(maxi(1, int(round(dw))), maxi(1, int(round(dh))), Image.INTERPOLATE_LANCZOS)
				var px := int(round(gx))
				var py := int(round(src.position.y + (box.y - dh) * 0.5))
				dest.blend_rect(gimg, Rect2i(Vector2i.ZERO, gimg.get_size()), Vector2i(px, py))
			gx += dw
		x += group_widths[g]


func _share_card_pressed() -> void:
	if not _share_open():
		return
	if _share_busy or (_share_service and _share_service.is_busy()):
		return
	_share_busy = true
	if _share_share_btn:
		_share_share_btn.disabled = true
	var png := _capture_share_card_png()
	if png.is_empty():
		_on_share_finished("failed")
		return
	if _share_service == null:
		_on_share_finished("failed")
		return
	var message := ReferralRulesScript.share_message(GameSession.referral_code)
	var status := str(_share_service.share_image(png, message))
	if status == "busy" or status.is_empty():
		_on_share_finished(status)


func _bind_share_rewards() -> void:
	var backend := get_node_or_null("/root/Backend")
	if backend == null or not backend.has_signal("share_rewards_changed"):
		return
	if not backend.share_rewards_changed.is_connected(_on_share_rewards_changed):
		backend.share_rewards_changed.connect(_on_share_rewards_changed)


func _unbind_share_rewards() -> void:
	var backend := get_node_or_null("/root/Backend")
	if backend and backend.has_signal("share_rewards_changed") and backend.share_rewards_changed.is_connected(_on_share_rewards_changed):
		backend.share_rewards_changed.disconnect(_on_share_rewards_changed)


func _on_share_rewards_changed() -> void:
	if _share_progress and is_instance_valid(_share_progress):
		_share_progress.set_value(ReferralRulesScript.progress_label(GameSession.share_reward_qualified))


func _on_share_finished(_status: String) -> void:
	_share_busy = false
	if _share_share_btn and is_instance_valid(_share_share_btn):
		_share_share_btn.disabled = false


func _retry() -> void:
	get_tree().paused = false
	if GameSession.practice_daily:
		get_tree().reload_current_scene.call_deferred()
		return
	if GameSession.match_mode == GameSession.MODE_DAILY:
		# The attempt was consumed at start. Another swim would be a second attempt.
		_menu()
		return
	GameSession.start_match(GameSession.MODE_UNLIMITED)
	get_tree().reload_current_scene.call_deferred()


func _menu() -> void:
	get_tree().paused = false
	if GameSession.practice_daily:
		GameSession.end_practice_daily()
	get_tree().change_scene_to_file.call_deferred("res://scenes/menu/main_menu.tscn")


func _set_paused(value: bool) -> void:
	if finished:
		return
	paused = value
	if _events_on():
		_events.set_paused(value)
	get_tree().paused = value
	if value and started and _mission_allowed():
		_set_mission_presentation("board")
	elif not value and started and _mission_allowed():
		if _events_on() and _events.blocks_swim():
			_set_mission_presentation("hidden")
		else:
			_set_mission_presentation("widget")
	if pause_layer:
		pause_layer.visible = value
		_layout_pause_controls(value and _mission_allowed())


func _build_pause() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 30
	pause_layer.visible = false
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_layer)
	_pause_dim = ColorRect.new()
	_pause_dim.color = Palette.SHADOW
	_pause_dim.size = RR.screen_size()
	_pause_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_layer.add_child(_pause_dim)
	_pause_title = SpriteTextScript.new()
	_pause_title.position = Vector2(0, RR.VIEW_H * 0.30)
	_pause_title.configure("PAUSED", 34, Vector2(RR.VIEW_W, 42), HORIZONTAL_ALIGNMENT_CENTER)
	pause_layer.add_child(_pause_title)
	_pause_resume = UIKit.make_icon_button(Sprites.tex("btn_play"), func(): _set_paused(false), 0.48)
	_pause_resume.size = _pause_resume.custom_minimum_size
	_pause_resume.position = Vector2(RR.VIEW_W * 0.5 - 33, RR.VIEW_H * 0.42)
	pause_layer.add_child(_pause_resume)
	_pause_leave = UIKit.make_icon_button(Sprites.tex("btn_close"), _menu, 0.35)
	_pause_leave.size = _pause_leave.custom_minimum_size
	_pause_leave.position = Vector2(RR.VIEW_W * 0.5 - 24, RR.VIEW_H * 0.56)
	pause_layer.add_child(_pause_leave)


func _layout_pause_controls(board_open: bool) -> void:
	if pause_layer == null or _pause_resume == null or _pause_leave == null:
		return
	var screen := RR.screen_size()
	pause_layer.layer = 36 if board_open else 30
	if _pause_dim:
		_pause_dim.size = screen
		_pause_dim.visible = not board_open
	if _pause_title:
		_pause_title.visible = not board_open
		_pause_title.position = Vector2(0, screen.y * 0.30)
	if not board_open:
		_pause_resume.position = Vector2(screen.x * 0.5 - 33, RR.VIEW_H * 0.42)
		_pause_leave.position = Vector2(screen.x * 0.5 - 24, RR.VIEW_H * 0.56)
		return
	var resume_size := _pause_resume.size
	if resume_size.y < 8.0:
		resume_size = _pause_resume.custom_minimum_size
	var leave_size := _pause_leave.size
	if leave_size.y < 8.0:
		leave_size = _pause_leave.custom_minimum_size
	var gap := 18.0
	var row_h := maxf(resume_size.y, leave_size.y)
	var y := screen.y - 22.0 - row_h
	var x := (screen.x - resume_size.x - gap - leave_size.x) * 0.5
	_pause_resume.position = Vector2(x, y + (row_h - resume_size.y) * 0.5)
	_pause_leave.position = Vector2(x + resume_size.x + gap, y + (row_h - leave_size.y) * 0.5)


func _prewarm_pipes() -> void:
	for i in RR.PIPE_POOL_SIZE:
		_pipe_pool.append(_make_pooled_pipe())


func _prewarm_gameplay_draw() -> void:
	_warmup = Node2D.new()
	_warmup.z_index = 40
	add_child(_warmup)
	var ids: PackedStringArray = RR.PIPE_IDS.duplicate()
	ids.append("coin")
	ids.append("num_gold_0")
	ids.append("num_gold_1")
	ids.append("num_gold_2")
	for i in ids.size():
		var spr := Sprite2D.new()
		spr.texture = Sprites.tex(ids[i])
		spr.centered = true
		spr.scale = Vector2.ONE * 0.04
		spr.position = Vector2(8.0 + float(i) * 6.0, 8.0)
		spr.modulate.a = 0.05
		_warmup.add_child(spr)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx:
		sfx.prewarm()


func _make_pooled_pipe() -> PipePair:
	var pair := PipePair.new()
	pair.process_mode = Node.PROCESS_MODE_PAUSABLE
	pair.rebuild(RR.PIPE_IDS[_pipe_pool.size() % RR.PIPE_IDS.size()], RR.VIEW_H * 0.45, RR.GAP)
	course.add_child(pair)
	course_draw.add_child(pair.visual)
	pair.visual.position = pair.position
	pair.activate()
	pair.deactivate()
	return pair


func _setup_harpoons() -> void:
	for lane in RR.HARPOON_LANES:
		for slot in RR.HARPOON_PER_LANE:
			var spear = HarpoonScript.new()
			add_child(spear)
			spear.setup(lane, RR.harpoon_lane_y(lane, slot))
			_harpoons.append(spear)


func _lane_center(lane: int) -> float:
	return RR.harpoon_lane_center(lane)


func _lane_of(y: float) -> int:
	return RR.harpoon_lane_of(y)


func _pipes_ahead() -> bool:
	var px := RR.PLAYER_X + scroll
	for pair in pipes:
		if pair.position.x > px - 70.0:
			return true
	return false


func _tick_harpoons(_delta: float) -> void:
	if _harpoon_beat == 1:
		if not _pipes_ahead():
			_harpoon_round = 0
			_begin_harpoon_warn()
		return
	if _harpoon_beat == 2:
		if _warn_t <= 0.0:
			_begin_harpoon_fire()
		return
	if _harpoon_beat != 3:
		return
	var flying := false
	for spear in _harpoons:
		if not spear.flying:
			continue
		flying = true
		var left: float = spear.span_left()
		var right: float = spear.span_right()
		if left < RR.PLAYER_X + RR.FISH_BODY * 0.5 and right > RR.PLAYER_X - RR.FISH_BODY * 0.5:
			if player != null and player.alive and _lane_of(player.position.y) != _safe_lane:
				player.kill()
			if not _harpoon_checked:
				_strike_harpoon_ghosts()
				_harpoon_checked = true
	if not flying:
		_finish_harpoon_volley()


func _begin_harpoon_warn() -> void:
	_safe_lane = _pick_safe_lane()
	_warn_t = RR.HARPOON_WARN
	_harpoon_checked = false
	_harpoon_beat = 2
	for spear in _harpoons:
		if spear.lane == _safe_lane:
			spear.hide_idle()
		else:
			spear.arm()
	if _harpoon_round == 0 and hud:
		hud.show_feed("Harpoons incoming")
	if _events_on():
		_events.notify_harpoon_phase(GameplayEvents.State.HARPOON_WARNING)


func _pick_safe_lane() -> int:
	if _harpoon_lane_i >= _harpoon_lanes.size():
		_refill_harpoon_lanes()
	if _harpoon_lane_i < _harpoon_lanes.size():
		var lane := _harpoon_lanes[_harpoon_lane_i]
		_harpoon_lane_i += 1
		return lane
	push_error("[course] harpoon lanes exhausted seed=%d" % GameSession.course_seed)
	return 1


func _refill_harpoon_lanes() -> void:
	var built: Dictionary = CourseBuilderScript.continuation(GameSession.course_seed, _harpoon_lanes.size())
	var lanes: PackedInt32Array = built.get("harpoon_lanes", PackedInt32Array())
	if lanes.is_empty():
		push_error("[course] harpoon refill failed seed=%d" % GameSession.course_seed)
		return
	for lane in lanes:
		_harpoon_lanes.append(int(lane))


func _begin_harpoon_fire() -> void:
	_harpoon_beat = 3
	Sfx.play("grappling")
	for spear in _harpoons:
		spear.fire()
	if _events_on():
		_events.notify_harpoon_phase(GameplayEvents.State.HARPOON_ACTIVE)


func _strike_harpoon_ghosts() -> void:
	for ghost in ghosts:
		if not ghost.alive:
			continue
		if ghost.control == ReefFish.CTRL_PLAYBACK:
			continue
		if _lane_of(ghost.position.y) == _safe_lane:
			continue
		if ghost.skill > 0.82 and absf(ghost.position.y - _lane_center(_safe_lane)) < 70.0:
			continue
		ghost.kill()


func _finish_harpoon_volley() -> void:
	for spear in _harpoons:
		spear.hide_idle()
	_harpoon_round += 1
	if _harpoon_round < RR.HARPOON_SHOTS:
		_begin_harpoon_warn()
		return
	_shift_upcoming_pipes(RR.VIEW_W + 120.0)
	_harpoon_round = 0
	_harpoon_beat = 0
	if _events_on():
		_events.notify_harpoon_finished()
		return
	_pipes_until_harpoon = RR.HARPOON_EVERY


func _advance_playback() -> void:
	for ghost in ghosts:
		if ghost.control != ReefFish.CTRL_PLAYBACK or not ghost.alive:
			continue
		var run = ghost.ghost_run
		if run == null:
			continue
		var flaps = run.flap_ticks
		# Consume missed ticks without replaying them; fire this tick's flap once.
		while ghost.next_flap_index < flaps.size() and int(flaps[ghost.next_flap_index]) < match_tick:
			ghost.next_flap_index += 1
		if ghost.next_flap_index < flaps.size() and int(flaps[ghost.next_flap_index]) == match_tick:
			ghost.flap(false)
			ghost.next_flap_index += 1
		if run.death_tick >= 0 and match_tick >= run.death_tick:
			ghost.kill()
	for i in logical_death.size():
		if logical_alive[i] == 0:
			continue
		if match_tick >= logical_death[i]:
			logical_alive[i] = 0
			swimming = maxi(swimming - 1, 0)


func _save_ghost_run() -> void:
	var run = GhostRunScript.new()
	var daily := GameSession.match_mode == GameSession.MODE_DAILY
	var challenge: Dictionary = GameSession.current_challenge() if daily else {}
	run.physics_version = int(challenge.get("physics_version", RR.PHYSICS_VERSION))
	run.course_version = int(challenge.get("course_version", RR.COURSE_VERSION))
	run.course_seed = GameSession.course_seed
	run.challenge_id = str(challenge.get("challenge_id", "")) if daily else ""
	run.display_name = _player_label()
	run.player_name = run.display_name
	run.fish_id = GameSession.selected_fish()
	run.hat_id = GameSession.hat_index
	run.flap_ticks = _recorded_flaps
	run.death_tick = match_tick
	run.score = score
	run.source = GhostRunScript.SOURCE_REAL
	run.player_id = GameSession.player_id
	run.created_at = int(Time.get_unix_time_from_system())
	run.run_id = "%s-%d-%d" % [GameSession.player_id, GameSession.course_seed, run.created_at]
	_ghost_match.save_local_run(run)


func _sample_perf() -> void:
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_perf_n += 1
	_perf_sum += frame_ms
	_perf_phys_sum += phys_ms
	if frame_ms > _perf_worst:
		_perf_worst = frame_ms
	if phys_ms > _perf_phys_worst:
		_perf_phys_worst = phys_ms


func _debug_ghost_playback() -> void:
	if not started or not _dev_diag() or ghosts.is_empty():
		return
	if match_tick > 90 or (match_tick > 1 and match_tick % 15 != 0):
		return
	var ghost: ReefFish = ghosts[0]
	var run = ghost.ghost_run
	var consumed := ghost.next_flap_index
	var next_flap := -1
	var total := 0
	if run != null:
		total = run.flap_ticks.size()
		if consumed < total:
			next_flap = int(run.flap_ticks[consumed])
	print(
		"[ghost-dbg] tick=%d y=%.1f vy=%.1f consumed=%d/%d next_flap=%d gravity=1"
		% [match_tick, ghost.position.y, ghost.velocity.y, consumed, total, next_flap]
	)


func _dev_diag() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build()


func _log_perf() -> void:
	if not _dev_diag():
		return
	var vis_play := 0
	for ghost in ghosts:
		if ghost.control == ReefFish.CTRL_PLAYBACK:
			vis_play += 1
	var avg := _perf_sum / float(maxi(_perf_n, 1))
	var avg_phys := _perf_phys_sum / float(maxi(_perf_n, 1))
	print(
		"[ghost-perf] seed=%d tick=%d vis=%d logical=%d nodes=%d avg_ms=%.2f worst_ms=%.2f avg_phys_ms=%.2f worst_phys_ms=%.2f fps=%.0f"
		% [
			GameSession.course_seed,
			match_tick,
			vis_play,
			logical_death.size(),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			avg,
			_perf_worst,
			avg_phys,
			_perf_phys_worst,
			Engine.get_frames_per_second(),
		]
	)


func _sample_pipe_spike(delta: float) -> void:
	if _spike_reported or _spike_phase == "idle":
		return
	var ms := delta * 1000.0
	if ms > float(_spike_worst[_spike_phase]):
		_spike_worst[_spike_phase] = ms
	if not started or finished or layout.size() < 2:
		return
	var px := RR.PLAYER_X + scroll
	var p1 := float(layout[0]["x"]) + RR.PLAYER_X - px
	var p2 := float(layout[1]["x"]) + RR.PLAYER_X - px
	if score >= 2:
		if _spike_phase != "score2":
			_spike_phase = "score2"
			return
		_spike_reported = true
		if not _dev_diag():
			return
		print(
			"[pipe-spike] start=%.1f pipe1=%.1f score1=%.1f pipe2=%.1f score2=%.1f"
			% [
				float(_spike_worst["start"]),
				float(_spike_worst["pipe1_approach"]),
				float(_spike_worst["score1"]),
				float(_spike_worst["pipe2_approach"]),
				float(_spike_worst["score2"]),
			]
		)
		return
	if score >= 1:
		_spike_phase = "pipe2_approach" if p2 < 220.0 else "score1"
		return
	if p1 < 220.0:
		_spike_phase = "pipe1_approach"


func _events_on() -> bool:
	return _events != null


func _setup_deep_dive() -> void:
	# Unlimited only. Daily Challenge keeps RR.HARPOON_EVERY and does not dive.
	if not GameplayEvents.applies_to(GameSession.match_mode, GameSession.practice_daily):
		return
	_events = GameplayEvents.new()
	_motion.configure(RR.VIEW_W)
	_dive_field = preload("res://scenes/deep_dive/dive_field.tscn").instantiate()
	_dive_field.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_dive_field)
	_dive_overlay = preload("res://scenes/deep_dive/dive_overlay.tscn").instantiate()
	add_child(_dive_overlay)
	_synced_state = GameplayEvents.State.NORMAL


func _ensure_course_ahead() -> void:
	if layout.size() - spawn_index > CourseBuilderScript.LOOKAHEAD:
		return
	var before := layout.size()
	var built: Dictionary = CourseBuilderScript.continuation(GameSession.course_seed, before)
	var placed: Array = CourseBuilderScript.placed_specs(layout, built.get("layout", []))
	if placed.is_empty():
		if not _course_extend_warned:
			_course_extend_warned = true
			push_error("[course] pipe extension produced nothing seed=%d size=%d spawn=%d" % [
				GameSession.course_seed, before, spawn_index,
			])
		return
	for spec in placed:
		layout.append(spec)
	_course_extend_warned = false
	var lanes: PackedInt32Array = built.get("harpoon_lanes", PackedInt32Array())
	for lane in lanes:
		_harpoon_lanes.append(int(lane))
	if spawn_index >= before:
		_recover_pipe_lead(before)


func _recover_pipe_lead(first_new: int) -> void:
	if first_new < 0 or first_new >= layout.size():
		return
	var lead := scroll + RR.VIEW_W + 80.0
	var have := float(layout[first_new]["x"])
	if have >= lead:
		return
	var shift := lead - have
	push_error("[course] pipes were behind the camera; shifting %d by %.1f" % [layout.size() - first_new, shift])
	for i in range(first_new, layout.size()):
		layout[i]["x"] = float(layout[i]["x"]) + shift


func _recover_daily_harpoon(delta: float) -> void:
	if _events_on() or _harpoon_beat == 0:
		_harpoon_stall = 0.0
		return
	var flying := false
	for spear in _harpoons:
		if spear.flying:
			flying = true
			break
	var stalled := false
	if _harpoon_beat == 1 and not _pipes_ahead():
		stalled = true
	elif _harpoon_beat == 2 and _warn_t <= 0.0:
		stalled = true
	elif _harpoon_beat == 3 and not flying:
		stalled = true
	if not stalled:
		_harpoon_stall = 0.0
		return
	_harpoon_stall += delta
	if _harpoon_stall < 0.75:
		return
	push_error("[course] harpoon beat %d stalled; restoring pipe spawning" % _harpoon_beat)
	for spear in _harpoons:
		spear.hide_idle()
	_harpoon_round = 0
	_harpoon_beat = 0
	_warn_t = 0.0
	_harpoon_stall = 0.0
	_pipes_until_harpoon = RR.HARPOON_EVERY


func _stage_was_abandoned(prev: int) -> bool:
	return (
		prev == GameplayEvents.State.HARPOON_PENDING
		or prev == GameplayEvents.State.HARPOON_WARNING
		or prev == GameplayEvents.State.HARPOON_ACTIVE
		or prev == GameplayEvents.State.DIVE_PENDING
		or prev == GameplayEvents.State.DIVE_TRANSITION_IN
		or prev == GameplayEvents.State.DEEP_DIVE
		or prev == GameplayEvents.State.DIVE_TRANSITION_OUT
	)


func _abandon_stage() -> void:
	for spear in _harpoons:
		spear.hide_idle()
	_harpoon_beat = 0
	_harpoon_round = 0
	_warn_t = 0.0
	_harpoon_stall = 0.0
	_halt_dive()
	_restore_swim_physics()
	_shift_upcoming_pipes(RR.VIEW_W + 200.0)


func _can_spawn_pipes() -> bool:
	if _events_on():
		return _events.pipes_allowed()
	return _harpoon_beat == 0


func _scoring_open() -> bool:
	if not _events_on():
		return true
	return _events.scoring_allowed()


func _harpoon_live() -> bool:
	if not _events_on():
		return false
	return (
		_events.state == GameplayEvents.State.HARPOON_WARNING
		or _events.state == GameplayEvents.State.HARPOON_ACTIVE
		or _harpoon_beat != 0
	)


func _corridor_clear() -> bool:
	if _harpoon_beat != 0:
		return false
	for spear in _harpoons:
		if spear.armed or spear.flying:
			return false
	for pair in pipes:
		var screen_x := pair.position.x - scroll
		if screen_x > -90.0 and screen_x < RR.VIEW_W + 36.0:
			return false
	return true


func _shift_upcoming_pipes(lead: float) -> void:
	if spawn_index >= layout.size():
		return
	var next_x := scroll + lead
	var shift := next_x - float(layout[spawn_index]["x"])
	if shift <= 0.0:
		return
	for i in range(spawn_index, layout.size()):
		layout[i]["x"] = float(layout[i]["x"]) + shift


func _sync_events() -> void:
	if not _events_on():
		return
	var now: int = _events.state
	if now == _synced_state:
		return
	var prev := _synced_state
	_synced_state = now
	if now == GameplayEvents.State.HARPOON_WARNING and prev != GameplayEvents.State.HARPOON_ACTIVE and _harpoon_beat == 0:
		_harpoon_round = 0
		_begin_harpoon_warn()
	elif now == GameplayEvents.State.DIVE_TRANSITION_IN:
		if _dive_field == null:
			_events.recover_swim("deep dive field missing")
			_synced_state = _events.state
			_abandon_stage()
		else:
			_enter_dive_transition()
	elif now == GameplayEvents.State.DEEP_DIVE:
		_enter_dive_play()
	elif now == GameplayEvents.State.DIVE_TRANSITION_OUT:
		_enter_dive_outro()
	elif now == GameplayEvents.State.RESUME_SWIMMING:
		_enter_swim_resume()
	elif now == GameplayEvents.State.NORMAL:
		if _stage_was_abandoned(prev):
			_abandon_stage()
		elif player and player.motion_lock:
			_restore_swim_physics()
	elif now == GameplayEvents.State.GAME_OVER:
		_halt_dive()


func _enter_dive_transition() -> void:
	for spear in _harpoons:
		spear.hide_idle()
	_harpoon_beat = 0
	_harpoon_round = 0
	_dive_origin = player.position if player else _swim_home
	_motion.reset(RR.VIEW_W * 0.5)
	_count_cue = 0
	_survived_cue = false
	if player:
		player.velocity = Vector2.ZERO
		player.hold_dive(0.0)
	if _dive_field:
		_dive_field.begin_ambient()
	_set_dive_ghosts(true)
	_shift_upcoming_pipes(RR.VIEW_W + 180.0)
	if _mission_track:
		_set_mission_presentation("hidden")
	var dive_n := _events.dive_number if _events else 0
	if dive_n != _whoosh_dive:
		_whoosh_dive = dive_n
		_cue("whoosh")
	_cue("checkpoint")


func _enter_dive_play() -> void:
	if player:
		_motion.reset(player.position.x)
		player.hold_dive(1.0)
	if _dive_field:
		var seed := GameSession.course_seed
		if seed == 0:
			seed = 1
		_dive_field.start(maxi(_events.dive_number, 1), seed + _events.dive_number * 997)
	if _mission_track:
		_mission_dives_entered += 1


func _enter_dive_outro() -> void:
	_dive_leave_from = player.position if player else Vector2(RR.VIEW_W * 0.5, DeepDiveConfig.FISH_Y)
	if _dive_field:
		_dive_field.stop_and_clear()
	if not _survived_cue:
		_survived_cue = true
		_cue("checkpoint")


func _enter_swim_resume() -> void:
	_restore_swim_physics()
	_shift_upcoming_pipes(RR.VIEW_W + 200.0)
	if world:
		world.set_depth_blend(0.0)
	if _dive_field:
		_dive_field.halt()
	if _dive_overlay:
		_dive_overlay.hide_all()
	if hud:
		hud.set_dive_timer("", false)
	_set_dive_ghosts(false)
	if _mission_track:
		_mission_dives_completed += 1
	if _mission_track and not paused:
		_set_mission_presentation("widget")


func _halt_dive() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx:
		sfx.stop("whoosh")
	if player:
		player.release_dive()
	_motion.reset(RR.PLAYER_X)
	if world:
		world.set_depth_blend(0.0)
	if _dive_field:
		_dive_field.halt()
	if _dive_overlay:
		_dive_overlay.hide_all()
	if hud:
		hud.set_dive_timer("", false)


func _restore_swim_physics() -> void:
	# The dive used to keep calling hold_dive through the resume window, which
	# left motion_lock set after the state returned to normal. Release once,
	# put the fish on the swim lane, and let tick() own gravity again.
	_motion.reset(RR.PLAYER_X)
	if player == null:
		return
	player.position = _swim_home
	player.release_dive()
	if started:
		player.started = true


func _update_dive_actor(delta: float) -> void:
	if player == null or _events == null:
		return
	if _events.steer_active():
		_motion.tick(delta)
	var tilt := 0.0
	if _events.steer_active() and absf(_motion.velocity) > 20.0:
		tilt = -signf(_motion.velocity) * 0.16
	player.set_dive_facing(_events.turn_amount(), tilt)
	player.hold_dive(0.0)
	var home := Vector2(_motion.x, DeepDiveConfig.FISH_Y)
	var turn := _events.turn_amount()
	match _events.state:
		GameplayEvents.State.DIVE_TRANSITION_IN:
			player.position = _dive_origin.lerp(home, _smoothstep(turn))
			if _dive_field:
				_dive_field.tick(delta, DeepDiveConfig.FISH_Y)
		GameplayEvents.State.DEEP_DIVE:
			player.position = home
			if _dive_field:
				var cleared := _dive_field.tick(delta, DeepDiveConfig.FISH_Y, _motion.x)
				_events.note_obstacles_dodged(cleared.x)
				_note_mission_dodges(cleared.x, cleared.y)
				if player.alive and _dive_field.take_hit():
					player.kill()
		GameplayEvents.State.DIVE_TRANSITION_OUT:
			var u := _smoothstep(1.0 - turn)
			player.position = _dive_leave_from.lerp(_swim_home, u)
			if _dive_field:
				_dive_field.tick(delta, DeepDiveConfig.FISH_Y)
		_:
			player.position = _swim_home


func _present_dive() -> void:
	if not _events_on():
		return
	var blend := _events.depth_blend()
	if world:
		world.set_depth_blend(blend)
	if _dive_field:
		_dive_field.set_blend(blend)
	if _dive_overlay:
		_dive_overlay.sync(_events)
	if hud:
		var show_timer := _events.state == GameplayEvents.State.DEEP_DIVE
		hud.set_dive_timer(str(_events.seconds_left()), show_timer)
	var count := _events.intro_count()
	if count > 0 and count != _count_cue:
		_count_cue = count
		_cue("checkpoint")


func _set_dive_ghosts(should_hide: bool) -> void:
	_dive_ghosts_hidden = should_hide
	if should_hide:
		for ghost in ghosts:
			ghost.visible = false
		return
	var shown := mini(_shown_ghosts, ghosts.size())
	for i in ghosts.size():
		ghosts[i].visible = i < shown and ghosts[i].alive


func _route_dive_pointer(event: InputEvent) -> bool:
	if not _events_on() or paused or finished:
		return false
	var diving := _events.steer_active()
	var owned := diving or _events.suppresses_flap()
	if not owned:
		return false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _button_node_at(touch.position):
			return false
		if touch.pressed and diving:
			_dive_tap(touch.position.x)
		_mark_input_handled()
		return true
	if event is InputEventScreenDrag:
		_mark_input_handled()
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _button_node_at(event.position):
			return false
		if event.pressed and diving:
			_dive_tap(event.position.x)
		_mark_input_handled()
		return true
	return false


func _dive_tap(screen_x: float) -> void:
	var before := _motion.lane
	_motion.nudge(-1.0 if screen_x < RR.VIEW_W * 0.5 else 1.0)
	if not _mission_track:
		return
	var change := DailyMissions.count_lane_change(before, _motion.lane)
	_mission_lanes += int(change.lanes)
	_mission_lanes_left += int(change.left)
	_mission_lanes_right += int(change.right)


func _note_mission_dodges(obstacles: int, mines: int) -> void:
	if not _mission_track or obstacles <= 0:
		return
	_mission_obstacles += obstacles
	_mission_mines += mines


func _mission_dive_facts() -> Dictionary:
	var seconds := mini(int(floorf(_mission_dive_seconds + 0.05)), _mission_dives_entered * 20)
	return {
		"dives_entered": _mission_dives_entered,
		"dives_completed": _mission_dives_completed,
		"dive_seconds": maxi(0, seconds),
		"lane_changes": _mission_lanes,
		"lanes_left": _mission_lanes_left,
		"lanes_right": _mission_lanes_right,
		"obstacles": _mission_obstacles,
		"mines": _mission_mines,
	}


func _smoothstep(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func _cue(id: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx:
		sfx.play(id, -11.0)


func debug_force_dive_play() -> void:
	if not _events_on() or player == null:
		return
	started = true
	_in_lobby = false
	player.alive = true
	player.started = true
	player.velocity = Vector2.ZERO
	player.position = Vector2(RR.VIEW_W * 0.5, DeepDiveConfig.FISH_Y)
	_events.debug_force_state(GameplayEvents.State.DEEP_DIVE)
	_synced_state = GameplayEvents.State.DEEP_DIVE
	_enter_dive_play()
