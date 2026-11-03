extends SceneTree

## Personal-best "NEW" mark on the Wiped Out score box.
## Restores user://reefrun.cfg even when a check fails.

func _initialize() -> void:
	root.add_child(Runner.new())


class Runner extends Node:
	const SAVE_PATH := "user://reefrun.cfg"

	func _ready() -> void:
		var snap := _snapshot()
		var code := 0
		var fail := await _checks()
		if fail != "":
			push_error("[new-best] " + fail)
			code = 1
		_restore(snap)
		var session := get_node("/root/GameSession")
		if int(session.best_score) != int(snap["best"]) or str(session.match_mode) != str(snap["mode"]) or bool(session.practice_daily) != bool(snap["practice"]):
			push_error("[new-best] save was not restored best=%s mode=%s practice=%s" % [session.best_score, session.match_mode, session.practice_daily])
			code = 1
		else:
			print("[new-best] restored personal best %s" % session.best_score)
		print("[new-best] %s" % ("ok" if code == 0 else "failed"))
		get_tree().quit(code)

	func _checks() -> String:
		var session := get_node("/root/GameSession")
		var game: Node = load("res://scenes/game/game.tscn").instantiate()
		add_child(game)
		await get_tree().process_frame
		await get_tree().process_frame
		var cases := [
			{"previous": 20, "score": 25, "show": true},
			{"previous": 25, "score": 25, "show": false},
			{"previous": 25, "score": 10, "show": false},
			{"previous": 25, "score": 30, "show": true},
		]
		for item in cases:
			session.practice_daily = false
			session.match_mode = ""
			session.best_score = int(item["previous"])
			game.set("score", int(item["score"]))
			game.call("_note_personal_best")
			var flagged: bool = game.get("_wipe_new_best")
			if flagged != bool(item["show"]):
				return "best %s score %s flag %s" % [item["previous"], item["score"], flagged]
			session.record_run(int(item["score"]), 50, 0)
			var expected := int(item["score"]) if bool(item["show"]) else int(item["previous"])
			if int(session.best_score) != expected:
				return "best stored %s after score %s, wanted %s" % [session.best_score, item["score"], expected]
			if bool(game.get("_wipe_new_best")) != bool(item["show"]):
				return "record_run cleared the NEW flag"
		var saved := ConfigFile.new()
		if saved.load(SAVE_PATH) != OK or int(saved.get_value("stats", "best_score", -1)) != 30:
			return "best_score was not written to reefrun.cfg"
		session.best_score = 1
		session._load()
		if int(session.best_score) != 30:
			return "reload lost best_score"
		session.best_score = 25
		session.practice_daily = true
		session.match_mode = ""
		game.set("score", 40)
		game.call("_note_personal_best")
		if bool(game.get("_wipe_new_best")):
			return "practice run showed NEW"
		session.record_run(40, 1, 0)
		if int(session.best_score) != 25:
			return "practice run changed best_score"
		session.practice_daily = false
		var lengths := [5, 25, 250, 9999]
		for value in lengths:
			var fit := await _measure(game, value, true)
			if fit != "":
				return fit
		var hidden := await _measure(game, 25, false)
		if hidden != "":
			return hidden
		game.set("score", 42)
		game.set("_wipe_new_best", true)
		game.set("finished", true)
		game.call("_show_over", 3, 2)
		await get_tree().process_frame
		if _count_named(game.get("overlay"), "ScoreNew") != 1:
			return "record overlay lost NEW"
		game.call("_open_share_overlay")
		await get_tree().process_frame
		if _count_named(game.get("_share_layer"), "ScoreNew") != 0:
			return "share card drew NEW"
		if game.get("_wipe_again") == null or game.get("_wipe_share") == null or game.get("_wipe_menu") == null:
			return "wipe buttons missing"
		game.call("_clear_overlay")
		game.set("started", false)
		game.set("finished", false)
		game.set("_wipe_new_best", true)
		game.call("_begin_run")
		if bool(game.get("_wipe_new_best")):
			return "starting another run kept NEW"
		game.set("finished", true)
		game.call("_show_over", 3, 2)
		await get_tree().process_frame
		if _count_named(game.get("overlay"), "ScoreNew") != 0:
			return "NEW still visible after a new run"
		return ""

	func _measure(game: Node, value: int, show: bool) -> String:
		game.set("score", value)
		game.set("_wipe_new_best", show)
		game.set("finished", true)
		game.call("_show_over", 4, 1)
		await get_tree().process_frame
		var overlay: Node = game.get("overlay")
		var marks := _count_named(overlay, "ScoreNew")
		if show and marks != 1:
			return "score %s expected one NEW, found %s" % [value, marks]
		if not show and marks != 0:
			return "score %s expected no NEW, found %s" % [value, marks]
		var box := _find(overlay, "ScoreDigits") as Control
		if box == null:
			return "score box missing"
		if not show:
			print("[new-best] score %s NEW hidden" % value)
			return ""
		var digit_left := float(box.size.x)
		var digit_right := 0.0
		var digit_h := 0.0
		var digit_count := 0
		var mark: Control = null
		for child in box.get_children():
			if str(child.name) == "ScoreNew":
				mark = child
				continue
			if child is TextureRect:
				digit_count += 1
				digit_left = minf(digit_left, child.position.x)
				digit_right = maxf(digit_right, child.position.x + child.size.x)
				digit_h = maxf(digit_h, child.size.y)
		if mark == null or digit_count != str(value).length():
			return "score %s digit layout missing" % value
		var gap := mark.position.x - digit_right
		var mark_right := mark.position.x + mark.size.x
		var ratio := mark.size.y / maxf(digit_h, 1.0)
		var center := float(digit_left + mark_right) * 0.5
		print("[new-best] digits=%s box=%.1f digit_h=%.1f mark_h=%.1f gap=%.1f right=%.1f" % [
			digit_count, box.size.x, digit_h, mark.size.y, gap, mark_right,
		])
		if gap < 1.0:
			return "score %s NEW overlaps digits (gap %.2f)" % [value, gap]
		if mark.position.x < 0.0 or mark_right > box.size.x + 0.5 or digit_left < -0.5:
			return "score %s NEW leaves the score box" % value
		if ratio < 0.40 or ratio > 0.52:
			return "score %s NEW height ratio %.2f" % [value, ratio]
		if absf(center - box.size.x * 0.5) > 1.5:
			return "score %s group is not centered" % value
		if mark.modulate != Palette.GOLD:
			return "score %s NEW is not gold" % value
		if mark.get_child_count() != 3:
			return "score %s NEW is not three letters" % value
		return ""

	func _count_named(node: Node, wanted: String) -> int:
		if node == null:
			return 0
		var count := 0
		if str(node.name) == wanted:
			count += 1
		for child in node.get_children():
			count += _count_named(child, wanted)
		return count

	func _find(node: Node, wanted: String) -> Node:
		if node == null:
			return null
		if str(node.name) == wanted:
			return node
		for child in node.get_children():
			var found := _find(child, wanted)
			if found:
				return found
		return null

	func _snapshot() -> Dictionary:
		var existed := FileAccess.file_exists(SAVE_PATH)
		var bytes := PackedByteArray()
		if existed:
			bytes = FileAccess.get_file_as_bytes(SAVE_PATH)
		var session := get_node("/root/GameSession")
		return {
			"existed": existed,
			"bytes": bytes,
			"best": int(session.best_score),
			"mode": str(session.match_mode),
			"practice": bool(session.practice_daily),
		}

	func _restore(snap: Dictionary) -> void:
		var session := get_node("/root/GameSession")
		if bool(snap["existed"]):
			var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
			if f:
				f.store_buffer(snap["bytes"])
				f.close()
			session._load()
		else:
			var abs_path := ProjectSettings.globalize_path(SAVE_PATH)
			if FileAccess.file_exists(SAVE_PATH):
				DirAccess.remove_absolute(abs_path)
			session.best_score = int(snap["best"])
		session.match_mode = str(snap["mode"])
		session.practice_daily = bool(snap["practice"])
