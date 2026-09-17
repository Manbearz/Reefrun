extends SceneTree

func _initialize() -> void:
	root.add_child(Runner.new())


class Runner extends Node:
	func _ready() -> void:
		var game: Node = load("res://scenes/game/game.tscn").instantiate()
		add_child(game)
		var waited := 0.0
		while not bool(game.get("started")) and waited < 8.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		if not bool(game.get("started")):
			push_error("[flap-input] game never started")
			get_tree().quit(1)
			return
		game.set_physics_process(false)
		var player: Node = game.get("player")
		if player:
			player.set("alive", true)
			player.set("started", true)
			player.set("velocity", Vector2(0, 0))
			player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))
		var pos := Vector2(RR.VIEW_W * 0.5, RR.VIEW_H * 0.55)
		var vp := get_viewport()
		var mouse_ok := 0
		var touch_ok := 0
		for i in 50:
			if player:
				player.set("velocity", Vector2(0, 0))
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.pressed = true
			mouse.position = pos
			vp.push_input(mouse)
			if player and is_equal_approx(float(player.get("velocity").y), -RR.FLAP):
				mouse_ok += 1
			await get_tree().process_frame
		for i in 50:
			if player:
				player.set("velocity", Vector2(0, 0))
			var touch := InputEventScreenTouch.new()
			touch.index = 0
			touch.pressed = true
			touch.position = pos
			vp.push_input(touch)
			if player and is_equal_approx(float(player.get("velocity").y), -RR.FLAP):
				touch_ok += 1
			await get_tree().process_frame
		var recorded: PackedInt32Array = game.get("_recorded_flaps")
		print("[flap-input] mouse_flaps=%d touch_flaps=%d recorded=%d" % [mouse_ok, touch_ok, recorded.size()])
		var ok := mouse_ok == 50 and touch_ok == 50 and recorded.size() == 100
		get_tree().quit(0 if ok else 1)
