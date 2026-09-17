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
		for i in 50:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.pressed = true
			mouse.position = pos
			vp.push_input(mouse)
			await get_tree().process_frame
			if player:
				player.set("velocity", Vector2(0, 0))
				player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))
		for i in 50:
			var touch := InputEventScreenTouch.new()
			touch.index = 0
			touch.pressed = true
			touch.position = pos
			vp.push_input(touch)
			await get_tree().process_frame
			if player:
				player.set("velocity", Vector2(0, 0))
				player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))
		print(
			"[flap-input] started=%s mouse_press=%s mouse_flaps=%s mouse_rej=%s touch_press=%s touch_flaps=%s touch_rej=%s flap_calls=%s vel_overwrite=%s reasons=%s"
			% [
				str(game.get("started")),
				str(game.get("_mouse_pressed")),
				str(game.get("_mouse_flaps")),
				str(game.get("_mouse_rejected")),
				str(game.get("_screen_touch_pressed")),
				str(game.get("_touch_flaps")),
				str(game.get("_touches_rejected")),
				str(game.get("_player_flap_calls")),
				str(game.get("_vel_overwrites")),
				str(game.get("_reject_counts")),
			]
		)
		var mouse_n: int = int(game.get("_mouse_lat_n"))
		var touch_n: int = int(game.get("_touch_lat_n"))
		var mouse_avg := float(int(game.get("_mouse_lat_sum"))) / float(maxi(mouse_n, 1))
		var touch_avg := float(int(game.get("_touch_lat_sum"))) / float(maxi(touch_n, 1))
		print(
			"[flap-input] mouse_us avg=%.0f worst=%s touch_us avg=%.0f worst=%s"
			% [mouse_avg, str(game.get("_mouse_lat_worst")), touch_avg, str(game.get("_touch_lat_worst"))]
		)
		var ok := (
			int(game.get("_mouse_pressed")) == 50
			and int(game.get("_mouse_flaps")) == 50
			and int(game.get("_screen_touch_pressed")) == 50
			and int(game.get("_touch_flaps")) == 50
			and int(game.get("_player_flap_calls")) == 100
		)
		get_tree().quit(0 if ok else 1)
