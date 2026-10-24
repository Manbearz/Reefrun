class_name MockRewardedAdProvider
extends RewardedAdProvider

enum Outcome {
	SUCCESS,
	CLOSED_NO_REWARD,
	FAILED,
	UNAVAILABLE,
	# Scripted tests hold the show open until the test emits callbacks itself.
	STALL,
}

const AdCfg := preload("res://scripts/ads/ad_config.gd")

var outcome: Outcome = Outcome.SUCCESS
var duplicate_reward_signal := false
var resolve_delay := 0.05
var show_calls := 0
var _scripted := false
var _settled := false
var _panel: CanvasLayer
var _live_session := 0


func is_available() -> bool:
	return outcome != Outcome.UNAVAILABLE


func prepare_interactive() -> void:
	_scripted = false
	_settled = false
	outcome = Outcome.SUCCESS
	duplicate_reward_signal = false
	show_calls = 0
	_close_panel()


func mark_scripted(next_outcome: int, duplicate_reward: bool, delay: float) -> void:
	_scripted = true
	_settled = false
	outcome = next_outcome
	duplicate_reward_signal = duplicate_reward
	resolve_delay = delay
	show_calls = 0
	_close_panel()


func simulator_button(action: String) -> BaseButton:
	if _panel == null or not is_instance_valid(_panel):
		return null
	return _panel.find_child("sim_%s" % action, true, false) as BaseButton


func show_session(session_id: int) -> void:
	show_calls += 1
	# An exported binary must not reach this provider. If it does, grant nothing.
	if not AdCfg.use_mock_provider():
		_emit_unavailable(session_id)
		return
	if _scripted:
		_show_scripted(session_id)
		return
	if not AdCfg.development_reward_simulator():
		_emit_unavailable(session_id)
		return
	if _panel != null and is_instance_valid(_panel):
		return
	_live_session = session_id
	_present_simulator()


func _show_scripted(session_id: int) -> void:
	if outcome == Outcome.UNAVAILABLE:
		_emit_unavailable(session_id)
		return
	if outcome == Outcome.STALL:
		return
	# Bind the id now. A later show must not retarget this callback.
	if resolve_delay <= 0.0:
		_queue_resolve(session_id)
		return
	get_tree().create_timer(resolve_delay).timeout.connect(_queue_resolve.bind(session_id), CONNECT_ONE_SHOT)


func _queue_resolve(session_id: int) -> void:
	call_deferred("_resolve_session", session_id)


func _resolve_session(session_id: int) -> void:
	if not _scripted or _settled:
		return
	_settled = true
	match outcome:
		Outcome.SUCCESS:
			_emit_reward(session_id)
			if duplicate_reward_signal:
				_emit_reward(session_id)
			_emit_closed(session_id)
		Outcome.CLOSED_NO_REWARD:
			_emit_closed(session_id)
		Outcome.FAILED:
			_emit_failed("mock_failed", session_id)
		_:
			_emit_unavailable(session_id)


func _present_simulator() -> void:
	_settled = false
	var layer := CanvasLayer.new()
	layer.layer = 90
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = layer
	add_child(layer)
	var screen := Vector2(540, 960)
	var tree := get_tree()
	if tree != null and tree.root != null:
		var visible := tree.root.get_visible_rect().size
		if visible.x > 8.0 and visible.y > 8.0:
			screen = visible
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.position = Vector2.ZERO
	root.size = screen
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.08, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.position = Vector2.ZERO
	dim.size = screen
	root.add_child(dim)
	var card_size := Vector2(screen.x * 0.84, screen.y * 0.56)
	var card := ColorRect.new()
	card.color = Color8(8, 28, 48)
	card.position = (screen - card_size) * 0.5
	card.size = card_size
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(card)
	card.add_child(_banner("TEST AD", card_size, 0.04, 28, Color8(255, 214, 64)))
	card.add_child(_banner("SIMULATED REWARD", card_size, 0.16, 22, Color8(255, 244, 210)))
	card.add_child(_banner("Editor only. This is not a real advertisement.", card_size, 0.30, 16, Color8(232, 244, 255)))
	card.add_child(_action_button("sim_complete", "Complete simulated reward", card_size, 0.48, _press_complete))
	card.add_child(_action_button("sim_cancel", "Cancel ad", card_size, 0.66, _press_cancel))
	card.add_child(_action_button("sim_unavailable", "Ad unavailable", card_size, 0.84, _press_unavailable))


func _banner(text: String, card_size: Vector2, y_ratio: float, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(12, card_size.y * y_ratio)
	label.size = Vector2(maxf(40.0, card_size.x - 24.0), 40)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _action_button(node_name: String, text: String, card_size: Vector2, y_ratio: float, pressed: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.position = Vector2(24, card_size.y * y_ratio)
	button.size = Vector2(maxf(40.0, card_size.x - 48.0), 44)
	button.pressed.connect(pressed)
	return button


func _press_complete() -> void:
	if not _grant_once():
		return
	# Same order as AdMob: the reward callback, then the ad closing.
	_emit_reward(_live_session)
	_emit_closed(_live_session)
	_close_panel()


func _press_cancel() -> void:
	if not _grant_once():
		return
	_emit_closed(_live_session)
	_close_panel()


func _press_unavailable() -> void:
	if not _grant_once():
		return
	_emit_unavailable(_live_session)
	_close_panel()


func _grant_once() -> bool:
	if _scripted or _settled or not AdCfg.development_reward_simulator():
		return false
	_settled = true
	if _panel != null and is_instance_valid(_panel):
		for action in ["complete", "cancel", "unavailable"]:
			var button := simulator_button(action)
			if button:
				button.disabled = true
	return true


func _close_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
