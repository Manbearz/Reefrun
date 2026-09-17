extends SceneTree

func _initialize() -> void:
	root.add_child(Runner.new())


class Runner extends Node:
	func _ready() -> void:
		var game: Node = load("res://scenes/game/game.tscn").instantiate()
		add_child(game)
		await get_tree().process_frame
		game.set("_lobby_t", RR.LOBBY_SECS)
		game.set("_in_lobby", false)
		game.call("_begin_run")
		var player: Node = game.get("player")
		var waited := 0.0
		while int(game.get("score")) < 2 and waited < 12.0:
			if player:
				player.set("alive", true)
				player.set("started", true)
				var gap: float = game.call("_upcoming_gap")
				player.set("position", Vector2(RR.PLAYER_X, gap))
				player.set("velocity", Vector2.ZERO)
			await get_tree().process_frame
			waited += get_process_delta_time()
		var worst: Dictionary = game.get("_spike_worst")
		print(
			"[pipe-spike-test] score=%s start=%.1f pipe1=%.1f score1=%.1f pipe2=%.1f score2=%.1f primed=%s pool=%s"
			% [
				str(game.get("score")),
				float(worst.get("start", 0.0)),
				float(worst.get("pipe1_approach", 0.0)),
				float(worst.get("score1", 0.0)),
				float(worst.get("pipe2_approach", 0.0)),
				float(worst.get("score2", 0.0)),
				str((game.get("pipes") as Array).size()),
				str((game.get("_pipe_pool") as Array).size()),
			]
		)
		get_tree().quit(0 if int(game.get("score")) >= 2 else 1)
