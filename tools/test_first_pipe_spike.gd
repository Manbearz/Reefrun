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
		await get_tree().process_frame
		game.set("_lobby_t", RR.LOBBY_SECS)
		game.set("_in_lobby", false)
		game.call("_begin_run")
		var player: Node = game.get("player")
		if player != null and player.died.is_connected(game._on_player_died):
			player.died.disconnect(game._on_player_died)
		var waited := 0.0
		while int(game.get("score")) < 2 and waited < 12.0:
			if player:
				player.set("alive", true)
				player.set("started", true)
				game.set("finished", false)
				var gap := _gap_for_fish(game, player)
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
		var live := 0
		var blocked := 0
		if host != null:
			live = int(host.get("_live_http"))
			blocked = int(host.get("_blocked_http"))
		print("[isolate] blocked=%d live=%d" % [blocked, live])
		if live > 0:
			push_error("[isolate] live http responses=%d" % live)
		get_tree().quit(0 if int(game.get("score")) >= 2 and live == 0 else 1)


	func _gap_for_fish(game: Node, player: Node) -> float:
		var fish := player as Node2D
		if fish == null:
			return float(game.call("_upcoming_gap"))
		var fish_x := fish.global_position.x
		var pipes: Array = game.get("pipes")
		var overlap: Node = null
		var overlap_dx := INF
		var nearest: Node = null
		var nearest_dx := INF
		for pair in pipes:
			if pair == null or not is_instance_valid(pair):
				continue
			if not bool(pair.get("active")):
				continue
			var body := pair as Node2D
			if body == null:
				continue
			var half := _pipe_half_width(pair)
			var dx := absf(body.global_position.x - fish_x)
			if dx < nearest_dx:
				nearest_dx = dx
				nearest = pair
			if dx <= half + RR.FISH_HIT and dx < overlap_dx:
				overlap_dx = dx
				overlap = pair
		var chosen: Node = overlap if overlap != null else nearest
		if chosen == null:
			return float(game.call("_upcoming_gap"))
		return float(chosen.get("gap_y"))


	func _pipe_half_width(pair: Node) -> float:
		var rect := pair.get("_top_rect") as RectangleShape2D
		if rect != null and rect.size.x > 1.0:
			return rect.size.x * 0.5
		return 48.0


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
