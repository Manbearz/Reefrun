class_name ReefWorld
extends Node2D

var _scroll := 0.0
var _ground_a: Sprite2D
var _ground_b: Sprite2D
var _ceiling: Area2D
var _floor: Area2D
var _bubbles: Array[Sprite2D] = []
var _bubble_x := PackedFloat32Array()
var _bubble_y := PackedFloat32Array()
var _bubble_speed := PackedFloat32Array()
var _bubble_phase := PackedFloat32Array()
var _bubble_wobble := PackedFloat32Array()
var _last_scroll := 0.0
var _bg_layer: CanvasLayer
var _shark: Sprite2D
var _shark_active := false
var _shark_wait := 0.0
var _shark_speed := 0.0
var _shark_bob := 0.0
var _shark_y := 0.0
var _shark_rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = -8
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_backdrop()
	_build_ceiling()
	_build_ground()
	_build_bubbles()


func _build_backdrop() -> void:
	_bg_layer = CanvasLayer.new()
	_bg_layer.layer = -20
	add_child(_bg_layer)
	var tex := Sprites.tex("background")
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.position = Vector2(RR.VIEW_W * 0.5, RR.VIEW_H * 0.5)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if tex:
		var cover := maxf(RR.VIEW_W / float(tex.get_width()), RR.VIEW_H / float(tex.get_height()))
		spr.scale = Vector2(cover, cover)
	_bg_layer.add_child(spr)
	_build_shark()


func _build_ceiling() -> void:
	_ceiling = Area2D.new()
	_ceiling.position = Vector2(RR.VIEW_W * 0.5, RR.PLAY_TOP * 0.5 - 8.0)
	_ceiling.collision_layer = 1
	_ceiling.monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(RR.VIEW_W + 40, maxf(RR.PLAY_TOP - 16.0, 8.0))
	shape.shape = rect
	_ceiling.add_child(shape)
	add_child(_ceiling)


func _build_ground() -> void:
	var tex := Sprites.tex("ground")
	if tex == null:
		push_error("Missing ground texture")
		return
	var scale := 0.78
	var gy := RR.VIEW_H - tex.get_height() * scale + 18.0
	_ground_a = _tile(tex, gy, scale, 12)
	_ground_b = _tile(tex, gy, scale, 12)
	_ground_b.position.x = tex.get_width() * scale
	_floor = Area2D.new()
	var floor_top := RR.VIEW_H + 24.0
	var floor_h := 80.0
	_floor.position = Vector2(RR.VIEW_W * 0.5, floor_top + floor_h * 0.5)
	_floor.collision_layer = 1
	_floor.monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(RR.VIEW_W + 80, floor_h)
	shape.shape = rect
	_floor.add_child(shape)
	add_child(_floor)


func _tile(tex: Texture2D, y: float, scale: float, z: int) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	spr.position = Vector2(0, y)
	spr.scale = Vector2.ONE * scale
	spr.z_index = z
	add_child(spr)
	return spr


func follow(scroll: float) -> void:
	_scroll = scroll
	if _ground_a == null or _ground_a.texture == null:
		return
	var gw := _ground_a.texture.get_width() * _ground_a.scale.x
	var gx := fmod(-scroll, gw)
	if gx > 0.0:
		gx -= gw
	_ground_a.position.x = gx
	_ground_b.position.x = gx + gw


func tick_decor(delta: float) -> void:
	var drift := _scroll - _last_scroll
	_last_scroll = _scroll
	var top := RR.PLAY_TOP - 70.0
	var bot := RR.VIEW_H + 50.0
	var span := bot - top
	for i in _bubbles.size():
		_bubble_phase[i] += delta
		_bubble_y[i] -= _bubble_speed[i] * delta
		_bubble_x[i] -= drift * 0.28
		if _bubble_y[i] < top:
			_bubble_y[i] += span
			_bubble_x[i] = fmod(_bubble_x[i] + RR.VIEW_W * 1.4, RR.VIEW_W + 80.0) - 40.0
		if _bubble_x[i] < -50.0:
			_bubble_x[i] += RR.VIEW_W + 100.0
		elif _bubble_x[i] > RR.VIEW_W + 50.0:
			_bubble_x[i] -= RR.VIEW_W + 100.0
		var wobble := sin(_bubble_phase[i]) * _bubble_wobble[i]
		_bubbles[i].position = Vector2(_bubble_x[i] + wobble, _bubble_y[i])
	_tick_shark(delta)


func _build_bubbles() -> void:
	var tex := Sprites.tex("bubbles_small")
	if tex == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 12:
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = true
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.z_index = 3
		spr.scale = Vector2.ONE * rng.randf_range(0.22, 0.48)
		spr.modulate = Color(1, 1, 1, rng.randf_range(0.42, 0.72))
		add_child(spr)
		_bubbles.append(spr)
		_bubble_x.append(rng.randf_range(-20.0, RR.VIEW_W + 20.0))
		_bubble_y.append(rng.randf_range(RR.PLAY_TOP, RR.VIEW_H))
		_bubble_speed.append(rng.randf_range(18.0, 42.0))
		_bubble_phase.append(rng.randf() * TAU)
		_bubble_wobble.append(rng.randf_range(6.0, 16.0))
		spr.position = Vector2(_bubble_x[i], _bubble_y[i])


func _build_shark() -> void:
	var tex := Sprites.tex("shark_far")
	if tex == null or _bg_layer == null:
		return
	_shark_rng.randomize()
	_shark = Sprite2D.new()
	_shark.texture = tex
	_shark.centered = true
	_shark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_shark.z_index = 1
	_shark.visible = false
	_shark.modulate = Color(0.58, 0.74, 0.9, 0.55)
	_bg_layer.add_child(_shark)
	_shark_wait = _shark_rng.randf_range(3.5, 9.0)


func _tick_shark(delta: float) -> void:
	if _shark == null:
		return
	if not _shark_active:
		_shark_wait -= delta
		if _shark_wait <= 0.0:
			_launch_shark()
		return
	_shark_bob += delta
	_shark.position.x += _shark_speed * delta
	_shark.position.y = _shark_y + sin(_shark_bob * 1.15) * 5.0
	var tex_w := 140.0
	if _shark.texture:
		tex_w = float(_shark.texture.get_width())
	var half: float = tex_w * absf(_shark.scale.x) * 0.5
	if _shark.position.x < -half - 20.0 or _shark.position.x > RR.VIEW_W + half + 20.0:
		_shark_active = false
		_shark.visible = false
		_shark_wait = _shark_rng.randf_range(11.0, 24.0)


func _launch_shark() -> void:
	if _shark == null or _shark.texture == null:
		_shark_wait = 12.0
		return
	var shark_scale: float = _shark_rng.randf_range(0.48, 0.72)
	var going_right := _shark_rng.randf() > 0.5
	var half: float = float(_shark.texture.get_width()) * shark_scale * 0.5
	_shark.scale = Vector2(shark_scale, shark_scale)
	_shark.flip_h = going_right
	_shark_speed = _shark_rng.randf_range(26.0, 42.0)
	if not going_right:
		_shark_speed = -_shark_speed
	_shark_y = _shark_rng.randf_range(RR.VIEW_H * 0.64, RR.VIEW_H * 0.78)
	_shark_bob = _shark_rng.randf() * TAU
	if going_right:
		_shark.position = Vector2(-half - 16.0, _shark_y)
	else:
		_shark.position = Vector2(RR.VIEW_W + half + 16.0, _shark_y)
	_shark.visible = true
	_shark_active = true
