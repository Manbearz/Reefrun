class_name PipePair
extends Node2D

const MAX_SEGS := 5

var gap_y := 0.0
var gap_h := 0.0
var scored := false
var style := "pipe_kelp"
var visual: Node2D
var active := false

var _top: Array[Sprite2D] = []
var _bot: Array[Sprite2D] = []
var _top_hit: Area2D
var _bot_hit: Area2D
var _top_shape: CollisionShape2D
var _bot_shape: CollisionShape2D
var _top_rect: RectangleShape2D
var _bot_rect: RectangleShape2D
var _ready_pool := false


func _alloc() -> void:
	if _ready_pool:
		return
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visual = Node2D.new()
	visual.z_index = 6
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for i in MAX_SEGS:
		_top.append(_make_sprite())
		_bot.append(_make_sprite())
	_top_hit = _make_hit(true)
	_bot_hit = _make_hit(false)
	_ready_pool = true
	deactivate()


func _make_sprite() -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.visible = false
	visual.add_child(sprite)
	return sprite


func _make_hit(is_top: bool) -> Area2D:
	var hit := Area2D.new()
	hit.collision_layer = 1
	hit.collision_mask = 0
	hit.monitoring = false
	hit.monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	shape.shape = rect
	shape.disabled = true
	hit.add_child(shape)
	add_child(hit)
	if is_top:
		_top_shape = shape
		_top_rect = rect
	else:
		_bot_shape = shape
		_bot_rect = rect
	return hit


func rebuild(p_style: String, p_gap_y: float, p_gap_h: float) -> void:
	_alloc()
	style = p_style
	gap_y = p_gap_y
	gap_h = p_gap_h
	scored = false
	var tex := Sprites.tex(style)
	if tex == null:
		return
	var half := p_gap_h * 0.5
	_place_column(_top, _top_hit, _top_rect, _top_shape, tex, p_gap_y - half, true)
	_place_column(_bot, _bot_hit, _bot_rect, _bot_shape, tex, p_gap_y + half, false)


func activate() -> void:
	active = true
	visual.visible = true
	_top_hit.monitorable = true
	_bot_hit.monitorable = true
	_top_shape.disabled = false
	_bot_shape.disabled = false


func deactivate() -> void:
	active = false
	scored = true
	visual.visible = false
	_top_hit.monitorable = false
	_bot_hit.monitorable = false
	_top_shape.disabled = true
	_bot_shape.disabled = true


func _place_column(
	sprites: Array[Sprite2D],
	hit: Area2D,
	rect: RectangleShape2D,
	shape: CollisionShape2D,
	tex: Texture2D,
	lip_y: float,
	top: bool
) -> void:
	var scale := RR.PIPE_SCALE
	var pipe_h := tex.get_height() * scale
	var pipe_w := tex.get_width() * scale
	var join := pipe_h * RR.PIPE_JOIN
	var step := maxf(pipe_h - join, pipe_h * 0.5)
	var span := (lip_y + 8.0) if top else (RR.VIEW_H - lip_y + 8.0)
	var count := clampi(maxi(1, int(ceil(span / step))), 1, MAX_SEGS)
	for i in MAX_SEGS:
		var sprite := sprites[i]
		if i >= count:
			sprite.visible = false
			continue
		var py := (lip_y - pipe_h * 0.5 - step * i) if top else (lip_y + pipe_h * 0.5 + step * i)
		if py + pipe_h * 0.5 < -24.0 or py - pipe_h * 0.5 > RR.VIEW_H + 24.0:
			sprite.visible = false
			continue
		sprite.texture = tex
		sprite.scale = Vector2(scale, scale)
		sprite.position = Vector2(0, py)
		sprite.visible = true
	var lip_inset := pipe_h * RR.PIPE_LIP_INSET
	var col_h := pipe_h + float(count - 1) * step - lip_inset
	rect.size = Vector2(pipe_w * RR.PIPE_HIT_WIDTH, col_h)
	if top:
		hit.position = Vector2(0, lip_y - lip_inset - col_h * 0.5)
	else:
		hit.position = Vector2(0, lip_y + lip_inset + col_h * 0.5)
	shape.disabled = not active
