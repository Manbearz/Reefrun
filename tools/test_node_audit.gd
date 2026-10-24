extends SceneTree

# Diagnostic only. Walks the live scene tree during the real spawn and cleanup
# paths and records what grows. It does not change gameplay, submit scores,
# or contact production services.
# Godot --headless --path . --script res://tools/test_node_audit.gd

const DT := 0.1
const MARKS: Array[int] = [100, 500, 1000, 2000, 3000, 4000, 5000]
const DAILY_MARKS: Array[int] = [100, 500, 1000]

var _live_http := 0
var _failed := 0


func _initialize() -> void:
	ProjectSettings.set_setting("network/http_proxy/host", "127.0.0.1")
	ProjectSettings.set_setting("network/http_proxy/port", 9)
	var session := ConfigFile.new()
	session.set_value("session", "access_token", "offline-test-token")
	session.set_value("session", "refresh_token", "")
	session.set_value("session", "user_id", "11111111-1111-4111-8111-111111111111")
	session.set_value("session", "expires_at", int(Time.get_unix_time_from_system()) + 86400)
	session.save("user://supabase_session.cfg")
	call_deferred("_seal_network")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var version := Engine.get_version_info()
	print("[audit] godot=%s.%s.%s" % [version.major, version.minor, version.patch])
	_seal_network()
	await process_frame
	_seal_network()
	_probe_allocation_cost()
	var held_static := _static_mem()
	var held_objects := _objects()
	for _i in 30:
		await process_frame
	print("[audit] probe after_30_frames static_delta=%d object_delta=%d" % [
		_static_mem() - held_static, _objects() - held_objects,
	])
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null:
		for player in sfx._players:
			player.stop()
		for _i in 10:
			await process_frame
		print("[audit] probe after_stop static_delta=%d object_delta=%d" % [
			_static_mem() - held_static, _objects() - held_objects,
		])
	_probe_without_revive()
	var session := root.get_node("GameSession")
	var saved_mode: String = session.match_mode
	var saved_seed: int = session.course_seed
	var saved_practice: bool = session.practice_daily
	var saved_coins: int = int(session.coins)
	var saved_games: int = int(session.games_played)
	print("[audit] baseline %s" % _monitors())
	var unlimited: Dictionary = await _simulate("unlimited", 1, MARKS, 5000, true)
	_check("unlimited_reached", int(unlimited["score"]) >= 5000)
	await _cleanup_cycles(unlimited["start_nodes"])
	var daily: Dictionary = await _simulate("daily", 1, DAILY_MARKS, 1000, false)
	_check("daily_reached", int(daily["score"]) >= 1000)
	_compare_modes(unlimited, daily)
	_time_generator()
	session.match_mode = saved_mode
	session.course_seed = saved_seed
	session.practice_daily = saved_practice
	_check("wallet_untouched", int(session.coins) == saved_coins and int(session.games_played) == saved_games)
	_check("network_blocked", _live_http == 0, "live_http=%d" % _live_http)
	print("[audit] failed=%d" % _failed)
	quit(0 if _failed == 0 else 1)


func _simulate(mode: String, seed: int, marks: Array[int], target: int, keep_final: bool) -> Dictionary:
	var game = _boot(mode, seed)
	var events = game._events
	var seen := {}
	var steps := 0
	var cap := 280000 if target >= 5000 else 120000
	var idle := 0.0
	var last_score := 0
	var early_us := 0
	var early_n := 0
	var late_us := 0
	var late_n := 0
	var gen_us := 0
	var gen_n := 0
	var steady_us := 0
	var steady_n := 0
	var worst_us := 0
	var worst_score := 0
	var walk_us := 0
	var snapshots: Array[Dictionary] = []
	print("[audit] %s start %s" % [mode, _monitors()])
	var opened := _snapshot(game, mode, 0, 0, 0)
	snapshots.append(opened)
	_print_snapshot(opened)
	while steps < cap and int(game.score) < target:
		steps += 1
		var layout_before: int = game.layout.size()
		var started := Time.get_ticks_usec()
		game.player.alive = true
		var diving: bool = events != null and events.blocks_swim()
		if int(game._harpoon_beat) >= 2 and not diving:
			game.player.position.y = RR.harpoon_lane_center(int(game._safe_lane))
		_clock_harpoons(game)
		if events != null:
			events.set_corridor_clear(game._corridor_clear())
			events.tick(DT)
			if game._harpoon_live():
				game._tick_harpoons(DT)
			game._sync_events()
			diving = events.blocks_swim()
		if not diving:
			game.scroll += RR.PIPE_SPEED * DT
			game.player.position.y = game._upcoming_gap()
		if game._can_spawn_pipes():
			game._spawn_pipes()
		game._cull_pipes()
		if events == null and int(game._harpoon_beat) != 0:
			game._tick_harpoons(DT)
			game._recover_daily_harpoon(DT)
		if diving:
			game._update_dive_actor(DT)
		elif not diving:
			game._collect_coins()
			if game._scoring_open():
				game._score_pipes()
		var elapsed := Time.get_ticks_usec() - started
		if game.layout.size() != layout_before:
			gen_us += elapsed
			gen_n += 1
		elif int(game.score) >= 80:
			steady_us += elapsed
			steady_n += 1
		if elapsed > worst_us:
			worst_us = elapsed
			worst_score = int(game.score)
		if int(game.score) >= 80 and int(game.score) <= 120:
			early_us += elapsed
			early_n += 1
		if target >= 5000 and int(game.score) >= 4800:
			late_us += elapsed
			late_n += 1
		elif target < 5000 and int(game.score) >= 900:
			late_us += elapsed
			late_n += 1
		var score := int(game.score)
		var busy: bool = diving or int(game._harpoon_beat) != 0 or (events != null and not events.pipes_allowed())
		if busy or score != last_score:
			idle = 0.0
			last_score = score
		else:
			idle += DT
		if idle > 30.0:
			push_error("[audit] %s stalled at score %d" % [mode, score])
			break
		if seen.has(score):
			continue
		if score in marks:
			seen[score] = true
			var walked := Time.get_ticks_usec()
			var snap := _snapshot(game, mode, score, steps, elapsed)
			walk_us += Time.get_ticks_usec() - walked
			snapshots.append(snap)
			_print_snapshot(snap)
	var result := {
		"mode": mode,
		"score": int(game.score),
		"steps": steps,
		"snapshots": snapshots,
		"start_nodes": int(opened["game_nodes"]),
		"early_us": early_us,
		"early_n": early_n,
		"late_us": late_us,
		"late_n": late_n,
		"gen_us": gen_us,
		"gen_n": gen_n,
		"steady_us": steady_us,
		"steady_n": steady_n,
		"worst_us": worst_us,
		"worst_score": worst_score,
		"walk_us": walk_us,
	}
	_print_timing(result)
	if keep_final:
		_measure_course_data(game)
		result["game"] = game
	else:
		game.free()
		await process_frame
		await process_frame
	return result


func _snapshot(game: Node, mode: String, score: int, steps: int, step_us: int) -> Dictionary:
	var bucket := {
		"mode": mode,
		"score": score,
		"steps": steps,
		"step_us": step_us,
		"static": _static_mem(),
		"objects": _objects(),
		"resources": _resources(),
		"monitor_nodes": _nodes(),
		"orphans": _orphans(),
		"tree_nodes": 0,
		"game_nodes": 0,
		"autoload_nodes": 0,
		"hidden": 0,
		"visible": 0,
		"by_class": {},
		"by_kind": {},
		"by_parent": {},
		"by_system": {},
		"by_edge": {},
		"by_owner": {},
		"roots": {},
		"layout": game.layout.size(),
		"lanes": game._harpoon_lanes.size(),
		"fired": 0 if game._events == null else game._events.fired_log.size(),
		"coins": game._coins.size(),
		"coin_pool": game._coin_pool.size(),
		"pipes": game.pipes.size(),
		"pipe_pool": game._pipe_pool.size(),
		"harpoons": game._harpoons.size(),
	}
	_walk(root, game, bucket)
	var class_sum := 0
	for key in bucket["by_class"]:
		class_sum += int(bucket["by_class"][key])
	bucket["class_sum"] = class_sum
	bucket["reconciled"] = class_sum == int(bucket["tree_nodes"])
	bucket["monitor_gap"] = int(bucket["monitor_nodes"]) - int(bucket["tree_nodes"])
	return bucket


func _walk(node: Node, game: Node, bucket: Dictionary) -> void:
	bucket["tree_nodes"] = int(bucket["tree_nodes"]) + 1
	var under_game := node == game or _under(node, game)
	if under_game:
		bucket["game_nodes"] = int(bucket["game_nodes"]) + 1
	elif node.get_parent() == root or _under_autoload(node, game):
		bucket["autoload_nodes"] = int(bucket["autoload_nodes"]) + 1
	var cls := node.get_class()
	_bump(bucket["by_class"], cls)
	var kind := _kind(node)
	_bump(bucket["by_kind"], kind)
	var parent := node.get_parent()
	var parent_kind := "none" if parent == null else _kind(parent)
	_bump(bucket["by_parent"], "%s > %s" % [parent_kind, kind])
	_bump(bucket["by_edge"], "%s > %s" % [parent_kind, _pattern(str(node.name))])
	_bump(bucket["by_owner"], _owner_key(node))
	var system := _system(node, game)
	_bump(bucket["by_system"], system)
	if node is CanvasItem and not (node as CanvasItem).visible:
		bucket["hidden"] = int(bucket["hidden"]) + 1
	else:
		bucket["visible"] = int(bucket["visible"]) + 1
	if node.get_parent() == root:
		bucket["roots"][str(node.name)] = _descendants(node)
	for child in node.get_children():
		_walk(child, game, bucket)


func _print_snapshot(snap: Dictionary) -> void:
	print("[audit] mark mode=%s score=%d steps=%d static=%d objects=%d resources=%d monitor_nodes=%d tree=%d game=%d autoload=%d hidden=%d visible=%d orphans=%d monitor_gap=%d class_sum=%d reconciled=%s layout=%d lanes=%d fired=%d coins=%d/%d pipes=%d/%d harpoons=%d" % [
		snap["mode"], snap["score"], snap["steps"], snap["static"], snap["objects"], snap["resources"],
		snap["monitor_nodes"], snap["tree_nodes"], snap["game_nodes"], snap["autoload_nodes"],
		snap["hidden"], snap["visible"], snap["orphans"], snap["monitor_gap"], snap["class_sum"],
		snap["reconciled"], snap["layout"], snap["lanes"], snap["fired"], snap["coins"], snap["coin_pool"],
		snap["pipes"], snap["pipe_pool"], snap["harpoons"],
	])
	print("[audit] roots %s" % _fmt_map(snap["roots"]))
	print("[audit] class %s" % _fmt_map(snap["by_class"]))
	print("[audit] system %s" % _fmt_map(snap["by_system"]))
	print("[audit] kind %s" % _fmt_map(snap["by_kind"]))
	print("[audit] parent %s" % _fmt_map(snap["by_parent"]))
	print("[audit] owner %s" % _fmt_map(snap["by_owner"]))


func _print_timing(result: Dictionary) -> void:
	print("[audit] timing mode=%s steps=%d early_avg_us=%d early_n=%d late_avg_us=%d late_n=%d extend_avg_us=%d extend_n=%d steady_avg_us=%d steady_n=%d worst_us=%d worst_score=%d walk_us=%d" % [
		result["mode"], result["steps"],
		_avg(int(result["early_us"]), int(result["early_n"])), int(result["early_n"]),
		_avg(int(result["late_us"]), int(result["late_n"])), int(result["late_n"]),
		_avg(int(result["gen_us"]), int(result["gen_n"])), int(result["gen_n"]),
		_avg(int(result["steady_us"]), int(result["steady_n"])), int(result["steady_n"]),
		result["worst_us"], result["worst_score"], result["walk_us"],
	])


func _compare_modes(unlimited: Dictionary, daily: Dictionary) -> void:
	var u := _snap_at(unlimited["snapshots"], 100)
	var u5 := _snap_at(unlimited["snapshots"], 5000)
	var d := _snap_at(daily["snapshots"], 100)
	var d1 := _snap_at(daily["snapshots"], 1000)
	if u.is_empty() or u5.is_empty():
		_check("unlimited_span", false, "missing 100 or 5000 snapshot")
		return
	print("[audit] delta unlimited 100->5000")
	var node_delta := int(u5["game_nodes"]) - int(u["game_nodes"])
	var accounted := _print_delta("kind", u["by_kind"], u5["by_kind"])
	var owner_accounted := _print_delta("owner", u["by_owner"], u5["by_owner"])
	var edge_accounted := _print_delta("edge", u["by_edge"], u5["by_edge"])
	_print_delta("system", u["by_system"], u5["by_system"])
	_print_delta("class", u["by_class"], u5["by_class"])
	print("[audit] reconcile game_node_delta=%d kind_delta_sum=%d owner_delta_sum=%d edge_delta_sum=%d monitor_delta=%d tree_delta=%d" % [
		node_delta, accounted, owner_accounted, edge_accounted,
		int(u5["monitor_nodes"]) - int(u["monitor_nodes"]),
		int(u5["tree_nodes"]) - int(u["tree_nodes"]),
	])
	_check("kind_accounts_for_game_nodes", accounted == node_delta, "kind=%d game=%d" % [accounted, node_delta])
	if not d.is_empty() and not d1.is_empty():
		print("[audit] delta daily 100->1000")
		var daily_nodes := int(d1["game_nodes"]) - int(d["game_nodes"])
		var daily_kind := _print_delta("kind", d["by_kind"], d1["by_kind"])
		print("[audit] reconcile daily game_node_delta=%d kind_delta_sum=%d" % [daily_nodes, daily_kind])
		_check("daily_kind_accounts", daily_kind == daily_nodes, "kind=%d game=%d" % [daily_kind, daily_nodes])


func _print_delta(label: String, before: Dictionary, after: Dictionary) -> int:
	var keys := {}
	for key in before:
		keys[key] = true
	for key in after:
		keys[key] = true
	var rows: Array[Dictionary] = []
	var sum := 0
	for key in keys:
		var a := int(before.get(key, 0))
		var b := int(after.get(key, 0))
		var delta := b - a
		sum += delta
		if delta != 0:
			rows.append({"key": str(key), "a": a, "b": b, "d": delta})
	rows.sort_custom(func(x, y): return int(x["d"]) > int(y["d"]))
	for row in rows:
		print("[audit] %s %s before=%d after=%d delta=%d" % [label, row["key"], row["a"], row["b"], row["d"]])
	return sum


func _measure_course_data(game) -> void:
	var layout: Array = game.layout
	var lanes: PackedInt32Array = game._harpoon_lanes
	var fired: PackedStringArray = PackedStringArray()
	if game._events != null:
		fired = game._events.fired_log
	var style_chars := 0
	for spec in layout:
		style_chars += str(spec.get("style", "")).length()
	var fired_chars := 0
	for entry in fired:
		fired_chars += entry.length()
	var static_before := _static_mem()
	var objects_before := _objects()
	var copy: Array = layout.duplicate(true)
	var static_after := _static_mem()
	var objects_after := _objects()
	copy.clear()
	copy = []
	var lane_copy := lanes.duplicate()
	var fired_copy := fired.duplicate()
	print("[audit] course_data specs=%d style_chars=%d lanes=%d lane_bytes=%d fired=%d fired_chars=%d duplicate_static_delta=%d duplicate_object_delta=%d static_after_release=%d" % [
		layout.size(), style_chars, lanes.size(), lanes.size() * 4, fired.size(), fired_chars,
		static_after - static_before, objects_after - objects_before, _static_mem(),
	])
	lane_copy.resize(0)
	fired_copy.resize(0)
	_release_splash(game)
	print("[audit] course_refs last_x=%.1f spawn_index=%d history_before_spawn=%d" % [
		float(layout[layout.size() - 1]["x"]) if not layout.is_empty() else -1.0,
		int(game.spawn_index),
		maxi(0, int(game.spawn_index) - 1),
	])


func _probe_without_revive() -> void:
	var game = _boot("unlimited", 1)
	var events = game._events
	var steps := 0
	while steps < 2500 and int(game.score) < 80:
		steps += 1
		var diving: bool = events != null and events.blocks_swim()
		if int(game._harpoon_beat) >= 2 and not diving:
			game.player.position.y = RR.harpoon_lane_center(int(game._safe_lane))
		_clock_harpoons(game)
		if events != null:
			events.set_corridor_clear(game._corridor_clear())
			events.tick(DT)
			if game._harpoon_live():
				game._tick_harpoons(DT)
			game._sync_events()
			diving = events.blocks_swim()
		if not diving:
			game.scroll += RR.PIPE_SPEED * DT
			game.player.position.y = game._upcoming_gap()
		if game._can_spawn_pipes():
			game._spawn_pipes()
		game._cull_pipes()
		if events == null and int(game._harpoon_beat) != 0:
			game._tick_harpoons(DT)
			game._recover_daily_harpoon(DT)
		if diving:
			game._update_dive_actor(DT)
		else:
			game._collect_coins()
			if game._scoring_open():
				game._score_pipes()
		if not game.player.alive:
			break
	var census := _fish_census(game.player)
	print("[audit] no_revive score=%d steps=%d alive=%s fish_children=%d splash=%d other=%d nodes=%d" % [
		int(game.score), steps, game.player.alive, census["children"], census["splash"], census["other"], _nodes(),
	])
	game.free()


func _fish_census(fish: Node) -> Dictionary:
	var splash := 0
	var other := 0
	var sample := ""
	for child in fish.get_children():
		if child is Sprite2D and int(child.z_index) == 24:
			splash += 1
			if sample == "":
				var tex: Texture2D = (child as Sprite2D).texture
				sample = "<null>" if tex == null else "%s %dx%d" % [tex.resource_path, tex.get_width(), tex.get_height()]
		else:
			other += 1
	return {"children": fish.get_child_count(), "splash": splash, "other": other, "sample": sample}


func _release_splash(game) -> void:
	if game.player == null:
		return
	var census := _fish_census(game.player)
	var before_static := _static_mem()
	var before_objects := _objects()
	var before_nodes := _nodes()
	var removed := 0
	for child in game.player.get_children():
		if child is Sprite2D and int(child.z_index) == 24:
			game.player.remove_child(child)
			child.free()
			removed += 1
	print("[audit] splash children=%d splash=%d other=%d sample=%s removed=%d static_delta=%d object_delta=%d node_delta=%d static_after=%d" % [
		census["children"], census["splash"], census["other"], census["sample"], removed,
		_static_mem() - before_static, _objects() - before_objects, _nodes() - before_nodes, _static_mem(),
	])
	print("[audit] splash_cost removed=%d static_before=%d objects_before=%d nodes_before=%d" % [
		removed, before_static, before_objects, before_nodes,
	])
	_attribute_game(game)


func _mark_drop(label: String, static_before: int, objects_before: int) -> void:
	print("[audit] drop %s static=%d static_delta=%d objects=%d object_delta=%d nodes=%d" % [
		label, _static_mem(), _static_mem() - static_before, _objects(), _objects() - objects_before, _nodes(),
	])


func _attribute_game(game) -> void:
	var static_before := _static_mem()
	var objects_before := _objects()
	game.layout.clear()
	_mark_drop("clear_layout", static_before, objects_before)
	static_before = _static_mem()
	objects_before = _objects()
	game._harpoon_lanes = PackedInt32Array()
	if game._events != null:
		game._events.fired_log = PackedStringArray()
		game._events._consumed.clear()
		game._events._queue = PackedStringArray()
	_mark_drop("clear_lanes_and_event_log", static_before, objects_before)
	static_before = _static_mem()
	objects_before = _objects()
	if game._dive_field != null:
		game._dive_field.free()
		game._dive_field = null
	if game._dive_overlay != null:
		game._dive_overlay.free()
		game._dive_overlay = null
	_mark_drop("free_dive", static_before, objects_before)
	static_before = _static_mem()
	objects_before = _objects()
	for spear in game._harpoons:
		if is_instance_valid(spear):
			spear.free()
	game._harpoons.clear()
	_mark_drop("free_harpoons", static_before, objects_before)
	static_before = _static_mem()
	objects_before = _objects()
	for pair in game.pipes:
		if pair.visual != null and is_instance_valid(pair.visual):
			pair.visual.free()
		if is_instance_valid(pair):
			pair.free()
	for pair in game._pipe_pool:
		if pair.visual != null and is_instance_valid(pair.visual):
			pair.visual.free()
		if is_instance_valid(pair):
			pair.free()
	game.pipes.clear()
	game._pipe_pool.clear()
	_mark_drop("free_pipes", static_before, objects_before)
	static_before = _static_mem()
	objects_before = _objects()
	if game.player != null and is_instance_valid(game.player):
		game.player.free()
		game.player = null
	_mark_drop("free_player", static_before, objects_before)


func _cleanup_cycles(first_start_nodes: int) -> void:
	var game = null
	for child in root.get_children():
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("game.gd"):
			game = child
			break
	if game == null:
		_check("cleanup_found_game", false)
		return
	print("[audit] cleanup before_free %s" % _monitors())
	var layout_ref: Array = game.layout
	var layout_size := layout_ref.size()
	game.queue_free()
	game = null
	for _i in 4:
		await process_frame
	print("[audit] cleanup after_free %s layout_script_ref=%d" % [_monitors(), layout_size])
	print("[audit] cleanup roots %s" % _root_report())
	var menu_scene: PackedScene = load("res://scenes/menu/main_menu.tscn")
	for cycle in 3:
		var menu = menu_scene.instantiate()
		root.add_child(menu)
		menu.set_process(false)
		menu.set_process_input(false)
		await process_frame
		print("[audit] cleanup menu cycle=%d %s menu_nodes=%d" % [cycle + 1, _monitors(), _descendants(menu)])
		menu.free()
		for _i in 2:
			await process_frame
		var fresh = _boot("unlimited", 1)
		var snap := _snapshot(fresh, "unlimited", 0, 0, 0)
		print("[audit] cleanup new_run cycle=%d game_nodes=%d first_start=%d monitor=%d orphans=%d layout=%d" % [
			cycle + 1, snap["game_nodes"], first_start_nodes, snap["monitor_nodes"], snap["orphans"], snap["layout"],
		])
		_check("clean_restart_%d" % (cycle + 1), int(snap["game_nodes"]) <= int(first_start_nodes) + 4, "game=%d start=%d" % [int(snap["game_nodes"]), int(first_start_nodes)])
		fresh.free()
		for _i in 2:
			await process_frame
		print("[audit] cleanup after_cycle=%d %s" % [cycle + 1, _monitors()])


func _probe_allocation_cost() -> void:
	var holder := Node.new()
	holder.name = "AuditProbe"
	root.add_child(holder)
	var before := _static_mem()
	var objects_before := _objects()
	var nodes_before := _nodes()
	for _i in 200:
		holder.add_child(Node2D.new())
	var node_static := _static_mem() - before
	var node_objects := _objects() - objects_before
	var node_nodes := _nodes() - nodes_before
	holder.free()
	var specs: Array = []
	var spec_before := _static_mem()
	var spec_objects := _objects()
	for _i in 1000:
		specs.append({"x": 1.0, "gap_y": 2.0, "gap_h": 3.0, "style": "pipe_kelp"})
	var spec_static := _static_mem() - spec_before
	var spec_object_delta := _objects() - spec_objects
	specs.clear()
	var lanes := PackedInt32Array()
	lanes.resize(1506)
	var lane_before := _static_mem()
	var lane_copy := lanes.duplicate()
	var lane_static := _static_mem() - lane_before
	lane_copy.resize(0)
	print("[audit] probe empty_node2d n=200 static_delta=%d per_node=%d object_delta=%d node_delta=%d" % [
		node_static, node_static / 200, node_objects, node_nodes,
	])
	print("[audit] probe spec_dict n=1000 static_delta=%d per_spec=%d object_delta=%d lane_copy_1506_static=%d" % [
		spec_static, spec_static / 1000, spec_object_delta, lane_static,
	])
	var sprites := root.get_node_or_null("Sprites")
	var splash_tex: Texture2D = null
	if sprites != null and sprites.has_method("tex"):
		splash_tex = sprites.tex("splash_b")
	var splash_holder := Node2D.new()
	root.add_child(splash_holder)
	var splash_before := _static_mem()
	var splash_objects := _objects()
	var splash_nodes := _nodes()
	for _i in 200:
		var spr := Sprite2D.new()
		spr.texture = splash_tex
		spr.z_index = 24
		spr.scale = Vector2.ONE * 0.45
		splash_holder.add_child(spr)
	print("[audit] probe splash_sprite n=200 static_delta=%d per_sprite=%d object_delta=%d node_delta=%d" % [
		_static_mem() - splash_before, (_static_mem() - splash_before) / 200, _objects() - splash_objects, _nodes() - splash_nodes,
	])
	splash_holder.free()
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null and sfx.has_method("play"):
		var play_objects := _objects()
		var play_static := _static_mem()
		for _i in 400:
			sfx.play("checkpoint", -80.0)
		print("[audit] probe checkpoint_play n=400 static_delta=%d object_delta=%d" % [
			_static_mem() - play_static, _objects() - play_objects,
		])


func _time_generator() -> void:
	var course := load("res://scripts/course_builder.gd")
	var started := Time.get_ticks_usec()
	var total_specs := 0
	for i in 200:
		var built: Dictionary = course.continuation(1, i * 40)
		total_specs += (built["layout"] as Array).size()
	var elapsed := Time.get_ticks_usec() - started
	print("[audit] generator chunks=200 specs=%d total_us=%d avg_us=%d" % [total_specs, elapsed, elapsed / 200])


func _boot(mode: String, seed: int):
	var session := root.get_node("GameSession")
	session.match_mode = mode
	session.course_seed = seed
	session.practice_daily = mode != "unlimited"
	var game = load("res://scenes/game/game.tscn").instantiate()
	game.debug_skip_ready = true
	game.set_process(false)
	game.set_physics_process(false)
	root.add_child(game)
	game.course = Node2D.new()
	game.course.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	game.add_child(game.course)
	game.course_draw = Node2D.new()
	game.course_draw.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	game.add_child(game.course_draw)
	game.school = Node2D.new()
	game.add_child(game.school)
	game._build_layout()
	game._spawn_player()
	session.practice_daily = true
	game._setup_harpoons()
	game._prewarm_pipes()
	game.started = true
	game.finished = false
	game.paused = false
	game._in_lobby = false
	game.player.alive = true
	game.player.started = true
	var died := Callable(game, "_on_player_died")
	if game.player.died.is_connected(died):
		game.player.died.disconnect(died)
	return game


func _clock_harpoons(game) -> void:
	if int(game._harpoon_beat) < 2:
		return
	for spear in game._harpoons:
		spear.tick(DT)
	if int(game._harpoon_beat) == 2:
		game._warn_t -= DT


func _under(node: Node, game: Node) -> bool:
	var current := node.get_parent()
	while current != null:
		if current == game:
			return true
		current = current.get_parent()
	return false


func _under_autoload(node: Node, game: Node) -> bool:
	var current := node
	while current != null and current != root:
		if current.get_parent() == root and current != game:
			return true
		current = current.get_parent()
	return false


func _system(node: Node, game: Node) -> String:
	var current := node
	while current != null and current != root:
		var path := _script_path(current)
		if path.ends_with("pipe_pair.gd"):
			return "pipe"
		if path.ends_with("harpoon.gd"):
			return "harpoon"
		if path.ends_with("dive_field.gd") or path.ends_with("dive_obstacle.gd") or path.ends_with("dive_overlay.gd"):
			return "deep_dive"
		if path.ends_with("fish.gd"):
			return "fish"
		if path.ends_with("world.gd"):
			return "world"
		if path.ends_with("hud.gd"):
			return "hud"
		if current == game:
			if node == game:
				return "game_root"
			return "game_other"
		if current.get_parent() == root and current != game:
			return "autoload:" + str(current.name)
		current = current.get_parent()
	return "outside"


func _owner_key(node: Node) -> String:
	var current := node.get_parent()
	while current != null:
		var path := _script_path(current)
		if path != "":
			return "%s / %s" % [path.get_file(), _pattern(str(node.name))]
		current = current.get_parent()
	return "none / %s" % _pattern(str(node.name))


func _kind(node: Node) -> String:
	var path := _script_path(node)
	if path != "":
		return path.get_file() + ":" + node.get_class()
	return node.get_class()


func _script_path(node: Node) -> String:
	var script = node.get_script()
	if script == null:
		return ""
	return str(script.resource_path)


func _pattern(node_name: String) -> String:
	if node_name.begins_with("@"):
		var parts := node_name.split("@")
		if parts.size() >= 2 and parts[1] != "":
			return "@" + parts[1]
	return node_name


func _descendants(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _descendants(child)
	return count


func _root_report() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for child in root.get_children():
		parts.append("%s=%d" % [str(child.name), _descendants(child)])
	return " ".join(parts)


func _snap_at(snapshots: Array, score: int) -> Dictionary:
	for snap in snapshots:
		if int(snap["score"]) == score:
			return snap
	return {}


func _bump(bucket: Dictionary, key: String) -> void:
	bucket[key] = int(bucket.get(key, 0)) + 1


func _fmt_map(values: Dictionary) -> String:
	var rows: Array[Dictionary] = []
	for key in values:
		rows.append({"key": str(key), "n": int(values[key])})
	rows.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
	var parts: PackedStringArray = PackedStringArray()
	for row in rows:
		parts.append("%s=%d" % [row["key"], row["n"]])
	return " ".join(parts)


func _avg(total: int, count: int) -> int:
	if count <= 0:
		return 0
	return total / count


func _monitors() -> String:
	return "static=%d nodes=%d objects=%d resources=%d orphans=%d" % [
		_static_mem(), _nodes(), _objects(), _resources(), _orphans(),
	]


func _nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _objects() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func _resources() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))


func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _static_mem() -> int:
	return int(Performance.get_monitor(Performance.MEMORY_STATIC))


func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[audit] pass %s" % name)
		return
	_failed += 1
	print("[audit] FAIL %s %s" % [name, detail])


func _seal_network() -> void:
	var backend := root.get_node_or_null("Backend")
	if backend == null or not ("_client" in backend):
		return
	backend._client = DeadNet.new()
	var pending: Array[Node] = []
	_collect_http(root, pending)
	for http in pending:
		http.cancel_request()
		http.queue_free()


func _collect_http(node: Node, found: Array[Node]) -> void:
	if node is HTTPRequest:
		found.append(node)
		var http := node as HTTPRequest
		if not http.request_completed.is_connected(_on_http):
			http.request_completed.connect(_on_http)
	for child in node.get_children():
		_collect_http(child, found)


func _on_http(result: int, status: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and status >= 200:
		_live_http += 1


class DeadNet:
	var calls := 0

	func cancel() -> void:
		pass

	func is_ready() -> bool:
		return true

	func auth_headers(_access_token: String = "") -> PackedStringArray:
		return PackedStringArray()

	func request_json(_method: String, _url: String, _headers: PackedStringArray, _body: String = "") -> Dictionary:
		calls += 1
		return {"ok": false, "status": 0, "json": null, "error": "blocked", "result": HTTPRequest.RESULT_CANT_CONNECT}

	func request_json_independent(method: String, url: String, headers: PackedStringArray, body: String = "") -> Dictionary:
		return request_json(method, url, headers, body)
