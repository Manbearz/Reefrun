extends Node

const Feedback := preload("res://scripts/button_feedback.gd")

# Attaches ButtonFeedback to every Button and TextureButton as it enters the tree.
# Touch drags are watched here so a highlight cannot stay on after the finger leaves.

var using_touch := false
var _held = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		Feedback.attach(node)


func hold(feedback) -> void:
	_held = feedback


func drop(feedback) -> void:
	if _held == feedback:
		_held = null


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		using_touch = true
	elif event is InputEventMouse:
		using_touch = (event as InputEventMouse).device < 0
	if _held == null or not is_instance_valid(_held):
		_held = null
		return
	var point := Vector2.INF
	var released := false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		point = touch.position
		released = not touch.pressed
	elif event is InputEventScreenDrag:
		point = (event as InputEventScreenDrag).position
	else:
		return
	var target: BaseButton = _held.button()
	if target == null or not is_instance_valid(target) or released or not target.get_global_rect().has_point(point):
		_held.release_touch()
		_held = null
