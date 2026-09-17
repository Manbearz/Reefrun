class_name ReefFish
extends Node2D

signal died

const CTRL_PLAYER := 0
const CTRL_PLAYBACK := 1
const CTRL_AI := 2

var is_player := false
var control := CTRL_PLAYER
var skin := "fish_blue"
var display_name := "You"
var alive := true
var started := false
var velocity := Vector2.ZERO
var survive_pipes := 9999
var pipes_cleared := 0
var look_ahead := 0.0
var skill := 0.55
var flap_cd := 0.0 # AI anti-spam only. Local player input never checks this.
var bob_t := 0.0
var rest_y := 0.0
var x_jitter := 0.0
var start_origin := Vector2.ZERO
var rng := RandomNumberGenerator.new()
var ghost_run
var next_flap_index := 0

var _sprite: Sprite2D
var _hat: Sprite2D
var _hit_area: Area2D
var _flap_present_usec := 0


func setup(p_skin: String, p_player: bool, origin: Vector2, p_name: String) -> void:
	skin = p_skin
	is_player = p_player
	display_name = p_name
	position = origin
	start_origin = origin
	rest_y = origin.y
	x_jitter = origin.x - RR.PLAYER_X
	bob_t = 0.0
	control = CTRL_PLAYER if p_player else CTRL_AI
	if p_player:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	set_process(is_player)
	set_physics_process(false)
	# Ghosts keep interpolation. The local player's drawn sprite is presented in
	# _process so a flap is visible before the next 60 Hz physics step.
	physics_interpolation_mode = (
		Node.PHYSICS_INTERPOLATION_MODE_OFF if is_player else Node.PHYSICS_INTERPOLATION_MODE_ON
	)
	_sprite = Sprite2D.new()
	_sprite.texture = _tex(skin)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var s := RR.FISH_SCALE * (1.16 if is_player else 0.92)
	_sprite.scale = Vector2.ONE * s
	_sprite.z_index = 20 if is_player else 8
	add_child(_sprite)
	if is_player:
		_sprite.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_hat = Sprite2D.new()
	_hat.centered = true
	_hat.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_hat.z_index = 1
	_sprite.add_child(_hat)
	if is_player:
		apply_hat(GameSession.hat_index)
	else:
		apply_hat(-1)
	if not is_player:
		modulate = Color(1, 1, 1, RR.GHOST_ALPHA)
		return
	_hit_area = Area2D.new()
	_hit_area.monitoring = true
	_hit_area.monitorable = false
	_hit_area.collision_layer = 2
	_hit_area.collision_mask = 1
	var capsule := CapsuleShape2D.new()
	capsule.radius = RR.FISH_HIT * 1.12
	capsule.height = RR.FISH_BODY * 1.12
	var shape := CollisionShape2D.new()
	shape.shape = capsule
	shape.rotation = PI * 0.5
	_hit_area.add_child(shape)
	_hit_area.area_entered.connect(_on_hit)
	add_child(_hit_area)


func apply_hat(index: int) -> void:
	if _hat == null:
		return
	if index < 0 or index >= RR.HAT_COUNT:
		_hat.visible = false
		return
	_hat.texture = _tex(RR.hat_id(index))
	_hat.visible = _hat.texture != null
	_hat.centered = true
	_hat.position = RR.hat_anchor(skin)
	_hat.offset = RR.hat_brim_offset(_hat.texture)
	_hat.scale = Vector2.ONE * RR.hat_local_scale(_sprite.scale.x)


func reset_for_match() -> void:
	position = start_origin
	velocity = Vector2.ZERO
	if _sprite:
		_sprite.rotation = 0.0
		_sprite.position = Vector2.ZERO
		_sprite.offset = Vector2.ZERO
	_flap_present_usec = 0
	if is_player:
		apply_hat(GameSession.hat_index)


func simulate_vertical(delta: float) -> void:
	velocity.y = minf(velocity.y + RR.GRAVITY * delta, RR.TERMINAL)
	position.y += velocity.y * delta
	if is_player:
		_flap_present_usec = 0


func _process(_delta: float) -> void:
	if is_player:
		_present_sprite()


func _present_dt() -> float:
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	if _flap_present_usec > 0:
		var elapsed := float(Time.get_ticks_usec() - _flap_present_usec) * 0.000001
		var refresh := DisplayServer.screen_get_refresh_rate()
		if refresh < 30.0:
			refresh = 60.0
		return clampf(maxf(elapsed, 1.0 / refresh), 0.0, tick)
	return clampf(Engine.get_physics_interpolation_fraction() * tick, 0.0, tick)


func _present_sprite() -> void:
	if _sprite == null or not is_player:
		return
	if not started or not alive:
		_sprite.position = Vector2.ZERO
		return
	# Local offset only. Collision stays on this node's physics position.
	_sprite.position = Vector2(0.0, velocity.y * _present_dt())


func tick(delta: float) -> void:
	if not alive:
		simulate_vertical(delta)
		_sprite.rotation = lerp_angle(_sprite.rotation, PI * 0.45, 0.18)
		return
	if not started:
		bob_t += delta * 3.2
		position.y = rest_y + sin(bob_t) * 7.0
		_sprite.rotation = -0.22 + sin(bob_t) * 0.10
		return
	if control == CTRL_AI:
		_ghost_think()
		flap_cd = maxf(flap_cd - delta, 0.0)
		simulate_vertical(delta)
		return
	if control == CTRL_PLAYBACK:
		simulate_vertical(delta)
		_face_velocity()
		return
	simulate_vertical(delta)
	_face_velocity()
	position.x = RR.PLAYER_X
	if position.y < RR.PLAY_TOP or position.y > RR.VIEW_H:
		kill()
		return
	if _hit_area and not _hit_area.get_overlapping_areas().is_empty():
		kill()


func _face_velocity() -> void:
	_sprite.rotation = clampf(remap(velocity.y, -RR.FLAP, 420.0, -0.45, 1.15), -0.5, 1.2)


func flap(play_sound := false) -> void:
	if not alive:
		return
	started = true
	velocity.y = -RR.FLAP
	if is_player:
		flap_cd = 0.0
		_flap_present_usec = Time.get_ticks_usec()
		# Stop displaying the previous falling pose. Collision stays here;
		# only the sprite presentation is corrected.
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		reset_physics_interpolation()
		if _sprite:
			_sprite.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			_sprite.reset_physics_interpolation()
			_sprite.position = Vector2.ZERO
			_face_velocity()
			_present_sprite()
	else:
		flap_cd = 0.08
		if _sprite:
			_face_velocity()
	if play_sound:
		var sfx := get_node_or_null("/root/Sfx")
		if sfx:
			sfx.play("swim")


func _ghost_think() -> void:
	if flap_cd > 0.0:
		return
	var target := look_ahead
	if pipes_cleared >= survive_pipes:
		target += 90.0 * (1.0 if rng.randf() > 0.5 else -1.0)
	elif position.y < RR.PLAY_TOP + 36.0:
		return
	var bias := (0.5 - skill) * 28.0
	if position.y > target + 10.0 + bias:
		flap()
		flap_cd = lerpf(0.16, 0.08, skill) + rng.randf() * 0.05
	elif velocity.y > 360.0:
		flap()
		flap_cd = 0.12


func kill() -> void:
	if not alive:
		return
	alive = false
	if velocity.y < 80.0:
		velocity.y = 120.0
	died.emit()
	if is_player:
		var puff := Sprite2D.new()
		puff.texture = _tex("splash_b")
		puff.scale = Vector2.ONE * 0.45
		puff.z_index = 24
		add_child(puff)


func _on_hit(_area: Area2D) -> void:
	if is_player:
		kill()


func _tex(id: String) -> Texture2D:
	var sprites := get_node_or_null("/root/Sprites")
	if sprites == null:
		return null
	return sprites.tex(id)
