extends SceneTree

# Closed local port. HTTPRequest ignores the project proxy setting, so each
# node is pointed at this address before it can open a socket.
const ISOLATED_PROXY_HOST := "127.0.0.1"
const ISOLATED_PROXY_PORT := 9

var _live_http := 0
var _blocked_http := 0


func _initialize() -> void:
	node_added.connect(_on_node_added)
	root.add_child(Runner.new())


func _on_node_added(node: Node) -> void:
	if node is HTTPRequest:
		_neuter_http(node as HTTPRequest)
	elif node.name == "Backend" and not node.ready.is_connected(_seal_backend):
		node.ready.connect(_seal_backend)


func _neuter_http(http: HTTPRequest) -> void:
	http.set_http_proxy(ISOLATED_PROXY_HOST, ISOLATED_PROXY_PORT)
	http.set_https_proxy(ISOLATED_PROXY_HOST, ISOLATED_PROXY_PORT)
	_blocked_http += 1
	if not http.request_completed.is_connected(_on_http_completed):
		http.request_completed.connect(_on_http_completed)


func _on_http_completed(result: int, status: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS or status >= 100:
		_live_http += 1


func _note_blocked_http() -> void:
	_blocked_http += 1


func _seal_backend() -> void:
	var backend := root.get_node_or_null("Backend")
	if backend == null or not ("_client" in backend):
		return
	backend._client = DeadNet.new()


class Runner extends Node:
	const COURSE_SEED := 827361

	func _ready() -> void:
		var host = Engine.get_main_loop()
		if host != null and host.has_method("_seal_backend"):
			host._seal_backend()
		var session := get_node_or_null("/root/GameSession")
		if session != null:
			session.match_mode = session.MODE_UNLIMITED
			session.course_seed = COURSE_SEED
			session.practice_daily = false
		var game: Node = load("res://scenes/game/game.tscn").instantiate()
		add_child(game)
		var waited := 0.0
		# Unlimited lobby is 8 seconds, so the old 8 second cap quit on the start frame.
		while not bool(game.get("started")) and waited < 10.5:
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
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		var terminal_ok := 0
		var rising_ok := 0
		var long_fall_ok := 0
		var touch_ok := 0
		var physics_ok := 0
		var sample := {}

		for i in 100:
			player.set("velocity", Vector2(0.0, RR.TERMINAL))
			player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))
			game.call("_try_player_flap")
			if is_equal_approx(float(player.get("velocity").y), -RR.FLAP):
				terminal_ok += 1

		for i in 100:
			player.set("velocity", Vector2(0.0, -400.0))
			player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))
			game.call("_try_player_flap")
			if is_equal_approx(float(player.get("velocity").y), -RR.FLAP):
				rising_ok += 1

		for i in 100:
			player.set("velocity", Vector2.ZERO)
			player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))
			for _t in 60:
				player.call("simulate_vertical", dt)
			var before := float(player.get("velocity").y)
			game.call("_try_player_flap")
			var after := float(player.get("velocity").y)
			player.call("simulate_vertical", dt)
			var phys1 := float(player.get("velocity").y)
			player.call("simulate_vertical", dt)
			var phys2 := float(player.get("velocity").y)
			if (
				before >= RR.TERMINAL * 0.9
				and is_equal_approx(after, -RR.FLAP)
				and phys1 < 0.0
				and phys2 < 0.0
			):
				long_fall_ok += 1
				if sample.is_empty():
					sample = {"before": before, "after": after, "phys1": phys1, "phys2": phys2}

		var vp := get_viewport()
		var pos := Vector2(RR.VIEW_W * 0.5, RR.VIEW_H * 0.55)
		for i in 50:
			player.set("velocity", Vector2(0.0, RR.TERMINAL))
			player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))
			var touch := InputEventScreenTouch.new()
			touch.index = 0
			touch.pressed = true
			touch.position = pos
			vp.push_input(touch)
			if is_equal_approx(float(player.get("velocity").y), -RR.FLAP):
				touch_ok += 1

		# Pipe overlap calls kill(), which replaces the flap velocity. Clearing
		# the mask keeps monitoring on so overlap queries stay valid and empty.
		var hit: Area2D = player.get("_hit_area")
		if hit == null:
			push_error("[fall-recovery] missing hit area")
			get_tree().quit(1)
			return
		hit.collision_mask = 0
		hit.collision_layer = 0
		if player.died.is_connected(game._on_player_died):
			player.died.disconnect(game._on_player_died)
		game.set_physics_process(true)
		for i in 50:
			game.set("finished", false)
			game.set("paused", false)
			player.set("alive", true)
			player.set("started", true)
			player.set("motion_lock", false)
			player.set("velocity", Vector2(0.0, RR.TERMINAL))
			player.set("position", Vector2(RR.PLAYER_X, RR.VIEW_H * 0.42))
			game.call("_try_player_flap")
			var followed := float(player.get("velocity").y)
			await get_tree().physics_frame
			await get_tree().physics_frame
			var follow := float(player.get("velocity").y)
			if is_equal_approx(followed, -RR.FLAP) and follow < 0.0:
				physics_ok += 1

		print("[fall-recovery] FLAP=%.1f TERMINAL=%.1f" % [RR.FLAP, RR.TERMINAL])
		print("[fall-recovery] terminal %d/100 rising %d/100 long_fall %d/100 touch %d/50 physics_follow %d/50" % [
			terminal_ok, rising_ok, long_fall_ok, touch_ok, physics_ok
		])
		if not sample.is_empty():
			print(
				"[fall-recovery] sample before=%.1f after=%.1f phys1=%.1f phys2=%.1f"
				% [float(sample.before), float(sample.after), float(sample.phys1), float(sample.phys2)]
			)
		var live := 0
		var blocked := 0
		if host != null:
			live = int(host.get("_live_http"))
			blocked = int(host.get("_blocked_http"))
		print("[isolate] blocked=%d live=%d" % [blocked, live])
		var ok := (
			terminal_ok == 100
			and rising_ok == 100
			and long_fall_ok == 100
			and touch_ok == 50
			and physics_ok == 50
			and live == 0
		)
		if live > 0:
			push_error("[isolate] live http responses=%d" % live)
		get_tree().quit(0 if ok else 1)


class DeadNet:
	func cancel() -> void:
		pass

	func is_ready() -> bool:
		return true

	func auth_headers(_access_token: String = "") -> PackedStringArray:
		return PackedStringArray()

	func request_json(_method: String, _url: String, _headers: PackedStringArray, _body: String = "") -> Dictionary:
		var host = Engine.get_main_loop()
		if host != null and host.has_method("_note_blocked_http"):
			host._note_blocked_http()
		return {"ok": false, "status": 0, "json": null, "error": "blocked", "result": HTTPRequest.RESULT_CANT_CONNECT}

	func request_json_independent(method: String, url: String, headers: PackedStringArray, body: String = "") -> Dictionary:
		return request_json(method, url, headers, body)
