extends Node2D

const HarpoonScript := preload("res://scenes/game/harpoon.gd")
const SpriteTextScript := preload("res://scripts/sprite_text.gd")
const GhostRunScript := preload("res://scripts/ghost_run.gd")
const GhostBankScript := preload("res://scripts/ghost_bank.gd")
const CourseBuilderScript := preload("res://scripts/course_builder.gd")
const ShareServiceScript := preload("res://scripts/share/share_service.gd")

const SHARE_CARD_CROP_H := 798
const SHARE_PLACE_RECT := Rect2(700, 398, 300, 100)
const SHARE_CHECK_RECT := Rect2(700, 528, 300, 100)
const SHARE_CLOSE_RECT := Rect2(190, 798, 400, 165)
const SHARE_SHARE_RECT := Rect2(575, 798, 500, 170)
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
var pause_layer: CanvasLayer
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
var _ghost_bank
var _coins: Array[Sprite2D] = []
var _run_coins := 0
var _over_rank := 0
var _over_remaining := 0
var _coin_reward_claimed := false
var _reward_request_active := false
var _coin_offer_open := false
var _coin_ad_watch: Button
var _coin_ad_note: SpriteTextScript
var _eat_emulated_mouse := false
var _pending_start_flap := false
var _share_service: Node
var _share_layer: CanvasLayer
var _share_share_btn: Button
var _wipe_again: Button
var _wipe_share: TextureButton
var _wipe_menu: TextureButton
var _share_busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	cosmetic_rng.randomize()
	_ghost_bank = GhostBankScript.new()
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
	_spawn_school()
	hud = GameHUD.new()
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(hud)
	_build_pause()
	_prewarm_pipes()
	_prime_opening_pipes()
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


func _build_layout() -> void:
	var built: Dictionary = CourseBuilderScript.generate(GameSession.course_seed)
	layout.clear()
	for spec in built["layout"]:
		layout.append(spec)
	_harpoon_lanes = built["harpoon_lanes"]
	_harpoon_lane_i = 0


func _spawn_school() -> void:
	player = _make_fish(GameSession.selected_fish(), true, Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42), _player_label())
	player.control = ReefFish.CTRL_PLAYER
	player.died.connect(_on_player_died)
	swimming = 1
	var runs: Array = _ghost_bank.get_runs(GameSession.course_seed)
	var vis_recorded := mini(runs.size(), RR.GHOST_DRAW)
	for i in vis_recorded:
		var run = runs[i]
		var skin: String = run.fish_id if run.fish_id != "" else "fish_blue"
		var origin := Vector2(RR.PLAYER_X + 20.0 + float(i % 4) * 8.0, RR.VIEW_H * 0.42)
		var ghost := _make_fish(skin, false, origin, run.player_name)
		ghost.control = ReefFish.CTRL_PLAYBACK
		ghost.ghost_run = run
		ghost.died.connect(_on_ghost_died.bind(ghost))
		ghost.visible = false
		ghosts.append(ghost)
	var vis_ai := RR.GHOST_DRAW - vis_recorded
	for skin in RR.FISH_IDS:
		for i in vis_ai:
			if RR.FISH_IDS[i % RR.FISH_IDS.size()] != skin:
				continue
			var origin := Vector2(
				RR.PLAYER_X + cosmetic_rng.randf_range(-36.0, 28.0),
				RR.VIEW_H * 0.42 + cosmetic_rng.randf_range(-93.0, 93.0)
			)
			var ghost := _make_fish(skin, false, origin, _ghost_name(ghosts.size()))
			ghost.control = ReefFish.CTRL_AI
			ghost.survive_pipes = _roll_death_pipe()
			ghost.skill = clampf(cosmetic_rng.randfn(0.58, 0.18), 0.12, 0.95)
			ghost.rng.seed = GameSession.course_seed + ghosts.size() * 97
			ghost.died.connect(_on_ghost_died.bind(ghost))
			ghost.visible = false
			ghosts.append(ghost)
	for i in range(vis_recorded, runs.size()):
		if logical_death.size() >= RR.GHOST_COUNT - ghosts.size():
			break
		var run = runs[i]
		logical_death.append(run.death_tick)
		logical_alive.append(1)
		logical_names.append(run.player_name)
	var slots_left := RR.GHOST_COUNT - ghosts.size() - logical_death.size()
	for i in slots_left:
		phantoms.append(_roll_death_pipe())
	print(
		"[ghosts] seed=%d vis=%d playback=%d logical=%d phantoms=%d"
		% [GameSession.course_seed, ghosts.size(), vis_recorded, logical_death.size(), phantoms.size()]
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
	var name := GameSession.player_name.strip_edges()
	if name.is_empty():
		return "YOU"
	return name


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
	if event is InputEventScreenTouch:
		if event.pressed:
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
	match_tick = 0
	_eat_emulated_mouse = false
	visual_scroll = scroll
	player.reset_for_match()
	player.started = true
	for ghost in ghosts:
		if ghost.control == ReefFish.CTRL_PLAYBACK:
			ghost.reset_for_match()
		else:
			ghost.position.y = ghost.rest_y
			ghost.velocity = Vector2.ZERO
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
	_lobby_len = RR.LOBBY_SECS
	_shown_ghosts = 0
	swimming = 1
	hud.set_lobby(true, ceili(_lobby_len))
	hud.set_coins(GameSession.coins)


func _tick_lobby(delta: float) -> void:
	_lobby_t += delta
	var u := clampf(_lobby_t / _lobby_len, 0.0, 1.0)
	var filled := 1 + int(round(float(RR.GHOST_COUNT) * (1.0 - pow(1.0 - u, 2.15))))
	if u >= 1.0:
		filled = 1 + RR.GHOST_COUNT
	swimming = filled
	_reveal_ghosts(mini(ghosts.size(), filled - 1))
	hud.set_lobby(true, maxi(1, ceili(_lobby_len - _lobby_t)))
	if _lobby_t < _lobby_len:
		return
	_in_lobby = false
	swimming = 1 + RR.GHOST_COUNT
	_reveal_ghosts(ghosts.size())
	hud.set_lobby(false, 0)
	hud.set_countdown("GO")
	_go_t = 0.55
	_begin_run()


func _reveal_ghosts(count: int) -> void:
	while _shown_ghosts < count:
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
	if started and not finished:
		match_tick += 1
		_advance_playback()
		scroll += RR.PIPE_SPEED * delta
		course.position.x = -scroll
		if _harpoon_beat == 0:
			_spawn_pipes()
		_cull_pipes()
		_tick_harpoons(delta)
		_guide_ghosts()
		_collect_coins()
		_score_pipes()
		_sample_perf()
	player.tick(delta)
	if not finished:
		for ghost in ghosts:
			if ghost.alive:
				ghost.tick(delta)


func _process(delta: float) -> void:
	if PIPE_SPIKE_PROFILE:
		_sample_pipe_spike(delta)
	if _warmup_frames > 0:
		_warmup_frames -= 1
		if _warmup_frames <= 0 and _warmup:
			_warmup.visible = false
			if hud:
				hud.hide_prewarm()
	if not finished and not paused:
		world_scroll += RR.PIPE_SPEED * delta
	if started and not finished and not paused:
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
	var px := RR.PLAYER_X + scroll
	var gap := _upcoming_gap()
	if _harpoon_beat >= 2:
		gap = _lane_center(_safe_lane)
	var near_pipe := false
	for pair in pipes:
		if absf(pair.position.x - px) < 30.0:
			near_pipe = true
			break
	for ghost in ghosts:
		if not ghost.alive:
			continue
		if ghost.control == ReefFish.CTRL_PLAYBACK:
			continue
		ghost.look_ahead = gap
		ghost.pipes_cleared = score
		if ghost.position.y < RR.PLAY_TOP - 6.0 or ghost.position.y > RR.PLAY_BOTTOM + 16.0:
			ghost.kill()
			continue
		if near_pipe and score >= ghost.survive_pipes:
			ghost.kill()
	if near_pipe:
		for i in range(phantoms.size() - 1, -1, -1):
			if score >= phantoms[i]:
				phantoms.remove_at(i)
				swimming = maxi(swimming - 1, 0)


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
	var spr := Sprite2D.new()
	spr.texture = Sprites.tex("coin")
	spr.centered = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	spr.z_index = 7
	spr.scale = Vector2.ONE * 0.58
	spr.position = Vector2((float(a["x"]) + float(b["x"])) * 0.5 + RR.PLAYER_X, (float(a["gap_y"]) + float(b["gap_y"])) * 0.5)
	course_draw.add_child(spr)
	_coins.append(spr)


func _collect_coins() -> void:
	if player == null or not player.alive:
		return
	for spr in _coins:
		if spr == null or not spr.visible:
			continue
		var sx := spr.position.x - scroll
		if sx > RR.PLAYER_X + 24.0:
			continue
		if sx < RR.PLAYER_X - 48.0:
			spr.visible = false
			continue
		if absf(player.position.y - spr.position.y) > 58.0:
			continue
		spr.visible = false
		_run_coins += 1
		GameSession.add_coins(1)
		Sfx.play("coin", -10.0)
		if hud:
			hud.set_coins(GameSession.coins)


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
	Sfx.play_death(-10.0)
	swimming = maxi(swimming - 1, 0)
	var remaining := swimming
	var rank := remaining + 1
	_save_ghost_run()
	_log_perf()
	GameSession.record_run(score, rank, remaining)
	get_tree().create_timer(0.85).timeout.connect(_after_death.bind(rank, remaining))


func _after_death(rank: int, remaining: int) -> void:
	if overlay and is_instance_valid(overlay):
		return
	_over_rank = rank
	_over_remaining = remaining
	if _run_coins > 0:
		_show_coin_ad()
	else:
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
	dim.size = Vector2(RR.VIEW_W, RR.VIEW_H)
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


func _coin_ad_hotspot(origin: Vector2, scale: float, src: Rect2, pressed: Callable) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.position = origin + src.position * scale
	btn.size = src.size * scale
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(pressed)
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
		_on_rewarded_ad_unavailable()
		return
	if overlay:
		overlay.visible = false
	RewardedAds.show_rewarded_ad()


func _finish_coin_ad() -> void:
	if _coin_reward_claimed:
		return
	_coin_reward_claimed = true
	_reward_request_active = false
	_coin_offer_open = false
	var bonus := _run_coins
	if bonus > 0:
		GameSession.add_coins(bonus)
		_run_coins = 0
		if hud:
			hud.set_coins(GameSession.coins)
	_show_over(_over_rank, _over_remaining)


func _abandon_coin_offer() -> void:
	_coin_offer_open = false
	_reward_request_active = false
	_run_coins = 0
	_show_over(_over_rank, _over_remaining)


func _restore_coin_ad(message: String) -> void:
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


func _on_rewarded_ad_earned() -> void:
	if not _coin_offer_open:
		return
	if _coin_reward_claimed:
		return
	_finish_coin_ad()


func _on_rewarded_ad_closed() -> void:
	if _coin_reward_claimed:
		return
	if not _coin_offer_open:
		return
	_restore_coin_ad("")


func _on_rewarded_ad_failed(_reason: String) -> void:
	if _coin_reward_claimed:
		return
	_restore_coin_ad("No ad available")


func _on_rewarded_ad_unavailable() -> void:
	if _coin_reward_claimed:
		return
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
	dim.size = Vector2(RR.VIEW_W, RR.VIEW_H)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
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
	dim.size = Vector2(RR.VIEW_W, RR.VIEW_H)
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
	_share_layer.add_child(close_btn)
	_share_share_btn = Button.new()
	_share_share_btn.flat = true
	_share_share_btn.position = card_pos + SHARE_SHARE_RECT.position * card_scale
	_share_share_btn.size = SHARE_SHARE_RECT.size * card_scale
	_share_share_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_share_share_btn.pressed.connect(_share_card_pressed)
	_share_layer.add_child(_share_share_btn)


func _close_share_overlay(restore_wipe := true) -> void:
	_share_busy = false
	_share_share_btn = null
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
	var status := str(_share_service.share_image(png))
	if status == "busy" or status.is_empty():
		_on_share_finished(status)


func _on_share_finished(_status: String) -> void:
	_share_busy = false
	if _share_share_btn and is_instance_valid(_share_share_btn):
		_share_share_btn.disabled = false


func _retry() -> void:
	get_tree().paused = false
	GameSession.start_match()
	get_tree().reload_current_scene.call_deferred()


func _menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred("res://scenes/menu/main_menu.tscn")


func _set_paused(value: bool) -> void:
	if finished:
		return
	paused = value
	get_tree().paused = value
	if pause_layer:
		pause_layer.visible = value


func _build_pause() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 30
	pause_layer.visible = false
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_layer)
	var dim := ColorRect.new()
	dim.color = Palette.SHADOW
	dim.size = Vector2(RR.VIEW_W, RR.VIEW_H)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_layer.add_child(dim)
	var title := SpriteTextScript.new()
	title.position = Vector2(0, RR.VIEW_H * 0.30)
	title.configure("PAUSED", 34, Vector2(RR.VIEW_W, 42), HORIZONTAL_ALIGNMENT_CENTER)
	pause_layer.add_child(title)
	var resume := UIKit.make_icon_button(Sprites.tex("btn_play"), func(): _set_paused(false), 0.48)
	resume.position = Vector2(RR.VIEW_W * 0.5 - 33, RR.VIEW_H * 0.42)
	pause_layer.add_child(resume)
	var leave := UIKit.make_icon_button(Sprites.tex("btn_close"), _menu, 0.35)
	leave.position = Vector2(RR.VIEW_W * 0.5 - 24, RR.VIEW_H * 0.56)
	pause_layer.add_child(leave)


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
	for lane in 3:
		for slot in RR.HARPOON_PER_LANE:
			var spear = HarpoonScript.new()
			add_child(spear)
			spear.setup(lane, _lane_slot_y(lane, slot))
			_harpoons.append(spear)


func _lane_center(lane: int) -> float:
	var h := (RR.PLAY_BOTTOM - RR.PLAY_TOP) / 3.0
	return RR.PLAY_TOP + h * (float(lane) + 0.5)


func _lane_slot_y(lane: int, slot: int) -> float:
	var h := (RR.PLAY_BOTTOM - RR.PLAY_TOP) / 3.0
	var top := RR.PLAY_TOP + h * float(lane)
	return top + h * (float(slot) + 0.5) / float(RR.HARPOON_PER_LANE)


func _lane_of(y: float) -> int:
	var h := (RR.PLAY_BOTTOM - RR.PLAY_TOP) / 3.0
	return clampi(int((y - RR.PLAY_TOP) / h), 0, 2)


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
			if player.alive and _lane_of(player.position.y) != _safe_lane:
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
	if _harpoon_round == 0:
		hud.show_feed("Harpoons incoming")


func _pick_safe_lane() -> int:
	if _harpoon_lane_i < _harpoon_lanes.size():
		var lane := _harpoon_lanes[_harpoon_lane_i]
		_harpoon_lane_i += 1
		return lane
	return 1


func _begin_harpoon_fire() -> void:
	_harpoon_beat = 3
	Sfx.play("grappling")
	for spear in _harpoons:
		spear.fire()


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
	if spawn_index < layout.size():
		var next_x: float = scroll + RR.VIEW_W + 120.0
		var shift: float = next_x - float(layout[spawn_index]["x"])
		if shift > 0.0:
			for i in range(spawn_index, layout.size()):
				layout[i]["x"] = float(layout[i]["x"]) + shift
	_pipes_until_harpoon = RR.HARPOON_EVERY
	_harpoon_round = 0
	_harpoon_beat = 0


func _advance_playback() -> void:
	for ghost in ghosts:
		if ghost.control != ReefFish.CTRL_PLAYBACK or not ghost.alive:
			continue
		var run = ghost.ghost_run
		if run == null:
			continue
		var flaps = run.flap_ticks
		while ghost.next_flap_index < flaps.size() and flaps[ghost.next_flap_index] == match_tick:
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
	run.physics_version = RR.PHYSICS_VERSION
	run.course_version = RR.COURSE_VERSION
	run.course_seed = GameSession.course_seed
	run.player_name = _player_label()
	run.fish_id = GameSession.selected_fish()
	run.flap_ticks = _recorded_flaps
	run.death_tick = match_tick
	run.score = score
	_ghost_bank.save_run(run)


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


func _log_perf() -> void:
	var vis_play := 0
	var vis_ai := 0
	for ghost in ghosts:
		if ghost.control == ReefFish.CTRL_PLAYBACK:
			vis_play += 1
		else:
			vis_ai += 1
	var avg := _perf_sum / float(maxi(_perf_n, 1))
	var avg_phys := _perf_phys_sum / float(maxi(_perf_n, 1))
	print(
		"[ghost-perf] seed=%d tick=%d vis_rec=%d vis_ai=%d logical=%d phantoms=%d nodes=%d avg_ms=%.2f worst_ms=%.2f avg_phys_ms=%.2f worst_phys_ms=%.2f fps=%.0f"
		% [
			GameSession.course_seed,
			match_tick,
			vis_play,
			vis_ai,
			logical_death.size(),
			phantoms.size(),
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
