extends SceneTree

const Feedback := preload("res://scripts/button_feedback.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _check(await _test_mouse(), "mouse") and ok
	ok = _check(await _test_touch(), "touch") and ok
	ok = _check(await _test_drag_off(), "drag off") and ok
	ok = _check(await _test_disabled_and_existing(), "disabled") and ok
	ok = _check(await _test_release_over(), "release over") and ok
	ok = _check(await _test_rapid(), "rapid") and ok
	ok = _check(await _test_single_action(), "single action") and ok
	ok = _check(await _test_plate(), "plate") and ok
	print("[button-feedback] ok=%s" % ok)
	quit(0 if ok else 1)


func _test_mouse() -> bool:
	_feedback().using_touch = false
	var icon := TextureRect.new()
	icon.position = Vector2(48, 48)
	icon.size = Vector2(96, 48)
	var button := Button.new()
	button.flat = true
	button.position = Vector2(40, 40)
	button.size = Vector2(112, 64)
	var spot := button.position
	Feedback.use_visual(button, icon)
	root.add_child(icon)
	root.add_child(button)
	await process_frame
	var feedback := button.get_node_or_null("ButtonFeedback")
	if feedback == null or button.get_node_or_null("ButtonWash") != null:
		return false
	button.mouse_entered.emit()
	if not is_equal_approx(feedback.goal_scale.x, Feedback.HOVER_SCALE):
		push_error("[button-feedback] hover scale %s" % feedback.goal_scale)
		return false
	if button.position != spot or not is_equal_approx(button.scale.x, 1.0):
		return false
	await _pump(0.16)
	if icon.modulate.r < 1.05:
		push_error("[button-feedback] hover tint %s" % icon.modulate)
		return false
	if icon.scale.x < 1.02:
		push_error("[button-feedback] art did not grow %s" % icon.scale)
		return false
	button.button_down.emit()
	if not is_equal_approx(feedback.goal_scale.x, Feedback.PRESS_SCALE):
		push_error("[button-feedback] press scale %s" % feedback.goal_scale)
		return false
	await _pump(0.12)
	if icon.scale.x > 0.99:
		push_error("[button-feedback] press did not shrink %s" % icon.scale)
		return false
	if not is_equal_approx(button.scale.x, 1.0) or button.size != Vector2(112, 64):
		push_error("[button-feedback] hitbox moved %s %s" % [button.scale, button.size])
		return false
	button.button_up.emit()
	button.mouse_exited.emit()
	await _pump(0.16)
	if not is_equal_approx(feedback.goal_scale.x, 1.0):
		push_error("[button-feedback] release scale %s" % feedback.goal_scale)
		return false
	if icon.modulate.r > 1.02:
		push_error("[button-feedback] tint stuck %s" % icon.modulate)
		return false
	icon.queue_free()
	button.queue_free()
	return true


func _test_touch() -> bool:
	_feedback().using_touch = true
	var clicks := [0]
	var icon := TextureRect.new()
	icon.size = Vector2(80, 40)
	var button := Button.new()
	button.flat = true
	button.position = Vector2(10, 200)
	button.size = Vector2(80, 40)
	Feedback.use_visual(button, icon)
	button.pressed.connect(func() -> void:
		clicks[0] += 1
	)
	root.add_child(icon)
	root.add_child(button)
	await process_frame
	var feedback := button.get_node("ButtonFeedback")
	button.mouse_entered.emit()
	if feedback.goal_scale.x > 1.001:
		push_error("[button-feedback] touch left a hover")
		return false
	button.pressed.emit()
	if clicks[0] != 1:
		return false
	if not is_equal_approx(feedback.goal_scale.x, Feedback.PRESS_SCALE):
		push_error("[button-feedback] synthetic press %s" % feedback.goal_scale)
		return false
	var outside := InputEventScreenTouch.new()
	outside.pressed = false
	outside.position = Vector2(400, 400)
	outside.index = 0
	_feedback()._input(outside)
	await _pump(0.12)
	if feedback.goal_scale.x < 0.99:
		push_error("[button-feedback] touch release stuck %s" % feedback.goal_scale)
		return false
	if clicks[0] != 1:
		push_error("[button-feedback] extra click %d" % clicks[0])
		return false
	if not is_equal_approx(button.scale.x, 1.0):
		return false
	icon.queue_free()
	button.queue_free()
	_feedback().using_touch = false
	return true


func _test_drag_off() -> bool:
	_feedback().using_touch = true
	var icon := TextureRect.new()
	icon.size = Vector2(100, 50)
	var button := Button.new()
	button.flat = true
	button.position = Vector2(20, 320)
	button.size = Vector2(100, 50)
	Feedback.use_visual(button, icon)
	root.add_child(icon)
	root.add_child(button)
	await process_frame
	var feedback := button.get_node("ButtonFeedback")
	button.pressed.emit()
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(300, 500)
	drag.index = 0
	_feedback()._input(drag)
	if feedback.goal_scale.x < 0.99:
		push_error("[button-feedback] drag off stayed down %s" % feedback.goal_scale)
		return false
	if not is_equal_approx(button.scale.x, 1.0):
		return false
	icon.queue_free()
	button.queue_free()
	_feedback().using_touch = false
	return true


func _test_plate() -> bool:
	_feedback().using_touch = false
	var hit := Rect2(230, 1478, 480, 140)
	var plate := Rect2(297, 1487, 370, 126)
	var button := Button.new()
	button.flat = true
	button.position = Vector2.ZERO
	button.size = hit.size
	Feedback.use_plate(button, load("res://assets/sprites/daily_overlay.png"), hit, plate, 0.46, "wood")
	root.add_child(button)
	await process_frame
	var overlay := button.get_node_or_null("ButtonPlate") as TextureRect
	if overlay == null or button.get_node_or_null("ButtonWash") != null:
		push_error("[button-feedback] plate missing")
		return false
	if overlay.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	if overlay.size.x > button.size.x * 0.9 or overlay.size.y > button.size.y * 0.95:
		push_error("[button-feedback] plate still covers the hitbox %s" % overlay.size)
		return false
	var corner := Vector2(20, 4)
	if Rect2(overlay.position, overlay.size).has_point(corner):
		push_error("[button-feedback] plate covers scenery at %s" % corner)
		return false
	button.mouse_entered.emit()
	await _pump(0.2)
	var mask := overlay.texture.get_image()
	if mask.get_pixel(2, 2).a > 0.15:
		push_error("[button-feedback] mask corner is opaque")
		return false
	if mask.get_pixel(mask.get_width() >> 1, mask.get_height() >> 1).a < 0.8:
		push_error("[button-feedback] mask missed the button")
		return false
	if overlay.modulate.a < 0.4:
		push_error("[button-feedback] plate did not brighten %s" % overlay.modulate)
		return false
	if not is_equal_approx(button.scale.x, 1.0) or button.size != hit.size:
		return false
	button.mouse_exited.emit()
	await _pump(0.2)
	if overlay.modulate.a > 0.05:
		push_error("[button-feedback] plate stuck %s" % overlay.modulate)
		return false
	button.queue_free()
	return true


func _test_disabled_and_existing() -> bool:
	_feedback().using_touch = false
	var button := Button.new()
	button.flat = true
	button.disabled = true
	button.size = Vector2(40, 40)
	root.add_child(button)
	var feedback := button.get_node("ButtonFeedback")
	button.mouse_entered.emit()
	button.button_down.emit()
	if feedback.goal_scale.x > 1.001:
		push_error("[button-feedback] disabled moved %s" % feedback.goal_scale)
		return false
	var styled := Button.new()
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.2, 0.6, 0.9)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.05, 0.2, 0.4)
	styled.add_theme_stylebox_override("hover", hover)
	styled.add_theme_stylebox_override("pressed", pressed)
	root.add_child(styled)
	if styled.get_node_or_null("ButtonFeedback") != null:
		push_error("[button-feedback] replaced existing press art")
		return false
	var icon := TextureButton.new()
	icon.texture_normal = GradientTexture2D.new()
	icon.ignore_texture_size = true
	icon.size = Vector2(48, 48)
	root.add_child(icon)
	await process_frame
	var icon_feedback := icon.get_node_or_null("ButtonFeedback")
	var art := icon.get_node_or_null("ButtonArt")
	if icon_feedback == null or art == null:
		push_error("[button-feedback] texture art was not lifted")
		return false
	if icon.texture_normal != null:
		push_error("[button-feedback] texture still drawn by the button")
		return false
	icon.mouse_entered.emit()
	if not is_equal_approx(icon_feedback.goal_scale.x, Feedback.HOVER_SCALE):
		push_error("[button-feedback] texture hover %s" % icon_feedback.goal_scale)
		return false
	if not is_equal_approx(icon.scale.x, 1.0):
		push_error("[button-feedback] texture hitbox scaled")
		return false
	button.queue_free()
	styled.queue_free()
	icon.queue_free()
	return true


func _test_single_action() -> bool:
	var clicks := [0]
	var button := Button.new()
	button.text = "Continue"
	button.size = Vector2(140, 48)
	button.pressed.connect(func() -> void:
		clicks[0] += 1
	)
	root.add_child(button)
	await process_frame
	for _i in 6:
		button.button_down.emit()
		button.button_up.emit()
		button.pressed.emit()
	if clicks[0] != 6:
		push_error("[button-feedback] click count %d" % clicks[0])
		return false
	if button.get_node("ButtonFeedback") == null:
		return false
	button.queue_free()
	return true


func _test_release_over() -> bool:
	_feedback().using_touch = false
	var icon := TextureRect.new()
	icon.size = Vector2(80, 40)
	var button := Button.new()
	button.flat = true
	button.position = Vector2(8, 8)
	button.size = Vector2(80, 40)
	Feedback.use_visual(button, icon)
	root.add_child(icon)
	root.add_child(button)
	await process_frame
	var feedback := button.get_node("ButtonFeedback")
	button.mouse_entered.emit()
	button.button_down.emit()
	# Released while the engine still reports the pointer inside the button.
	button.mouse_entered.emit()
	button.button_up.emit()
	if not is_equal_approx(feedback.goal_scale.x, Feedback.HOVER_SCALE):
		push_error("[button-feedback] release did not restore hover %s" % feedback.goal_scale)
		return false
	button.mouse_exited.emit()
	await _pump(0.16)
	if not is_equal_approx(feedback.goal_scale.x, 1.0):
		push_error("[button-feedback] exit after release stuck %s" % feedback.goal_scale)
		return false
	icon.queue_free()
	button.queue_free()
	return true


func _test_rapid() -> bool:
	_feedback().using_touch = false
	var icon := TextureRect.new()
	icon.size = Vector2(40, 40)
	var button := Button.new()
	button.flat = true
	button.position = Vector2(400, 20)
	button.size = Vector2(40, 40)
	Feedback.use_visual(button, icon)
	root.add_child(icon)
	root.add_child(button)
	await process_frame
	var feedback := button.get_node("ButtonFeedback")
	for _i in 8:
		button.mouse_entered.emit()
		button.mouse_exited.emit()
	button.mouse_entered.emit()
	if not is_equal_approx(feedback.goal_scale.x, Feedback.HOVER_SCALE):
		push_error("[button-feedback] rapid ended off hover %s" % feedback.goal_scale)
		return false
	button.mouse_exited.emit()
	await _pump(0.16)
	if not is_equal_approx(feedback.goal_scale.x, 1.0):
		push_error("[button-feedback] rapid exit stuck %s" % feedback.goal_scale)
		return false
	icon.queue_free()
	button.queue_free()
	return true


func _feedback():
	return root.get_node("UiFeedback")


func _pump(seconds: float) -> void:
	var left := seconds
	var steps := 0
	while left > 0.0 and steps < 40:
		await process_frame
		left -= 0.016
		steps += 1


func _check(ok: bool, label: String) -> bool:
	if not ok:
		print("[button-feedback] FAIL %s" % label)
	return ok
