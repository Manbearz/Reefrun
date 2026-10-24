class_name DiveObstacle
extends Node2D

const SPRITE_SLOTS := 4
const HIT_SLOTS := 2

var kind := ""
var gap_x := 0.0
var gap_w := 0.0
var travel := 0.0
var passed := false
var active := false
# Lanes this obstacle can kill, and the vertical window of the solid body.
# The opening from the course is never included. Physics shapes stay off so
# a wide sprite cannot reach a neighboring lane.
var occupied := PackedInt32Array()
var band_center := 0.0
var band_half := 0.0
var lethal := false

var _sprites: Array[Sprite2D] = []
var _hits: Array[Area2D] = []
var _shapes: Array[CollisionShape2D] = []
var _rects: Array[RectangleShape2D] = []
var _circles: Array[CircleShape2D] = []
var _rest: Array[Vector2] = []
var _drift_t := 0.0
var _drift_amp := 0.0
var _bob := 0.0
var _built := false
var _y := 0.0
var _hit_token: Array[int] = []
var _slot_armed: Array[bool] = []
var _safe_lane := DeepDiveConfig.CENTER_LANE
var _safe_span := 1
var _has_band := false


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_alloc()
	deactivate()


func place(y: float) -> void:
	_y = y
	position = Vector2(0.0, roundf(_y))


func advance(step: float) -> void:
	_y -= step
	position.y = roundf(_y)


func present(spec: Dictionary) -> void:
	_alloc()
	kind = str(spec.get("kind", "net"))
	gap_x = float(spec.get("gap_x", 180.0))
	gap_w = float(spec.get("gap_w", 180.0))
	travel = float(spec.get("travel", 0.0))
	passed = false
	active = true
	visible = true
	lethal = true
	occupied = PackedInt32Array()
	band_center = 0.0
	band_half = 0.0
	_has_band = false
	_safe_lane = clampi(int(spec.get("lane", DeepDiveConfig.CENTER_LANE)), 1, DeepDiveConfig.LANE_COUNT)
	_safe_span = clampi(int(spec.get("span", 1)), 1, DeepDiveConfig.LANE_COUNT)
	_drift_t = 0.0
	_drift_amp = float(spec.get("drift", 0.0))
	_bob = float(int(spec.get("variant", 0))) * 0.65
	_hide_all()
	match kind:
		"pillar":
			_layout_pillar(spec)
		"mine":
			_layout_mine(spec)
		"jelly":
			_layout_jelly(spec)
		"wreck":
			_layout_wreck(spec)
		_:
			_layout_net(spec)


func deactivate() -> void:
	active = false
	lethal = false
	visible = false
	passed = true
	occupied = PackedInt32Array()
	_has_band = false
	_hide_all()


func hits_player(player_lane: int, fish_y: float) -> bool:
	if not active or not lethal or not _has_band:
		return false
	if player_lane < 1 or player_lane > DeepDiveConfig.LANE_COUNT:
		return false
	if not occupied.has(player_lane):
		return false
	var reach := band_half + DeepDiveConfig.fish_half_y()
	return absf(position.y + band_center - fish_y) <= reach


func set_lethal(on: bool) -> void:
	lethal = on and active
	if on:
		return
	for i in _hits.size():
		_arm_slot(i, false)
		# The outro calls this before the fish checks overlaps again on this
		# same frame, so the disarm has to land now, not on the next idle.
		_commit_slot(i, _hit_token[i], false)


func tick_local(delta: float) -> void:
	if not active:
		return
	_drift_t += delta
	var sway := 0.0
	if kind == "mine" or kind == "jelly":
		sway = sin(_drift_t * 1.15) * _drift_amp
	var bob := 0.0
	if kind == "jelly":
		bob = sin(_drift_t * 2.2 + _bob) * 9.0
	for i in _sprites.size():
		if not _sprites[i].visible:
			continue
		var rest := _rest[i]
		var nx := rest.x
		if kind == "mine" or kind == "jelly":
			nx = _keep_out_of_gap(rest.x + sway, rest.x)
		_sprites[i].position = Vector2(roundf(nx), roundf(rest.y + bob))
		if (kind == "mine" or kind == "jelly") and i < _slot_armed.size() and _slot_armed[i]:
			_hits[i].position = _sprites[i].position


func _alloc() -> void:
	if _built:
		return
	z_index = 12
	for i in SPRITE_SLOTS:
		var spr := Sprite2D.new()
		spr.centered = true
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.visible = false
		add_child(spr)
		_sprites.append(spr)
		_rest.append(Vector2.ZERO)
	for i in HIT_SLOTS:
		var hit := Area2D.new()
		hit.collision_layer = 1
		hit.collision_mask = 0
		hit.monitoring = false
		hit.monitorable = false
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		var circle := CircleShape2D.new()
		shape.shape = rect
		shape.disabled = true
		hit.add_child(shape)
		add_child(hit)
		_hits.append(hit)
		_shapes.append(shape)
		_rects.append(rect)
		_circles.append(circle)
		_hit_token.append(0)
		_slot_armed.append(false)
	_built = true


func _hide_all() -> void:
	for spr in _sprites:
		spr.visible = false
		spr.rotation = 0.0
		spr.flip_h = false
	for i in _hits.size():
		_arm_slot(i, false)


func _show(slot: int, texture: Texture2D, at: Vector2, scale: Vector2, flip := false, rot := 0.0) -> void:
	if slot < 0 or slot >= _sprites.size() or texture == null:
		return
	var spr := _sprites[slot]
	var snapped := Vector2(roundf(at.x), roundf(at.y))
	spr.texture = texture
	spr.position = snapped
	spr.scale = scale
	spr.flip_h = flip
	spr.rotation = rot
	spr.visible = true
	_rest[slot] = snapped


func _rect(slot: int, center: Vector2, size: Vector2) -> void:
	if slot < 0 or slot >= _hits.size():
		return
	var rect := _rects[slot]
	rect.size = Vector2(maxf(size.x, 8.0), maxf(size.y, 8.0))
	_shapes[slot].shape = rect
	_hits[slot].position = center
	_arm_slot(slot, true)


func _circle(slot: int, center: Vector2, radius: float) -> void:
	if slot < 0 or slot >= _hits.size():
		return
	var circle := _circles[slot]
	circle.radius = maxf(radius, 8.0)
	_shapes[slot].shape = circle
	_hits[slot].position = center
	_arm_slot(slot, true)


# Death runs inside the fish area signal, while the physics server is flushing
# queries. monitorable and shape.disabled are changed on the next idle frame,
# which is outside that flush. The token drops a deferred disarm if the pool
# armed this obstacle again before the deferred call runs.
func _arm_slot(slot: int, armed: bool) -> void:
	if slot < 0 or slot >= _hits.size():
		return
	_slot_armed[slot] = armed
	_hit_token[slot] += 1
	var token := _hit_token[slot]
	_commit_slot.call_deferred(slot, token, armed)


func _commit_slot(slot: int, token: int, armed: bool) -> void:
	if slot < 0 or slot >= _hit_token.size() or token != _hit_token[slot]:
		return
	if not is_instance_valid(_hits[slot]) or not is_instance_valid(_shapes[slot]):
		return
	_hits[slot].monitorable = armed
	_shapes[slot].disabled = not armed


# The solid body, not the texture rectangle. Safe opening lanes are dropped
# inside lanes_under, so a shape that leans across the gap cannot kill there.
func _cover(x0: float, x1: float, y_center: float, half_h: float) -> void:
	var lanes := DeepDiveConfig.lanes_under(x0, x1, _safe_lane, _safe_span)
	for lane in lanes:
		var blocked := int(lane)
		if not occupied.has(blocked):
			occupied.append(blocked)
	var half := maxf(half_h, 1.0)
	if not _has_band:
		band_center = y_center
		band_half = half
		_has_band = true
		return
	var top := minf(band_center - band_half, y_center - half)
	var bot := maxf(band_center + band_half, y_center + half)
	band_center = (top + bot) * 0.5
	band_half = (bot - top) * 0.5


func _keep_out_of_gap(x: float, rest_x: float) -> float:
	var guard := 18.0
	if rest_x <= gap_x + gap_w * 0.5:
		return minf(x, gap_x - guard)
	return maxf(x, gap_x + gap_w + guard)


func _layout_net(spec: Dictionary) -> void:
	var tex := DiveAssets.tex(DiveAssets.net_id(int(spec.get("variant", 0))))
	if tex == null:
		return
	var src_w := float(tex.get_width())
	var src_h := float(tex.get_height())
	_fit_span(0, tex, 0.0, gap_x, src_w, src_h, false)
	_fit_span(1, tex, gap_x + gap_w, RR.VIEW_W, src_w, src_h, true)


func _fit_span(slot: int, tex: Texture2D, left: float, right: float, src_w: float, src_h: float, flip: bool) -> void:
	var span := right - left
	if span < 36.0:
		return
	var scale_x := clampf(span / src_w, 0.55, 1.3)
	var scale := Vector2(scale_x, clampf(scale_x, 0.7, 1.05))
	var center_x := (left + right) * 0.5
	_show(slot, tex, Vector2(center_x, 0.0), scale, flip)
	var drawn_w := src_w * scale_x
	var drawn_h := src_h * scale.y
	_cover(center_x - drawn_w * 0.5, center_x + drawn_w * 0.5, 6.0, drawn_h * 0.21)


func _layout_pillar(spec: Dictionary) -> void:
	var side := clampi(int(spec.get("side", 2)), 0, 2)
	if side == 2 and gap_w >= 150.0 and gap_w <= 250.0 and int(spec.get("variant", 0)) % 3 == 0:
		if _layout_arch():
			return
	var tex := DiveAssets.tex(DiveAssets.rock_id(int(spec.get("variant", 0))))
	if tex == null:
		return
	var placed := 0
	if side != 1:
		placed = _place_rock(placed, tex, true)
	if side != 0 and placed < HIT_SLOTS:
		_place_rock(placed, tex, false)


func _layout_arch() -> bool:
	var tex := DiveAssets.tex("arch")
	if tex == null:
		return false
	var mouth := 0.36
	var scale := clampf(gap_w / (float(tex.get_width()) * mouth), 0.8, 1.45)
	var display_w := float(tex.get_width()) * scale
	var display_h := float(tex.get_height()) * scale
	var center := gap_x + gap_w * 0.5
	_show(0, tex, Vector2(center, -display_h * 0.08), Vector2.ONE * scale)
	var stone_h := display_h * 0.46
	var side_w := maxf((display_w - gap_w) * 0.42, 18.0)
	var left_x := center - gap_w * 0.5 - side_w * 0.5 - 8.0
	var right_x := center + gap_w * 0.5 + side_w * 0.5 + 8.0
	var band_y := -display_h * 0.16
	_cover(left_x - side_w * 0.5, left_x + side_w * 0.5, band_y, stone_h * 0.5)
	_cover(right_x - side_w * 0.5, right_x + side_w * 0.5, band_y, stone_h * 0.5)
	return true


func _place_rock(slot: int, tex: Texture2D, left: bool) -> int:
	var width := float(tex.get_width())
	var height := float(tex.get_height())
	var room := (gap_x - 28.0) if left else (RR.VIEW_W - (gap_x + gap_w) - 28.0)
	var hit_w := minf(width * 0.62, maxf(room, 18.0))
	var hit_center := (gap_x - 14.0 - hit_w * 0.5) if left else (gap_x + gap_w + 14.0 + hit_w * 0.5)
	hit_center = clampf(hit_center, hit_w * 0.5 + 4.0, RR.VIEW_W - hit_w * 0.5 - 4.0)
	_show(slot, tex, Vector2(hit_center, 10.0), Vector2.ONE, not left)
	_cover(hit_center - hit_w * 0.5, hit_center + hit_w * 0.5, 10.0, height * 0.35)
	return slot + 1


func _layout_mine(spec: Dictionary) -> void:
	var id := DiveAssets.mine_id(int(spec.get("variant", 0)))
	var tex := DiveAssets.tex(id)
	if tex == null:
		return
	var chain := id.begins_with("mine_chain")
	var scale := 0.92 if chain else 1.0
	var focus := -float(tex.get_height()) * scale * 0.2 if chain else 0.0
	var radius := float(tex.get_width()) * scale * (0.3 if chain else 0.32)
	var slots: Array[bool] = []
	var side := int(spec.get("side", 0))
	if side != 1 and gap_x > 70.0:
		slots.append(true)
	if side != 0 and RR.VIEW_W - (gap_x + gap_w) > 70.0:
		slots.append(false)
	if slots.is_empty():
		slots.append(gap_x > RR.VIEW_W * 0.5)
	for i in mini(slots.size(), HIT_SLOTS):
		var left: bool = slots[i]
		var zone_l := 18.0 if left else gap_x + gap_w + 18.0
		var zone_r := gap_x - 18.0 if left else RR.VIEW_W - 18.0
		var x := (zone_l + zone_r) * 0.5
		_show(i, tex, Vector2(x, focus), Vector2.ONE * scale)
		_cover(x - radius, x + radius, focus, radius)


func _layout_jelly(spec: Dictionary) -> void:
	var tex := DiveAssets.tex(DiveAssets.jelly_id(int(spec.get("variant", 0))))
	if tex == null:
		return
	var left := int(spec.get("side", 0)) != 1
	var zone_l := 16.0 if left else gap_x + gap_w + 16.0
	var zone_r := gap_x - 16.0 if left else RR.VIEW_W - 16.0
	if zone_r - zone_l < 24.0:
		left = gap_x > RR.VIEW_W * 0.5
		zone_l = 16.0 if left else gap_x + gap_w + 16.0
		zone_r = gap_x - 16.0 if left else RR.VIEW_W - 16.0
	var x := (zone_l + zone_r) * 0.5
	_show(0, tex, Vector2(x, 0.0), Vector2.ONE)
	var bell := float(tex.get_width()) * 0.3
	_cover(x - bell, x + bell, float(tex.get_height()) * 0.08, bell)


func _layout_wreck(spec: Dictionary) -> void:
	var planks := int(spec.get("variant", 0)) % 2 == 0
	var tex := DiveAssets.tex("planks" if planks else "spears")
	if tex == null:
		return
	var left := int(spec.get("side", 0)) == 0
	var scale := 0.92 if planks else 0.84
	var width := float(tex.get_width()) * scale
	var height := float(tex.get_height()) * scale
	var x := gap_x - width * 0.28 if left else gap_x + gap_w + width * 0.28
	x = clampf(x, 30.0, RR.VIEW_W - 30.0)
	var rot := 0.22 if left else -0.22
	if not planks:
		rot = 0.0
	_show(0, tex, Vector2(x, 0.0), Vector2.ONE * scale, not left and not planks, rot if planks else 0.0)
	var hit_w := width * (0.62 if planks else 0.7)
	var hit_h := height * (0.42 if planks else 0.55)
	if left:
		x = minf(x, gap_x - 14.0 - hit_w * 0.5)
	else:
		x = maxf(x, gap_x + gap_w + 14.0 + hit_w * 0.5)
	x = clampf(x, hit_w * 0.5 + 4.0, RR.VIEW_W - hit_w * 0.5 - 4.0)
	_sprites[0].position = Vector2(x, 0.0)
	_rest[0] = _sprites[0].position
	_cover(x - hit_w * 0.5, x + hit_w * 0.5, 0.0, hit_h * 0.5)
