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
			push_error("[fall-recovery] game never started")
			get_tree().quit(1)
			return
		game.set_physics_process(false)
		var player: Node = game.get("player")
		if player == null:
			push_error("[fall-recovery] missing player")
			get_tree().quit(1)
			return
		player.set("alive", true)
		player.set("started", true)
		player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))

		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		var terminal_ok := 0
		var terminal_fail := 0
		var rising_ok := 0
		var rising_fail := 0
		var long_fall_ok := 0
		var long_fall_fail := 0
		var touch_ok := 0
		var touch_fail := 0
		var physics_ok := 0
		var physics_fail := 0
		var sample := {}

		for i in 100:
			player.set("velocity", Vector2(0.0, RR.TERMINAL))
			player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))
			var before := float(player.get("velocity").y)
			var reason: String = game.call("_try_player_flap")
			var after := float(player.get("velocity").y)
			if reason == "" and is_equal_approx(after, -RR.FLAP) and before >= RR.TERMINAL * 0.9:
				terminal_ok += 1
			else:
				terminal_fail += 1
				print("[fall-recovery] terminal fail before=%.1f after=%.1f reason=%s" % [before, after, reason])

		for i in 100:
			player.set("velocity", Vector2(0.0, -400.0))
			player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))
			var reason: String = game.call("_try_player_flap")
			if reason == "" and is_equal_approx(float(player.get("velocity").y), -RR.FLAP):
				rising_ok += 1
			else:
				rising_fail += 1

		for i in 100:
			player.set("velocity", Vector2.ZERO)
			player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))
			for _t in 60:
				player.call("simulate_vertical", dt)
			var before := float(player.get("velocity").y)
			var reason: String = game.call("_try_player_flap")
			var after := float(player.get("velocity").y)
			player.call("simulate_vertical", dt)
			var phys1 := float(player.get("velocity").y)
			player.call("simulate_vertical", dt)
			var phys2 := float(player.get("velocity").y)
			if (
				before >= RR.TERMINAL * 0.9
				and reason == ""
				and is_equal_approx(after, -RR.FLAP)
				and phys1 < 0.0
				and phys2 < 0.0
			):
				long_fall_ok += 1
				if sample.is_empty():
					sample = {
						"before": before,
						"after": after,
						"phys1": phys1,
						"phys2": phys2,
					}
			else:
				long_fall_fail += 1
				print(
					"[fall-recovery] long-fall fail before=%.1f after=%.1f phys1=%.1f phys2=%.1f reason=%s"
					% [before, after, phys1, phys2, reason]
				)

		var vp := get_viewport()
		var pos := Vector2(RR.VIEW_W * 0.5, RR.VIEW_H * 0.55)
		for i in 100:
			player.set("velocity", Vector2(0.0, RR.TERMINAL))
			player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))
			var touch := InputEventScreenTouch.new()
			touch.index = 0
			touch.pressed = true
			touch.position = pos
			vp.push_input(touch)
			if is_equal_approx(float(player.get("velocity").y), -RR.FLAP):
				touch_ok += 1
			else:
				touch_fail += 1

		game.set_physics_process(true)
		for i in 30:
			player.set("alive", true)
			player.set("started", true)
			player.set("velocity", Vector2(0.0, RR.TERMINAL))
			player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))
			var reason: String = game.call("_try_player_flap")
			var after := float(player.get("velocity").y)
			await get_tree().physics_frame
			await get_tree().physics_frame
			var rec: Dictionary = game.get("last_recovery")
			var follow := float(player.get("velocity").y)
			var phys1 := float(rec.get("phys1_vel", follow))
			if reason == "" and is_equal_approx(after, -RR.FLAP) and follow < 0.0 and phys1 < 0.0:
				physics_ok += 1
			else:
				physics_fail += 1
				print(
					"[fall-recovery] physics-follow fail after=%.1f follow=%.1f phys1=%.1f ui=%s"
					% [after, follow, phys1, str(rec.get("ui", "?"))]
				)

		print("[fall-recovery] FLAP=%.1f TERMINAL=%.1f" % [RR.FLAP, RR.TERMINAL])
		print("[fall-recovery] terminal %d/100 rising %d/100 long_fall %d/100 touch %d/100 physics_follow %d/30" % [
			terminal_ok, rising_ok, long_fall_ok, touch_ok, physics_ok
		])
		if not sample.is_empty():
			print(
				"[fall-recovery] sample before=%.1f after=%.1f phys1=%.1f phys2=%.1f"
				% [float(sample.before), float(sample.after), float(sample.phys1), float(sample.phys2)]
			)
		var ok := (
			terminal_ok == 100
			and rising_ok == 100
			and long_fall_ok == 100
			and touch_ok == 100
			and physics_ok == 30
			and terminal_fail == 0
			and rising_fail == 0
			and long_fall_fail == 0
			and touch_fail == 0
			and physics_fail == 0
		)
		get_tree().quit(0 if ok else 1)
