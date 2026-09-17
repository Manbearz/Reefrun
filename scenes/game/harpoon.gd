class_name ReefHarpoon
extends Node2D

const FRAME_IDS: PackedStringArray = [
	"harpoon_00",
	"harpoon_01",
	"harpoon_02",
	"harpoon_03",
	"harpoon_04",
	"harpoon_05",
	"harpoon_06",
	"harpoon_07",
	"harpoon_08",
	"harpoon_09",
	"harpoon_10",
]

var lane := 0
var armed := false
var flying := false

var _sprite: Sprite2D
var _next: Sprite2D
var _warn: Node2D
var _warn_fill: Polygon2D
var _hit: Area2D
var _shape: CollisionShape2D
var _rect: RectangleShape2D
var _frames: Array[Texture2D] = []
var _vis_w := 120.0
var _anim := 0.0
var _pulse_t := 0.0
var _hold_t := 0.0
var _done := false


func setup(p_lane: int, y: float) -> void:
	lane = p_lane
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = 22
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for id in FRAME_IDS:
		_frames.append(Sprites.tex(id))
	_sprite = _make_sprite()
	_next = _make_sprite()
	_next.modulate.a = 0.0
	_hit = Area2D.new()
	_hit.collision_layer = 1
	_hit.collision_mask = 0
	_hit.monitoring = false
	_hit.monitorable = false
	_rect = RectangleShape2D.new()
	_shape = CollisionShape2D.new()
	_shape.shape = _rect
	_shape.disabled = true
	_hit.add_child(_shape)
	add_child(_hit)
	_build_warn()
	position = Vector2(RR.VIEW_W - 4.0, y)
	_show_index(0.0)
	visible = false


func hide_idle() -> void:
	armed = false
	flying = false
	_done = false
	visible = false
	_anim = 0.0
	_pulse_t = 0.0
	_hold_t = 0.0
	_warn.visible = false
	_set_hit(false)
	_show_index(0.0)


func arm() -> void:
	armed = true
	flying = false
	_done = false
	visible = true
	_anim = 0.0
	_pulse_t = 0.0
	_hold_t = 0.0
	_warn.visible = true
	_warn.modulate.a = 1.0
	_set_hit(false)
	_show_index(0.0)


func fire() -> void:
	if not armed:
		return
	flying = true
	_done = false
	_anim = 1.0
	_hold_t = 0.0
	_warn.visible = false
	_set_hit(true)
	_show_index(1.0)


func tick(delta: float) -> void:
	if armed and not flying:
		_pulse_t += delta
		var wave := 0.5 + 0.5 * sin(_pulse_t * TAU * 3.2)
		_warn.modulate.a = 0.45 + 0.55 * wave
		_warn.scale = Vector2.ONE * (0.88 + 0.18 * wave)
		return
	if not flying:
		return
	if _done:
		hide_idle()
		return
	_anim += delta / RR.HARPOON_FRAME
	var last := float(_frames.size() - 1)
	if _anim >= last:
		_show_index(last)
		_hold_t += delta
		if _hold_t >= RR.HARPOON_HOLD:
			_done = true
		return
	_show_index(_anim)


func span_left() -> float:
	return position.x - _vis_w


func span_right() -> float:
	return position.x


func _make_sprite() -> Sprite2D:
	var spr := Sprite2D.new()
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	spr.scale = Vector2(RR.HARPOON_SCALE_X, RR.HARPOON_SCALE_Y)
	add_child(spr)
	return spr


func _build_warn() -> void:
	_warn = Node2D.new()
	_warn.z_index = 8
	_warn.position = Vector2(-10.0, 0.0)
	_warn.visible = false
	add_child(_warn)
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([
		Vector2(-26.0, 0.0),
		Vector2(8.0, -18.0),
		Vector2(8.0, 18.0),
	])
	shadow.color = Color(0.28, 0.02, 0.06, 0.9)
	_warn.add_child(shadow)
	_warn_fill = Polygon2D.new()
	_warn_fill.polygon = PackedVector2Array([
		Vector2(-22.0, 0.0),
		Vector2(5.0, -15.0),
		Vector2(5.0, 15.0),
	])
	_warn_fill.color = Color(1.0, 0.18, 0.16)
	_warn.add_child(_warn_fill)
	var inner := Polygon2D.new()
	inner.polygon = PackedVector2Array([
		Vector2(-8.0, 0.0),
		Vector2(1.0, -6.0),
		Vector2(1.0, 6.0),
	])
	inner.color = Color(1.0, 0.92, 0.78, 0.95)
	_warn.add_child(inner)


func _show_index(p: float) -> void:
	var last := _frames.size() - 1
	if last < 0:
		return
	var i := clampi(int(p), 0, last)
	var frac := 0.0
	if i < last:
		frac = clampf(p - float(i), 0.0, 1.0)
	else:
		frac = 0.0
	var tex_a := _frames[i]
	_apply_tex(_sprite, tex_a)
	_sprite.modulate.a = 1.0 - frac
	if frac > 0.001 and i < last:
		var tex_b := _frames[i + 1]
		_apply_tex(_next, tex_b)
		_next.modulate.a = frac
		_next.visible = true
		var wa := _tex_w(tex_a)
		var wb := _tex_w(tex_b)
		_vis_w = lerpf(wa, wb, frac) * RR.HARPOON_SCALE_X
	else:
		_next.visible = false
		_next.modulate.a = 0.0
		_vis_w = _tex_w(tex_a) * RR.HARPOON_SCALE_X
	var h := 28.0
	if tex_a:
		h = float(tex_a.get_height()) * RR.HARPOON_SCALE_Y * 0.42
	_rect.size = Vector2(_vis_w * 0.9, h)
	_hit.position = Vector2(-_vis_w * 0.5, 0.0)


func _apply_tex(spr: Sprite2D, tex: Texture2D) -> void:
	spr.texture = tex
	spr.region_enabled = false
	if tex == null:
		return
	spr.offset = Vector2(-float(tex.get_width()), -float(tex.get_height()) * 0.5)


func _tex_w(tex: Texture2D) -> float:
	if tex == null:
		return 176.0
	return float(tex.get_width())


func _set_hit(on: bool) -> void:
	_hit.monitorable = on
	_shape.disabled = not on
