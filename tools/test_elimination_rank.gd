extends SceneTree

## Wiped Out rank follows elimination order. First out is 100, last is 1.

func _initialize() -> void:
	root.add_child(Runner.new())


class Runner extends Node:
	func _ready() -> void:
		var fail := _checks()
		if fail != "":
			push_error("[rank] " + fail)
		print("[rank] %s" % ("ok" if fail == "" else "failed"))
		get_tree().quit(0 if fail == "" else 1)

	func _checks() -> String:
		var game: Node = load("res://scenes/game/game.tscn").instantiate()
		game.set("debug_skip_ready", true)
		add_child(game)
		var cases := [
			{"prior": 0, "rank": 100, "left": 99},
			{"prior": 1, "rank": 99, "left": 98},
			{"prior": 2, "rank": 98, "left": 97},
			{"prior": 9, "rank": 91, "left": 90},
			{"prior": 50, "rank": 50, "left": 49},
			{"prior": 99, "rank": 1, "left": 0},
		]
		for item in cases:
			var got := _finish_after(game, int(item["prior"]))
			if got != "":
				return got
			if int(game.get("_final_rank")) != int(item["rank"]) or int(game.get("_final_remaining")) != int(item["left"]):
				return "after %s prior, rank %s remaining %s" % [item["prior"], game.get("_final_rank"), game.get("_final_remaining")]
			if int(game.get("_final_remaining")) + 1 != int(game.get("_final_rank")):
				return "still swimming disagrees with rank"
			print("[rank] prior=%s place=%s swimming=%s" % [item["prior"], game.get("_final_rank"), game.get("_final_remaining")])
		game.call("_reset_elimination_state")
		if not game.call("_eliminate_participant", "g:a") or not game.call("_eliminate_participant", "g:b"):
			return "same-frame eliminations were rejected"
		if int(game.get("_eliminated")["g:a"]) != 1 or int(game.get("_eliminated")["g:b"]) != 2:
			return "same-frame order was not stable"
		if not game.call("_freeze_player_rank") or int(game.get("_final_rank")) != 98:
			return "player was not third after two same-frame deaths"
		game.call("_reset_elimination_state")
		if not game.call("_eliminate_participant", "g:1"):
			return "first ghost was not counted"
		if game.call("_eliminate_participant", "g:1"):
			return "ghost was eliminated twice"
		if int(game.get("_elimination_count")) != 1 or int(game.get("swimming")) != 99:
			return "duplicate callback changed the field"
		if not game.call("_freeze_player_rank") or int(game.get("_final_rank")) != 99:
			return "duplicate ghost changed the player rank"
		var frozen_rank := int(game.get("_final_rank"))
		var frozen_left := int(game.get("_final_remaining"))
		if not game.call("_eliminate_participant", "g:after"):
			return "ghost after the player was ignored"
		if int(game.get("_final_rank")) != frozen_rank or int(game.get("_final_remaining")) != frozen_left:
			return "rank changed after the player was eliminated"
		if int(game.get("swimming")) != 97:
			return "live field did not record the later ghost"
		if game.call("_freeze_player_rank"):
			return "a second player callback was counted again"
		game.call("_reset_elimination_state")
		if int(game.get("_elimination_count")) != 0 or int(game.get("swimming")) != 100 or int(game.get("_final_rank")) != -1:
			return "new run kept the previous elimination order"
		var again := _finish_after(game, 0)
		if again != "" or int(game.get("_final_rank")) != 100:
			return "new run did not rank a first death as 100"
		for _i in 100:
			game.call("_eliminate_participant", "extra:%d" % _i)
		if int(game.get("swimming")) != 0:
			return "field did not stop at zero"
		if game.call("_eliminate_participant", "extra:overflow"):
			return "elimination count exceeded 100"
		if int(game.get("swimming")) < 0 or int(game.get("swimming")) > 100:
			return "swimming left 0..100"
		if game.call("_death_due", -1, 0) or game.call("_death_due", -1, 80):
			return "a survivor was treated as eliminated"
		if not game.call("_death_due", 0, 0):
			return "a tick-0 death was skipped"
		if game.call("_death_due", 10, 9) or not game.call("_death_due", 10, 10):
			return "death tick comparison is wrong"
		return ""

	func _finish_after(game: Node, prior: int) -> String:
		game.call("_reset_elimination_state")
		for i in prior:
			if not game.call("_eliminate_participant", "prior:%d" % i):
				return "could not eliminate prior %d" % i
		if not game.call("_freeze_player_rank"):
			return "player finish was rejected after %d" % prior
		return ""
