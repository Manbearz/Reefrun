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
# Sprite and menu-file progress fill up to this. The remainder is the live menu.
const PREPARE_CAP := 0.9
# How quickly the bar closes the gap to the measured value. Not a load duration.
const SMOOTH_RATE := 14.0
const FINISH_RATE := 28.0

var _overlay: CanvasLayer
var _plate: Control
var _art: TextureRect
var _clip: Control
var _fill: TextureRect
var _status: Label
var _ids: PackedStringArray = PackedStringArray()
var _cursor := 0
var _finished := 0
var _failed := 0
var _inflight: PackedStringArray = PackedStringArray()
var _retries := {}
var _actual := 0.0
var _displayed := 0.0
var _visual_ready := false
var _aspect_saved := -1
var _menu_requested := false
var _menu_packed: PackedScene
var _menu_node: Node
var _menu_retries := 0
var _handoff := false
var _t0 := 0
var boot_ms := {}


func _ready() -> void:
	_t0 = Time.get_ticks_usec()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_use_full_screen()
	_build()
	_ids = _priority_first(Sprites.boot_ids())
	_request_menu()
	_kick()
	set_process(true)
	_stamp("screen")


func _process(delta: float) -> void:
	if _handoff:
		return
	# The menu was created last frame, so its first draw has finished.
	if _menu_node != null and not _visual_ready:
		_visual_ready = true
		_actual = 1.0
	elif _menu_node == null:
		_kick()
		_poll()
		_try_open()
	_follow(delta)
	_layout()
	if _visual_ready and _displayed >= 0.999:
		_stamp("shown")
		_finish_handoff(_menu_node)


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
			_failed += 1
			push_warning("[boot] missing sprite %s" % path)
			continue
		var err := ResourceLoader.load_threaded_request(path, "", false)
		if err == OK or err == ERR_ALREADY_EXISTS or err == ERR_BUSY:
			_inflight.append(path)
		else:
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
				_inflight.append(path)
			else:
				_recover_sprite(path)


func _poll() -> void:
	var still := PackedStringArray()
	var partial := 0.0
	for path in _inflight:
		var progress: Array = [0.0]
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				_take_sprite(path)
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				if not _retry_sprite(path):
					_recover_sprite(path)
				else:
					still.append(path)
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				still.append(path)
				# Stay under 1 until the loader reports the resource as loaded.
				if not progress.is_empty():
					partial += clampf(float(progress[0]), 0.0, 0.99)
			_:
				still.append(path)
	_inflight = still
	var required := float(_ids.size() + 1)
	var resource := clampf((float(_finished) + partial + _menu_fraction()) / required, 0.0, 1.0)
	# Leave the last slice for building and drawing the live menu.
	_actual = maxf(_actual, resource * PREPARE_CAP)


func _follow(delta: float) -> void:
	# Ease toward the measured value. A stall does not count as animation time.
	var gap := _actual - _displayed
	if gap <= 0.0:
		return
	if _actual >= 1.0 and gap <= 0.004:
		_displayed = _actual
		return
	var rate := FINISH_RATE if _actual >= 1.0 else SMOOTH_RATE
	var step_delta := clampf(delta, 0.0, 0.05)
	var blend := 1.0 - exp(-rate * step_delta)
	_displayed = minf(_actual, _displayed + gap * blend)


func _retry_sprite(path: String) -> bool:
	var attempts := int(_retries.get(path, 0))
	if attempts >= 1:
		return false
	_retries[path] = attempts + 1
	var err := ResourceLoader.load_threaded_request(path, "", false)
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_take_sprite(path)
		return false
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return true
	if err != OK and err != ERR_ALREADY_EXISTS and err != ERR_BUSY:
		push_warning("[boot] retry failed for %s: %s" % [path, error_string(err)])
	return false


func _take_sprite(path: String) -> void:
	var resource := ResourceLoader.load_threaded_get(path)
	if resource is Texture2D:
		Sprites.remember(path.get_file().get_basename(), resource)
		_finished += 1
	else:
		_failed += 1
		push_warning("[boot] sprite was not a texture: %s" % path)


func _recover_sprite(path: String) -> void:
	var resource := load(path) as Texture2D
	if resource:
		Sprites.remember(path.get_file().get_basename(), resource)
		_finished += 1
	else:
		_failed += 1
		push_warning("[boot] could not load %s" % path)


func _menu_fraction() -> float:
	if _menu_packed != null:
		return 1.0
	var progress: Array = [0.0]
	var status := ResourceLoader.load_threaded_get_status(MENU_PATH, progress)
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(MENU_PATH) as PackedScene
			if packed == null:
				return 0.0
			_menu_packed = packed
			return 1.0
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if progress.is_empty():
				return 0.0
			return clampf(float(progress[0]), 0.0, 0.99)
		_:
			return 0.0


func _menu_status() -> int:
	return ResourceLoader.load_threaded_get_status(MENU_PATH)


func _menu_ready() -> bool:
	return _menu_packed != null or _menu_status() == ResourceLoader.THREAD_LOAD_LOADED


func _service_menu() -> void:
	if _menu_ready() or _menu_retries >= 2:
		return
	var status := _menu_status()
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status != ResourceLoader.THREAD_LOAD_FAILED and status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		return
	_menu_retries += 1
	var err := ResourceLoader.load_threaded_request(MENU_PATH, "", false)
	status = _menu_status()
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
		return
	if err != OK and err != ERR_ALREADY_EXISTS and err != ERR_BUSY:
		push_warning("[boot] menu request failed: %s" % error_string(err))
	var packed := load(MENU_PATH) as PackedScene
	if packed != null:
		_menu_packed = packed


func _assets_done() -> bool:
	return _cursor >= _ids.size() and _inflight.is_empty()


func _try_open() -> void:
	if _menu_node != null or _handoff:
		return
	if not _assets_done():
		_set_status("")
		return
	_service_menu()
	if not _menu_ready():
		if _menu_retries >= 2:
			_set_status("Menu unavailable")
		return
	if _failed == 0 and _finished < _ids.size():
		return
	_set_status("")
	_stamp("resources")
	_spawn_menu()


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


func _spawn_menu() -> void:
	if _menu_node != null or _handoff:
		return
	var packed := _menu_packed if _menu_packed != null else ResourceLoader.load_threaded_get(MENU_PATH) as PackedScene
	if packed == null:
		_set_status("Menu unavailable")
		return
	var menu := packed.instantiate()
	add_child(menu)
	move_child(menu, 0)
	if menu is Control:
		(menu as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_node = menu
	_stamp("spawned")


func _stamp(key: String) -> void:
	boot_ms[key] = (Time.get_ticks_usec() - _t0) / 1000.0


func _finish_handoff(menu: Node) -> void:
	if _handoff or menu == null or not is_instance_valid(menu):
		return
	_handoff = true
	_restore_screen()
	var tree := get_tree()
	if tree == null:
		return
	tree.root.set_meta("boot_ms", boot_ms.duplicate())
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
	var amount := clampf(_displayed, 0.0, 1.0)
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
