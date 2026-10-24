class_name DiveField
extends Node2D

const POOL := 8
const DECOR := 7

var _pool: Array[DiveObstacle] = []
var _live: Array[DiveObstacle] = []
var _specs: Array[Dictionary] = []
var _cursor := 0
var _scroll := 0.0
var _speed := 220.0
var _running := false
var _clearing := false
var _decor: Array[Sprite2D] = []
var _decor_y: PackedFloat32Array = PackedFloat32Array()
var _decor_speed: PackedFloat32Array = PackedFloat32Array()
var _wash: Polygon2D
var _prepared := false
var _hit := false
var _debug_fish := Vector2.ZERO
var _debug_lane := 0


func _ready() -> void:
	z_index = 9
	# These nodes are moved by hand. Interpolation smears a pooled obstacle
	# from its old offscreen position through the playfield for a frame.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = false
	prepare()


func prepare() -> void:
	if _prepared:
		return
	DiveAssets.preload_all()
	var packed := preload("res://scenes/deep_dive/dive_obstacle.tscn")
	for i in POOL:
		var obs := packed.instantiate() as DiveObstacle
		obs.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(obs)
		_pool.append(obs)
	_wash = Polygon2D.new()
	_wash.polygon = PackedVector2Array([
		Vector2(-20, -400),
		Vector2(RR.VIEW_W + 20, -400),
		Vector2(RR.VIEW_W + 20, RR.VIEW_H + 500),
		Vector2(-20, RR.VIEW_H + 500),
	])
	_wash.color = Color(0.02, 0.09, 0.2, 0.0)
	_wash.z_index = -4
	add_child(_wash)
	for i in DECOR:
		var spr := Sprite2D.new()
		spr.centered = true
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.texture = DiveAssets.tex(DiveAssets.decor_id(i))
		spr.scale = Vector2.ONE * (0.85 if i % 2 == 0 else 0.7)
		spr.modulate = Color(1, 1, 1, 0.55)
		spr.z_index = -1
		spr.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		spr.position = Vector2(36.0 if i % 2 == 0 else RR.VIEW_W - 36.0, 120.0 + float(i) * 130.0)
		add_child(spr)
		_decor.append(spr)
		_decor_y.append(spr.position.y)
		_decor_speed.append(0.35 + float(i % 3) * 0.08)
	_prepared = true


func begin_ambient() -> void:
	prepare()
	visible = true


func start(dive_number: int, seed: int) -> void:
	prepare()
	_release_all()
	_specs = DiveCourse.generate(dive_number, seed)
	_cursor = 0
	_scroll = 0.0
	_speed = DeepDiveConfig.DEEP_DIVE_SPEED
	_running = true
	_clearing = false
	visible = true


func stop_and_clear() -> void:
	_running = false
	_clearing = true
	for obs in _live:
		obs.set_lethal(false)


func halt() -> void:
	_running = false
	_clearing = false
	_hit = false
	_release_all()
	visible = false
	if _wash:
		_wash.color.a = 0.0


func set_blend(amount: float) -> void:
	if _wash:
		_wash.color = Color(0.02, 0.09, 0.2, clampf(amount, 0.0, 1.0) * 0.34)


func fall_speed() -> float:
	if not _running and not _clearing:
		return 0.0
	return _speed * (3.4 if _clearing else 1.0)


func take_hit() -> bool:
	if not _hit:
		return false
	_hit = false
	return true


# fish_x < 0 skips the lane test. Callers that only scroll, including the
# intro and the outro, pass the two-argument form.
func tick(delta: float, fish_y: float, fish_x: float = -1.0) -> Vector2i:
	var dodged := 0
	var mines := 0
	var step := _speed * maxf(delta, 0.0)
	if _clearing:
		step *= 3.4
	if _running or _clearing:
		_scroll += step
	var player_lane := -1
	if fish_x >= 0.0:
		player_lane = DeepDiveConfig.lane_at(fish_x)
		_debug_fish = Vector2(fish_x, fish_y)
		_debug_lane = player_lane
	_hit = false
	for i in range(_live.size() - 1, -1, -1):
		var obs := _live[i]
		obs.advance(step)
		obs.tick_local(delta)
		if player_lane > 0 and _running and obs.hits_player(player_lane, fish_y):
			_hit = true
		if _running and not obs.passed and obs.position.y < fish_y - 24.0:
			obs.passed = true
			dodged += 1
			if obs.kind == "mine":
				mines += 1
		if obs.position.y < -260.0:
			_release(obs)
	if _running:
		_spawn_ready()
	if _clearing and _live.is_empty():
		_clearing = false
	_tick_decor(step)
	if DeepDiveConfig.collision_debug():
		queue_redraw()
	return Vector2i(dodged, mines)


func _draw() -> void:
	if not DeepDiveConfig.collision_debug():
		return
	var font := ThemeDB.fallback_font
	var bounds := Color(0.45, 0.9, 1.0, 0.5)
	var top := -80.0
	var bottom := RR.screen_bottom()
	for lane in range(1, DeepDiveConfig.LANE_COUNT + 1):
		var left := DeepDiveConfig.lane_center(lane) - DeepDiveConfig.LANE_GAP * 0.5
		draw_line(Vector2(left, top), Vector2(left, bottom), bounds, 1.0)
		if font != null:
			draw_string(font, Vector2(left + 6.0, 28.0), str(lane), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, bounds)
	var right_edge := DeepDiveConfig.lane_center(DeepDiveConfig.LANE_COUNT) + DeepDiveConfig.LANE_GAP * 0.5
	draw_line(Vector2(right_edge, top), Vector2(right_edge, bottom), bounds, 1.0)
	for obs in _live:
		if not obs.active or obs.occupied.is_empty():
			continue
		var eligible := _debug_lane > 0 and obs.hits_player(_debug_lane, _debug_fish.y)
		var fill := Color(1.0, 0.25, 0.18, 0.85) if eligible else Color(1.0, 0.72, 0.2, 0.7)
		var band_y := obs.position.y + obs.band_center - obs.band_half
		var band_h := maxf(obs.band_half * 2.0, 4.0)
		for blocked in obs.occupied:
			var lane_left := DeepDiveConfig.lane_center(int(blocked)) - DeepDiveConfig.LANE_GAP * 0.5
			draw_rect(Rect2(lane_left, band_y, DeepDiveConfig.LANE_GAP, band_h), fill, false, 2.0)
		if font != null:
			var mark := "hit" if eligible else "clear"
			draw_string(font, Vector2(8.0, band_y - 4.0), "%s %s" % [obs.kind, mark], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fill)
	if _debug_lane > 0:
		var fish_left := DeepDiveConfig.lane_center(_debug_lane) - DeepDiveConfig.LANE_GAP * 0.5
		var fish_h := DeepDiveConfig.fish_half_y() * 2.0
		draw_rect(Rect2(fish_left, _debug_fish.y - DeepDiveConfig.fish_half_y(), DeepDiveConfig.LANE_GAP, fish_h), Color(0.3, 1.0, 0.6, 0.95), false, 2.0)
		if font != null:
			draw_string(font, Vector2(_debug_fish.x + 12.0, _debug_fish.y - 10.0), "lane %d" % _debug_lane, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 1.0, 0.6, 0.95))


func live_count() -> int:
	return _live.size()


func obstacle_nodes() -> int:
	var count := 0
	for child in get_children():
		if child is DiveObstacle:
			count += 1
	return count


func _spawn_ready() -> void:
	var limit := RR.screen_bottom() + 180.0
	while _cursor < _specs.size():
		var spec: Dictionary = _specs[_cursor]
		var screen_y := DeepDiveConfig.FISH_Y + float(spec["travel"]) - _scroll
		if screen_y > limit:
			return
		if _pool.is_empty():
			return
		var obs: DiveObstacle = _pool.pop_back() as DiveObstacle
		obs.place(screen_y)
		obs.present(spec)
		obs.reset_physics_interpolation()
		_live.append(obs)
		_cursor += 1


func _release(obs: DiveObstacle) -> void:
	var idx := _live.find(obs)
	if idx >= 0:
		_live.remove_at(idx)
	obs.deactivate()
	if not _pool.has(obs):
		_pool.append(obs)


func _release_all() -> void:
	for obs in _live.duplicate():
		_release(obs)
	_live.clear()


func _tick_decor(step: float) -> void:
	var span := RR.screen_bottom() + 220.0
	for i in _decor.size():
		_decor_y[i] -= step * _decor_speed[i]
		if _decor_y[i] < -80.0:
			_decor_y[i] += span
		_decor[i].position.y = roundf(_decor_y[i])
