extends Control

const MENU_PATH := "res://scenes/menu/main_menu.tscn"
const ART_PATH := "res://assets/sprites/loading_screen.png"
const BAR_PATH := "res://assets/sprites/loading_bar.png"
const ART_SIZE := Vector2(941, 1672)
# Empty trough inside the splash bar, in art pixels.
const BAR := Rect2(208, 1068, 524, 56)
# Opaque capsule inside loading_bar.png. The file has a large transparent margin.
const BAR_ART := Rect2(45, 228, 2050, 313)
const FISH_ID := "fish_blue"
const BATCH := 3
const FADE_SEC := 0.4

var _overlay: CanvasLayer
var _plate: Control
var _fade: Tween
var _art: TextureRect
var _clip: Control
var _fill: TextureRect
var _status: Label
var _ids: PackedStringArray = PackedStringArray()
var _cursor := 0
var _finished := 0
var _inflight: PackedStringArray = PackedStringArray()
var _progress := 0.0
var _shown := 0.0
var _aspect_saved := -1
var _menu_requested := false
var _opening := false
var _handoff := false
var _stall := 0.0
var _stall_mark := -1
var _menu_gave_up := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_full_screen()
	_build()
	_ids = _priority_first(Sprites.boot_ids())
	_request_menu()
	_kick()
	set_process(true)


func _process(delta: float) -> void:
	if not _opening:
		_kick()
		_poll()
		_try_open()
	var target := 1.0 if _opening else _progress
	if target > _shown:
		_shown = minf(target, _shown + delta * 0.85)
	else:
		_shown = target
	_layout()
	if _opening and _shown >= 0.995:
		_reveal_menu()


func _priority_first(ids: PackedStringArray) -> PackedStringArray:
	var ordered := PackedStringArray()
	var seen := {}
	for id in [FISH_ID, "background", "bubbles_small"]:
		if ids.has(id) and not seen.has(id):
			seen[id] = true
			ordered.append(id)
	for id in ids:
		if id == "loading_screen" or id == "loading_bar" or seen.has(id):
			continue
		seen[id] = true
		ordered.append(id)
	return ordered


func _request_menu() -> void:
	if _menu_requested:
		return
	_menu_requested = true
	var err := ResourceLoader.load_threaded_request(MENU_PATH, "", false)
	if err != OK and err != ERR_ALREADY_EXISTS and err != ERR_BUSY:
		push_warning("[boot] menu request failed: %s" % error_string(err))


func _kick() -> void:
	while _inflight.size() < BATCH and _cursor < _ids.size():
		var id := _ids[_cursor]
		_cursor += 1
		var path := Sprites.sprite_path(id)
		if not ResourceLoader.exists(path):
			_finished += 1
			continue
		var err := ResourceLoader.load_threaded_request(path, "", false)
		if err == OK or err == ERR_ALREADY_EXISTS or err == ERR_BUSY:
			_inflight.append(path)
		else:
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
				_inflight.append(path)
			else:
				_finished += 1


func _poll() -> void:
	var still := PackedStringArray()
	var partial := 0.0
	for path in _inflight:
		var progress: Array = [0.0]
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				var resource := ResourceLoader.load_threaded_get(path)
				if resource is Texture2D:
					Sprites.remember(path.get_file().get_basename(), resource)
				_finished += 1
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_finished += 1
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				still.append(path)
				if not progress.is_empty():
					partial += clampf(float(progress[0]), 0.0, 1.0)
			_:
				still.append(path)
	_inflight = still
	var denom := float(maxi(_ids.size(), 1) + 1)
	_progress = clampf((float(_finished) + partial + _menu_fraction()) / denom, 0.0, 1.0)


func _menu_fraction() -> float:
	var progress: Array = [0.0]
	var status := ResourceLoader.load_threaded_get_status(MENU_PATH, progress)
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			return 1.0
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if progress.is_empty():
				return 0.15
			return clampf(float(progress[0]), 0.0, 0.99)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return 1.0
		_:
			return 0.0


func _menu_failed() -> bool:
	if _menu_gave_up:
		return true
	var status := ResourceLoader.load_threaded_get_status(MENU_PATH)
	return status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE


func _assets_done() -> bool:
	return _cursor >= _ids.size() and _inflight.is_empty()


func _try_open() -> void:
	if _opening or _handoff:
		return
	_watch_for_stall()
	if not _assets_done():
		_set_status("")
		return
	if _menu_failed():
		_set_status("Menu unavailable")
		_progress = 1.0
		return
	if ResourceLoader.load_threaded_get_status(MENU_PATH) != ResourceLoader.THREAD_LOAD_LOADED:
		_set_status("")
		return
	_opening = true
	_progress = 1.0
	_set_status("")


func _watch_for_stall() -> void:
	var menu_busy := ResourceLoader.load_threaded_get_status(MENU_PATH) == ResourceLoader.THREAD_LOAD_IN_PROGRESS
	var busy := not _inflight.is_empty() or menu_busy
	if not busy or _finished != _stall_mark:
		_stall = 0.0
		_stall_mark = _finished
		return
	_stall += get_process_delta_time()
	if _stall < 8.0:
		return
	_finished += _inflight.size()
	_inflight = PackedStringArray()
	_cursor = _ids.size()
	if menu_busy:
		_menu_gave_up = true
	_stall = 0.0
	_stall_mark = _finished


func _use_full_screen() -> void:
	var root := get_tree().root if get_tree() else null
	if root == null:
		return
	_aspect_saved = root.content_scale_aspect
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


func _restore_screen() -> void:
	if _aspect_saved < 0:
		return
	var root := get_tree().root if get_tree() else null
	if root:
		root.content_scale_aspect = _aspect_saved
	_aspect_saved = -1


func _reveal_menu() -> void:
	if _handoff or (_fade != null and _fade.is_valid()):
		return
	var packed := ResourceLoader.load_threaded_get(MENU_PATH) as PackedScene
	if packed == null:
		_opening = false
		_set_status("Menu unavailable")
		return
	var menu := packed.instantiate()
	add_child(menu)
	move_child(menu, 0)
	if menu is Control:
		(menu as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _plate == null or not is_instance_valid(_plate):
		_finish_handoff(menu)
		return
	_fade = create_tween()
	var step := _fade.tween_property(_plate, "modulate:a", 0.0, FADE_SEC)
	if step == null:
		_finish_handoff(menu)
		return
	step.set_trans(Tween.TRANS_SINE)
	step.set_ease(Tween.EASE_IN_OUT)
	_fade.finished.connect(_finish_handoff.bind(menu), CONNECT_ONE_SHOT)


func _finish_handoff(menu: Node) -> void:
	if _handoff or menu == null or not is_instance_valid(menu):
		return
	_handoff = true
	_restore_screen()
	var tree := get_tree()
	if tree == null:
		return
	menu.reparent(tree.root, false)
	if menu is Control:
		(menu as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.current_scene = menu
	queue_free()


func _set_status(text: String) -> void:
	if _status == null:
		return
	_status.text = text
	_status.visible = not text.is_empty()


func _layout() -> void:
	var view := size
	if view.x < 8.0 or view.y < 8.0 or _art == null:
		return
	var scale := Vector2(view.x / ART_SIZE.x, view.y / ART_SIZE.y)
	_art.position = Vector2.ZERO
	_art.size = view
	var slot_pos := BAR.position * scale
	var slot_size := BAR.size * scale
	var amount := clampf(_shown, 0.0, 1.0)
	_clip.position = slot_pos
	_clip.size = Vector2(slot_size.x * amount, slot_size.y)
	_fill.position = Vector2.ZERO
	_fill.size = slot_size
	if _status.visible:
		var note := Vector2(slot_size.x, maxf(22.0, slot_size.y * 0.7))
		_status.position = slot_pos + Vector2(0.0, slot_size.y + 8.0)
		_status.size = note


func _build() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	_plate = Control.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_STOP
	_plate.modulate = Color(1, 1, 1, 1)
	_overlay.add_child(_plate)
	_plate.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var plate := _plate
	var deep := ColorRect.new()
	deep.color = Color8(0, 82, 156)
	deep.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	deep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(deep)
	_art = TextureRect.new()
	_art.texture = load(ART_PATH)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(_art)
	_clip = Control.new()
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.clip_contents = true
	plate.add_child(_clip)
	var bar_tex := load(BAR_PATH) as Texture2D
	var atlas := AtlasTexture.new()
	atlas.atlas = bar_tex
	atlas.region = BAR_ART
	_fill = TextureRect.new()
	_fill.texture = atlas
	_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fill.stretch_mode = TextureRect.STRETCH_SCALE
	_fill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_fill)
	_status = UIKit.make_label("", 16, Palette.FOAM)
	_status.visible = false
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(_status)
