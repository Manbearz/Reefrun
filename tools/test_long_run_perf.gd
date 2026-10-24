extends SceneTree

# Headless long-run memory and step-cost probe. It drives the real pipe,
# coin, harpoon, and Deep Dive paths. It does not submit scores or show ads.
# Godot --headless --path . --script res://tools/test_long_run_perf.gd

const DT := 0.1
const UNLIMITED_MARKS: Array[int] = [100, 500, 1000, 2000, 5000]
const DAILY_MARKS: Array[int] = [100, 500, 1000]
const RESTARTS := 100

var _failed := 0
var _live_http := 0


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
	print("[perf] godot=%s.%s.%s" % [version.major, version.minor, version.patch])
	_seal_network()
	await process_frame
	_seal_network()
	var session := root.get_node("GameSession")
	var saved_mode: String = session.match_mode
	var saved_seed: int = session.course_seed
	var saved_practice: bool = session.practice_daily
	var saved_coins: int = int(session.coins)
	var saved_games: int = int(session.games_played)
	var nodes_before: int = _nodes()
	print("[perf] baseline nodes=%d static=%d objects=%d resources=%d orphans=%d" % [
		nodes_before, _static_mem(), _objects(), _resources(), _orphans(),
	])
	var unlimited: Dictionary = _simulate("unlimited", 1, UNLIMITED_MARKS, 5000)
	_check("unlimited_reached", int(unlimited["score"]) >= 5000, "score=%d steps=%d" % [int(unlimited["score"]), int(unlimited["steps"])])
	_check("unlimited_pipes_bounded", bool(unlimited["pipes_bounded"]))
	_check("unlimited_harpoons_fixed", bool(unlimited["harpoons_fixed"]))
	_check("unlimited_dive_bounded", bool(unlimited["dive_bounded"]))
	_check("unlimited_audio_fixed", bool(unlimited["audio_fixed"]))
	_check("unlimited_coins_bounded", bool(unlimited["coins_bounded"]))
	var daily: Dictionary = _simulate("daily", 1, DAILY_MARKS, 1000)
	_check("daily_reached", int(daily["score"]) >= 1000, "score=%d steps=%d" % [int(daily["score"]), int(daily["steps"])])
	_check("daily_pipes_bounded", bool(daily["pipes_bounded"]))
	_check("daily_harpoons_fixed", bool(daily["harpoons_fixed"]))
	_check("daily_audio_fixed", bool(daily["audio_fixed"]))
	_check("daily_coins_bounded", bool(daily["coins_bounded"]))
	_check("wallet_untouched", int(session.coins) == saved_coins and int(session.games_played) == saved_games, "coins=%d games=%d" % [int(session.coins), int(session.games_played)])
	await _restart_cycles()
	session.match_mode = saved_mode
	session.course_seed = saved_seed
	session.practice_daily = saved_practice
	_check("network_blocked", _live_http == 0, "live_http=%d" % _live_http)
	var nodes_after: int = _nodes()
	print("[perf] after_restarts nodes=%d static=%d objects=%d resources=%d orphans=%d delta_nodes=%d" % [
		nodes_after, _static_mem(), _objects(), _resources(), _orphans(), nodes_after - nodes_before,
	])
	print("[perf] failed=%d" % _failed)
	quit(0 if _failed == 0 else 1)


func _simulate(mode: String, seed: int, marks: Array[int], target: int) -> Dictionary:
	var game = _boot(mode, seed)
	var events = game._events
	var sfx := root.get_node_or_null("Sfx")
	var seen := {}
	var steps := 0
	var cap := 280000 if target >= 5000 else 120000
	var idle := 0.0
	var last_score := 0
	var pipes_bounded := true
	var harpoons_fixed := true
	var dive_bounded := true
	var audio_fixed := true
	var coins_bounded := true
	var peak_coins := 0
	var peak_coin_nodes := 0
	var harpoon_base: int = game._harpoons.size()
	var audio_base: int = _audio_players(sfx)
	var early_us := 0
	var early_n := 0
	var late_us := 0
	var late_n := 0
	var worst_us := 0
	var worst_score := 0
	var mem0 := _static_mem()
	var next_progress := 500
	print("[perf] %s start mem=%d nodes=%d harpoons=%d audio_players=%d" % [mode, mem0, _nodes(), harpoon_base, audio_base])
	while steps < cap and int(game.score) < target:
		steps += 1
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
		else:
			game._collect_coins()
			if game._scoring_open():
				game._score_pipes()
		var step_us := int(Time.get_ticks_usec() - started)
		var score := int(game.score)
		if step_us > worst_us:
			worst_us = step_us
			worst_score = score
		if score >= 80 and score < 120:
			early_us += step_us
			early_n += 1
		elif score >= target - 200 and score < target:
			late_us += step_us
			late_n += 1
		var pipe_nodes: int = game.pipes.size() + game._pipe_pool.size()
		if pipe_nodes > RR.PIPE_POOL_SIZE + 4:
			pipes_bounded = false
		if game._harpoons.size() != harpoon_base:
			harpoons_fixed = false
		if game._dive_field != null and game._dive_field.obstacle_nodes() > 8:
			dive_bounded = false
		if _audio_players(sfx) != audio_base:
			audio_fixed = false
		var coin_nodes: int = game._coins.size() + game._coin_pool.size()
		peak_coins = maxi(peak_coins, game._coins.size())
		peak_coin_nodes = maxi(peak_coin_nodes, coin_nodes)
		if game._coins.size() > 4 or coin_nodes > 4:
			coins_bounded = false
		var busy: bool = diving or int(game._harpoon_beat) != 0 or (events != null and not events.pipes_allowed())
		if busy or score != last_score:
			idle = 0.0
			last_score = score
		else:
			idle += DT
		if idle > 8.0:
			push_error("[perf] %s stalled at score=%d spawn=%d beat=%d" % [mode, score, game.spawn_index, game._harpoon_beat])
			break
		for mark in marks:
			if score >= mark and not seen.has(mark):
				seen[mark] = true
				_print_mark(mode, game, sfx, mark, steps, step_us)
		if score >= next_progress:
			print("[perf] %s progress score=%d steps=%d coins=%d mem=%d" % [mode, score, steps, game._coins.size(), _static_mem()])
			next_progress += 500
	var final_score := int(game.score)
	if final_score < target:
		_print_mark(mode, game, sfx, final_score, steps, worst_us)
	var early_avg := float(early_us) / float(maxi(early_n, 1))
	var late_avg := float(late_us) / float(maxi(late_n, 1))
	print("[perf] %s done score=%d steps=%d early_us=%.1f late_us=%.1f worst_us=%d worst_score=%d mem=%d->%d coins=%d coin_nodes=%d peak_coins=%d peak_coin_nodes=%d layout=%d lanes=%d fired=%d" % [
		mode,
		final_score,
		steps,
		early_avg,
		late_avg,
		worst_us,
		worst_score,
		mem0,
		_static_mem(),
		game._coins.size(),
		game._coins.size() + game._coin_pool.size(),
		peak_coins,
		peak_coin_nodes,
		game.layout.size(),
		game._harpoon_lanes.size(),
		0 if game._events == null else game._events.fired_log.size(),
	])
	var snapshot := {
		"score": final_score,
		"steps": steps,
		"pipes_bounded": pipes_bounded,
		"harpoons_fixed": harpoons_fixed,
		"dive_bounded": dive_bounded,
		"audio_fixed": audio_fixed,
		"coins_bounded": coins_bounded,
	}
	game.free()
	return snapshot


func _print_mark(mode: String, game, sfx: Node, mark: int, steps: int, step_us: int) -> void:
	var live_dive := 0
	var dive_nodes := 0
	if game._dive_field != null:
		live_dive = int(game._dive_field.live_count())
		dive_nodes = int(game._dive_field.obstacle_nodes())
	var fired := 0
	if game._events != null:
		fired = game._events.fired_log.size()
	var visible := 0
	for spr in game._coins:
		if spr != null and spr.visible:
			visible += 1
	var coin_nodes: int = game._coins.size() + game._coin_pool.size()
	print("[perf] mark mode=%s score=%d steps=%d static=%d nodes=%d objects=%d resources=%d pipes=%d pool=%d pipe_nodes=%d coins=%d coin_pool=%d coin_nodes=%d coins_visible=%d harpoons=%d dive_live=%d dive_nodes=%d ghosts=%d logical=%d flaps=%d audio_players=%d audio_playing=%d layout=%d lanes=%d fired=%d step_us=%d" % [
		mode,
		mark,
		steps,
		_static_mem(),
		_nodes(),
		_objects(),
		_resources(),
		game.pipes.size(),
		game._pipe_pool.size(),
		game.pipes.size() + game._pipe_pool.size(),
		game._coins.size(),
		game._coin_pool.size(),
		coin_nodes,
		visible,
		game._harpoons.size(),
		live_dive,
		dive_nodes,
		game.ghosts.size(),
		game.logical_death.size(),
		game._recorded_flaps.size(),
		_audio_players(sfx),
		_audio_playing(sfx),
		game.layout.size(),
		game._harpoon_lanes.size(),
		fired,
		step_us,
	])


func _restart_cycles() -> void:
	var sfx := root.get_node_or_null("Sfx")
	var backend := root.get_node_or_null("Backend")
	var base_nodes := _nodes()
	var base_mem := _static_mem()
	var base_audio := _audio_players(sfx)
	var signals_before := _backend_connections(backend)
	var menu_scene: PackedScene = load("res://scenes/menu/main_menu.tscn")
	for i in RESTARTS:
		var game = _boot("unlimited", 1)
		for _step in 12:
			game.player.alive = true
			game.scroll += RR.PIPE_SPEED * DT
			if game._can_spawn_pipes():
				game._spawn_pipes()
			game._cull_pipes()
			if game._scoring_open():
				game._score_pipes()
		if game.overlay == null:
			game._show_over(2, 0)
		game.free()
		var menu = menu_scene.instantiate()
		root.add_child(menu)
		menu.set_process(false)
		menu.set_process_input(false)
		menu.free()
		if (i + 1) % 25 == 0:
			print("[perf] restart cycle=%d nodes=%d static=%d objects=%d orphans=%d audio=%d backend_signals=%d" % [
				i + 1, _nodes(), _static_mem(), _objects(), _orphans(), _audio_players(sfx), _backend_connections(backend),
			])
	var nodes_now := _nodes()
	var signals_after := _backend_connections(backend)
	print("[perf] restarts=%d nodes=%d->%d static=%d->%d audio=%d->%d backend_signals=%d->%d" % [
		RESTARTS, base_nodes, nodes_now, base_mem, _static_mem(), base_audio, _audio_players(sfx), signals_before, signals_after,
	])
	_check("restart_nodes", nodes_now <= base_nodes + 8, "%d -> %d" % [base_nodes, nodes_now])
	_check("restart_audio", _audio_players(sfx) == base_audio)
	_check("restart_signals", signals_after <= signals_before + 2, "%d -> %d" % [signals_before, signals_after])


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


func _audio_players(sfx: Node) -> int:
	if sfx == null:
		return 0
	return int(sfx._players.size())


func _audio_playing(sfx: Node) -> int:
	if sfx == null:
		return 0
	var playing := 0
	for player in sfx._players:
		if player.playing:
			playing += 1
	return playing


func _backend_connections(backend: Node) -> int:
	if backend == null:
		return 0
	var total := 0
	for sig in ["leaderboards_ready", "identity_ready", "share_rewards_changed", "daily_missions_changed"]:
		if backend.has_signal(sig):
			total += backend.get_signal_connection_list(sig).size()
	return total


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


func _check(name: String, passed: bool, detail: String = "") -> void:
	if passed:
		print("[perf] %s=pass" % name)
	else:
		_failed += 1
		print("[perf] %s=FAIL %s" % [name, detail])


func _seal_network() -> void:
	var backend := root.get_node_or_null("Backend")
	if backend == null or not ("_client" in backend):
		return
	var dead := DeadNet.new()
	dead.owner_tree = self
	backend._client = dead
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
	var owner_tree: SceneTree

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
