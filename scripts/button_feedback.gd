extends Node

# Visual hover and press for any BaseButton. Layout position and size stay put.
# The click signal is never emitted from here.

const HOVER_SEC := 0.10
const PRESS_SEC := 0.08
const HOVER_SCALE := 1.03
const PRESS_SCALE := 0.965
const HOVER_TINT := Color(1.12, 1.16, 1.20, 1.0)
const PRESS_TINT := Color(0.84, 0.90, 0.97, 1.0)
const PLATE_REST := Color(1, 1, 1, 0)
const PLATE_HOVER := Color(1.12, 1.18, 1.24, 0.72)
const PLATE_PRESS := Color(0.62, 0.64, 0.66, 0.78)

var _button: BaseButton
var _visual: CanvasItem
var _plate: TextureRect
var _plate_anchor := Rect2()
var _plate_kind := "auto"
var _art_scale := Vector2.ONE
var _art_modulate := Color.WHITE
var _button_scale := Vector2.ONE
var _hover := false
var _inside := false
var _pressed := false
var _armed := false
var _touch_hold := false
var _safety := 0.0
var _tween: Tween
var _host: Node
var _mode := -1
var _saw_engine_hover := false
var _saw_engine_press := false
var goal_scale := Vector2.ONE


static func attach(button: BaseButton) -> void:
	if button == null or not is_instance_valid(button):
		return
	if button.has_meta(&"_rr_feedback"):
		return
	if _owns_states(button):
		return
	button.set_meta(&"_rr_feedback", true)
	var node: Node = (load("res://scripts/button_feedback.gd") as GDScript).new()
	node.name = "ButtonFeedback"
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	button.add_child(node)


# Tint and scale this drawing. The button stays the hitbox.
static func use_visual(button: BaseButton, visual: CanvasItem) -> void:
	if button == null or visual == null:
		return
	button.set_meta(&"_rr_visual", visual)


# Brighten only the painted button inside this texture region. hit and plate are texture pixels.
static func use_plate(button: BaseButton, texture: Texture2D, hit: Rect2, plate: Rect2, radius_ratio: float, kind := "auto") -> void:
	if button == null or texture == null or hit.size.x < 1.0 or hit.size.y < 1.0:
		return
	button.set_meta(&"_rr_plate", {
		"texture": texture,
		"region": plate,
		"anchor": Rect2(
			(plate.position.x - hit.position.x) / hit.size.x,
			(plate.position.y - hit.position.y) / hit.size.y,
			plate.size.x / hit.size.x,
			plate.size.y / hit.size.y
		),
		"kind": kind,
		"radius": radius_ratio,
	})


static func _owns_states(button: BaseButton) -> bool:
	if button is TextureButton:
		var textured := button as TextureButton
		if textured.texture_hover != null or textured.texture_pressed != null:
			return true
	if not button.has_theme_stylebox_override("hover") or not button.has_theme_stylebox_override("pressed"):
		return false
	var hover := button.get_theme_stylebox("hover")
	var pressed := button.get_theme_stylebox("pressed")
	if hover is StyleBoxEmpty or pressed is StyleBoxEmpty:
		return false
	return hover != pressed


func button() -> BaseButton:
	return _button


func release_touch() -> void:
	_touch_hold = false
	_safety = 0.0
	_pressed = false
	_hover = false
	_inside = false
	# A finger lift must not leave a hover. A mouse that is still over the
	# button gets the hover state back on the next sync.
	if not _touching() and _engine_hover():
		_hover = true
		_inside = true
	_apply(false)


func _ready() -> void:
	_button = get_parent() as BaseButton
	if _button == null:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_button_scale = _button.scale
	_host = get_node_or_null("/root/UiFeedback")
	_clear_theme_rects()
	_bind_art()
	_fit_pivot()
	if not _button.resized.is_connected(_fit_pivot):
		_button.resized.connect(_fit_pivot)
	_button.mouse_entered.connect(_on_enter)
	_button.mouse_exited.connect(_on_exit)
	_button.button_down.connect(_on_down)
	_button.button_up.connect(_on_up)
	_button.pressed.connect(_on_action)
	_button.visibility_changed.connect(_on_visibility)
	_button.tree_exiting.connect(_on_exit_tree)


func _bind_art() -> void:
	if _button.has_meta(&"_rr_visual"):
		_visual = _button.get_meta(&"_rr_visual") as CanvasItem
		if _visual != null:
			_art_scale = _visual.scale
			_art_modulate = _visual.modulate
			if _visual is Control and not (_visual as Control).resized.is_connected(_fit_pivot):
				(_visual as Control).resized.connect(_fit_pivot)
			return
	if not _button.has_meta(&"_rr_plate"):
		if _button is TextureButton and (_button as TextureButton).texture_normal != null:
			call_deferred("_lift_texture")
			return
		if _draws_itself(_button):
			_art_scale = _button.scale
			_art_modulate = _button.modulate
		return
	call_deferred("_build_plate")


func _build_plate() -> void:
	if _button == null or not is_instance_valid(_button) or _plate != null:
		return
	if not _button.has_meta(&"_rr_plate"):
		return
	var info: Dictionary = _button.get_meta(&"_rr_plate")
	var texture: Texture2D = info.get("texture") as Texture2D
	if texture == null:
		return
	var region: Rect2 = info.get("region")
	_plate_anchor = info.get("anchor")
	_plate_kind = str(info.get("kind", "auto"))
	var key := _mask_key(texture, region, _plate_kind)
	if _masks.has(key):
		var cached = _masks[key]
		if cached is Image:
			_apply_plate_image(cached)
		return
	var area := int(region.size.x) * int(region.size.y)
	# Auto tries six full scans. A large explicit face is the same kind of
	# main-thread stall. Both wait for the sliced baker instead of running here.
	if _plate_kind == "auto" or area > HEAVY_PLATE_PIXELS:
		_enqueue_plate(self, texture, region, _plate_kind)
		return
	var image := _silhouette(texture, region, _plate_kind)
	if image == null:
		return
	_apply_plate_image(image)


func _apply_plate_image(image: Image) -> void:
	if _button == null or not is_instance_valid(_button) or _plate != null or image == null:
		return
	_plate = TextureRect.new()
	_plate.name = "ButtonPlate"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.texture = ImageTexture.create_from_image(image)
	_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_plate.stretch_mode = TextureRect.STRETCH_SCALE
	_plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_plate.modulate = PLATE_REST
	_button.add_child(_plate)
	_place_plate()
	_apply(true)


# Scale a copy of the icon so the TextureButton's hitbox never changes size.
func _lift_texture() -> void:
	if _button == null or not is_instance_valid(_button) or _visual != null:
		return
	if not (_button is TextureButton):
		return
	var tex := _button as TextureButton
	if tex.texture_normal == null:
		return
	var art := TextureRect.new()
	art.name = "ButtonArt"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.grow_horizontal = Control.GROW_DIRECTION_BOTH
	art.grow_vertical = Control.GROW_DIRECTION_BOTH
	art.texture = tex.texture_normal
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = tex.texture_filter
	tex.ignore_texture_size = true
	tex.texture_normal = null
	_button.add_child(art)
	_visual = art
	_art_scale = Vector2.ONE
	_art_modulate = Color.WHITE
	_fit_pivot()
	_apply(true)


func _clear_theme_rects() -> void:
	# Flat image hotspots were still drawing the default theme focus StyleBoxFlat.
	var empty := StyleBoxEmpty.new()
	var flat_button := _button is Button and (_button as Button).flat
	if flat_button:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			_button.add_theme_stylebox_override(state, empty)
	elif not _button.has_theme_stylebox_override("focus"):
		_button.add_theme_stylebox_override("focus", empty)


func _draws_itself(button: BaseButton) -> bool:
	if button is TextureButton:
		return (button as TextureButton).texture_normal != null
	if button is Button:
		return not (button as Button).text.is_empty()
	return false


const HEAVY_PLATE_PIXELS := 50000
const PLATE_PIXELS_PER_FRAME := 2000
const PLATE_SLICE_USEC := 1200

static var _masks := {}
static var _decoded := {}
static var _jobs: Array = []
static var _baker
static var _baker_key := ""
static var _baker_hosts: Array = []
static var _service_frame := -1
static var defer_heavy_plates := false
static var main_thread_pixels := 0
static var last_pump_usec := 0
static var last_decode_usec := 0
static var work_serial := 0


static func warm_plate(texture: Texture2D, region: Rect2, kind: String) -> void:
	_enqueue_plate(null, texture, region, kind)


static func service_plates() -> void:
	var frame := Engine.get_process_frames()
	if _service_frame == frame:
		return
	_service_frame = frame
	if defer_heavy_plates:
		return
	if _baker == null:
		if _jobs.is_empty():
			return
		# Decoding the source image is its own frame. Pixel work starts on the next one.
		_begin_job(_jobs.pop_front())
		return
	var started := Time.get_ticks_usec()
	var finished := false
	var guard := 0
	while not finished and guard < 16:
		guard += 1
		var before := int(_baker.pumped)
		finished = bool(_baker.pump(200))
		if int(_baker.pumped) == before:
			break
		if Time.get_ticks_usec() - started >= PLATE_SLICE_USEC:
			break
	last_pump_usec = Time.get_ticks_usec() - started
	main_thread_pixels += int(_baker.pumped)
	_baker.pumped = 0
	work_serial += 1
	if finished:
		_finish_baker()


static func cache_label() -> String:
	var ready := 0
	for key in _masks:
		if _masks[key] is Image:
			ready += 1
	var waiting := _jobs.size() + (1 if _baker != null else 0)
	return "ready=%d waiting=%d" % [ready, waiting]


static func drop_dead_hosts() -> void:
	var live: Array = []
	for host in _baker_hosts:
		if is_instance_valid(host):
			live.append(host)
	_baker_hosts = live
	for job in _jobs:
		var hosts: Array = job.get("hosts", [])
		var kept: Array = []
		for host in hosts:
			if is_instance_valid(host):
				kept.append(host)
		job["hosts"] = kept


static func plate_diag() -> String:
	var phase := "idle"
	var kind_i := -1
	var kinds := 0
	if _baker != null:
		phase = str(_baker.phase)
		kind_i = int(_baker.kind_i)
		kinds = int(_baker.kind_list.size())
	return "phase=%s kind=%d/%d jobs=%d defer=%s serial=%d" % [
		phase, kind_i, kinds, _jobs.size(), str(defer_heavy_plates), work_serial
	]


static func debug_bake(texture: Texture2D, region: Rect2, kind: String) -> Image:
	var full := _decoded_image(texture)
	if full == null:
		return null
	var rect := Rect2i(int(region.position.x), int(region.position.y), int(region.size.x), int(region.size.y))
	if rect.size.x < 4 or rect.size.y < 4 or rect.position.x < 0 or rect.position.y < 0:
		return null
	if rect.end.x > full.get_width() or rect.end.y > full.get_height():
		return null
	var crop := full.get_region(rect)
	if crop.get_format() != Image.FORMAT_RGBA8:
		crop.convert(Image.FORMAT_RGBA8)
	var baker := PlateBaker.new()
	baker.setup(crop.get_data(), crop.get_width(), crop.get_height(), kind)
	var guard := 0
	while not baker.pump(250000) and guard < 8:
		guard += 1
	return baker.result()


static func _mask_key(texture: Texture2D, region: Rect2, kind: String) -> String:
	var path := texture.resource_path
	if path.is_empty():
		path = "id:%d" % texture.get_instance_id()
	return "%s|%s|%s" % [path, region, kind]


static func _enqueue_plate(host: Node, texture: Texture2D, region: Rect2, kind: String) -> void:
	if texture == null:
		return
	var key := _mask_key(texture, region, kind)
	if _masks.has(key):
		var cached = _masks[key]
		if host != null and is_instance_valid(host) and cached is Image:
			host._apply_plate_image(cached)
		return
	if _baker != null and _baker_key == key:
		if host != null and host not in _baker_hosts:
			_baker_hosts.append(host)
		return
	for job in _jobs:
		if str(job.get("key", "")) != key:
			continue
		var hosts: Array = job.get("hosts", [])
		if host != null and host not in hosts:
			hosts.append(host)
			job["hosts"] = hosts
		return
	var hosts: Array = []
	if host != null:
		hosts.append(host)
	_jobs.append({
		"texture": texture,
		"region": region,
		"kind": kind,
		"key": key,
		"hosts": hosts,
	})


static func _begin_job(job: Dictionary) -> bool:
	var texture: Texture2D = job.get("texture") as Texture2D
	var region: Rect2 = job.get("region", Rect2())
	var kind := str(job.get("kind", "auto"))
	var key := str(job.get("key", ""))
	var hosts: Array = job.get("hosts", [])
	if _masks.has(key):
		var cached = _masks[key]
		if cached is Image:
			for host in hosts:
				if is_instance_valid(host):
					host._apply_plate_image(cached)
		return false
	var started := Time.get_ticks_usec()
	var full := _decoded_image(texture)
	last_decode_usec = Time.get_ticks_usec() - started
	if full == null:
		_masks[key] = false
		return false
	var rect := Rect2i(int(region.position.x), int(region.position.y), int(region.size.x), int(region.size.y))
	if rect.size.x < 4 or rect.size.y < 4 or rect.position.x < 0 or rect.position.y < 0 or rect.end.x > full.get_width() or rect.end.y > full.get_height():
		_masks[key] = false
		return false
	var crop := full.get_region(rect)
	if crop.get_format() != Image.FORMAT_RGBA8:
		crop.convert(Image.FORMAT_RGBA8)
	var baker := PlateBaker.new()
	baker.setup(crop.get_data(), crop.get_width(), crop.get_height(), kind)
	_baker = baker
	_baker_key = key
	_baker_hosts = hosts
	work_serial += 1
	print("[plate] start decode=%d us pixels=%d key=%s" % [last_decode_usec, crop.get_width() * crop.get_height(), key])
	return true


static func _finish_baker() -> void:
	var image: Image = _baker.result() if _baker != null else null
	var key := _baker_key
	var hosts := _baker_hosts
	_baker = null
	_baker_key = ""
	_baker_hosts = []
	_masks[key] = image if image != null else false
	print("[plate] ready key=%s image=%s %s" % [key, str(image != null), cache_label()])
	if image == null:
		return
	for host in hosts:
		if is_instance_valid(host):
			host._apply_plate_image(image)


static func _decoded_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var path := texture.resource_path
	if path.is_empty():
		path = "id:%d" % texture.get_instance_id()
	if _decoded.has(path):
		return _decoded[path]
	var src := texture.get_image()
	if src == null:
		return null
	if src.is_compressed():
		src.decompress()
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	_decoded[path] = src
	return src


static func _silhouette(texture: Texture2D, region: Rect2, kind: String) -> Image:
	var key := _mask_key(texture, region, kind)
	if _masks.has(key):
		var cached = _masks[key]
		return cached if cached is Image else null
	var src := texture.get_image()
	if src == null:
		return null
	if src.is_compressed():
		src.decompress()
	main_thread_pixels += maxi(1, int(region.size.x) * int(region.size.y))
	var picked := kind
	if picked == "auto":
		picked = _best_kind(src, region)
	var image: Image = null
	if picked == "":
		image = _cut_from_background(src, region)
	else:
		image = _cut_face(src, region, picked)
	if image != null:
		_masks[key] = image
	return image


static func _best_kind(src: Image, region: Rect2) -> String:
	var best := ""
	var best_score := 0.0
	for kind in ["wood", "stone", "blue", "gold", "green", "red"]:
		var image := _cut_face(src, region, kind)
		if image == null:
			continue
		var opaque := 0
		var w := image.get_width()
		var h := image.get_height()
		for y in range(0, h, 2):
			for x in range(0, w, 2):
				if image.get_pixel(x, y).a > 0.5:
					opaque += 1
		var coverage := float(opaque * 4) / float(maxi(1, w * h))
		var score := 1.0 - absf(coverage - 0.62)
		if score > best_score:
			best_score = score
			best = kind
	return best


static func _cut_face(src: Image, region: Rect2, kind: String) -> Image:
	var x0 := int(region.position.x)
	var y0 := int(region.position.y)
	var w := int(region.size.x)
	var h := int(region.size.y)
	if w < 4 or h < 4 or x0 < 0 or y0 < 0:
		return null
	if x0 + w > src.get_width() or y0 + h > src.get_height():
		return null
	# The nearest colored pixel is often inside a letter. Keep the largest
	# connected face so the highlight follows the button, not a speck of text.
	var face := PackedByteArray()
	face.resize(w * h)
	var any_face := false
	for y in h:
		var row := y * w
		for x in w:
			if _is_face(src.get_pixel(x0 + x, y0 + y), kind):
				face[row + x] = 1
				any_face = true
	if not any_face:
		return null
	var seen := PackedByteArray()
	seen.resize(w * h)
	var mask := PackedByteArray()
	mask.resize(w * h)
	var best_count := 0
	var best_pixels := PackedInt32Array()
	for y in h:
		var row := y * w
		for x in w:
			var start := row + x
			if face[start] == 0 or seen[start] != 0:
				continue
			var stack := PackedInt32Array()
			var comp := PackedInt32Array()
			stack.append(start)
			seen[start] = 1
			var head := 0
			while head < stack.size():
				var i := stack[head]
				head += 1
				comp.append(i)
				var py := int(i / w)
				var neighbors := [i + 1, i - 1, i + w, i - w]
				for n in neighbors.size():
					var ni: int = neighbors[n]
					if ni < 0 or ni >= w * h or seen[ni] != 0 or face[ni] == 0:
						continue
					if n < 2 and int(ni / w) != py:
						continue
					seen[ni] = 1
					stack.append(ni)
			if comp.size() > best_count:
				best_count = comp.size()
				best_pixels = comp
	if best_count < 8:
		return null
	for i in best_pixels:
		mask[i] = 1
	var outside := PackedByteArray()
	outside.resize(w * h)
	var edge := PackedInt32Array()
	for x in w:
		edge.append(x)
		edge.append((h - 1) * w + x)
	for y in h:
		edge.append(y * w)
		edge.append(y * w + w - 1)
	var ehead := 0
	while ehead < edge.size():
		var i := edge[ehead]
		ehead += 1
		if i < 0 or i >= w * h or outside[i] != 0 or mask[i] != 0:
			continue
		var oy := int(i / w)
		var ox := i - oy * w
		# Letter faces are bright and can touch the crop edge. They are paint,
		# not the scenery around the button.
		if _is_ink(src.get_pixel(x0 + ox, y0 + oy)):
			continue
		outside[i] = 1
		var py := int(i / w)
		var neighbors := [i + 1, i - 1, i + w, i - w]
		for n in neighbors.size():
			var ni: int = neighbors[n]
			if ni < 0 or ni >= w * h:
				continue
			if n < 2 and int(ni / w) != py:
				continue
			edge.append(ni)
	var filled := 0
	for i in mask.size():
		if mask[i] == 0 and outside[i] == 0:
			mask[i] = 1
		if mask[i] == 1:
			filled += 1
	for _step in 3:
		var grow := PackedInt32Array()
		for y in h:
			for x in w:
				var i := y * w + x
				if mask[i] != 0:
					continue
				var touches := false
				if x > 0 and mask[i - 1] == 1:
					touches = true
				elif x + 1 < w and mask[i + 1] == 1:
					touches = true
				elif y > 0 and mask[i - w] == 1:
					touches = true
				elif y + 1 < h and mask[i + w] == 1:
					touches = true
				if not touches:
					continue
				var px := src.get_pixel(x0 + x, y0 + y)
				if px.r < 0.18 and px.g < 0.18 and px.b < 0.18:
					grow.append(i)
		for i in grow:
			mask[i] = 1
			filled += 1
	var coverage := float(filled) / float(w * h)
	if coverage < 0.2 or coverage > 0.96:
		return null
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				var px := src.get_pixel(x0 + x, y0 + y)
				image.set_pixel(x, y, Color(px.r, px.g, px.b, 1.0))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return image


# Illustrated buttons (the missions banner) are many colors. Remove only the
# ocean that touches the crop edge, and keep every pixel the water cannot reach.
static func _cut_from_background(src: Image, region: Rect2) -> Image:
	var x0 := int(region.position.x)
	var y0 := int(region.position.y)
	var w := int(region.size.x)
	var h := int(region.size.y)
	if w < 4 or h < 4 or x0 < 0 or y0 < 0:
		return null
	if x0 + w > src.get_width() or y0 + h > src.get_height():
		return null
	var water := PackedByteArray()
	water.resize(w * h)
	var edge := PackedInt32Array()
	for x in w:
		edge.append(x)
		edge.append((h - 1) * w + x)
	for y in h:
		edge.append(y * w)
		edge.append(y * w + w - 1)
	var head := 0
	while head < edge.size():
		var i := edge[head]
		head += 1
		if i < 0 or i >= w * h or water[i] != 0:
			continue
		var py := int(i / w)
		var px := i - py * w
		if not _is_water(src.get_pixel(x0 + px, y0 + py)):
			continue
		water[i] = 1
		var neighbors := [i + 1, i - 1, i + w, i - w]
		for n in neighbors.size():
			var ni: int = neighbors[n]
			if ni < 0 or ni >= w * h or water[ni] != 0:
				continue
			if n < 2 and int(ni / w) != py:
				continue
			edge.append(ni)
	var kept := 0
	for i in water.size():
		if water[i] == 0:
			kept += 1
	var coverage := float(kept) / float(w * h)
	if coverage < 0.35 or coverage > 0.96:
		return null
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			if water[y * w + x] == 0:
				var px := src.get_pixel(x0 + x, y0 + y)
				image.set_pixel(x, y, Color(px.r, px.g, px.b, 1.0))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return image


static func _is_ink(px: Color) -> bool:
	return px.r + px.g + px.b > 2.15


static func _is_water(px: Color) -> bool:
	var r := px.r
	var g := px.g
	var b := px.b
	if r > 0.55:
		return false
	if g > 0.85 and r > 0.35:
		return false
	return b > 0.25 and g > 0.18 and b + g > r + 0.28 and r < 0.5


static func _is_face(px: Color, kind: String) -> bool:
	var r := px.r
	var g := px.g
	var b := px.b
	if kind == "wood":
		return r > 0.58 and r > b + 0.12 and g > 0.28 and g < 0.9 and b < 0.62
	if kind == "stone":
		return b > 0.45 and b > r + 0.16 and r < 0.45 and g > 0.25 and g < 0.78 and b < 0.92
	if kind == "blue":
		return r < 0.62 and b > 0.45 and b > r + 0.18 and g > 0.18 and g < 0.98
	if kind == "gold":
		return r > 0.72 and g > 0.4 and g < 0.95 and b < 0.45 and r > b + 0.35
	if kind == "green":
		return g > 0.45 and g > r + 0.08 and g > b and r < 0.75
	if kind == "red":
		return r > 0.55 and r > g + 0.12 and r > b and g < 0.55
	return false


func _fit_pivot() -> void:
	if _button == null or not is_instance_valid(_button):
		return
	_place_plate()
	var art := _scaled_art()
	if art is Control:
		var ctrl := art as Control
		if ctrl.size.x > 1.0 and ctrl.size.y > 1.0:
			ctrl.pivot_offset = ctrl.size * 0.5


func _scaled_art() -> CanvasItem:
	if _visual != null and is_instance_valid(_visual):
		return _visual
	if _plate == null and _draws_itself(_button):
		return _button
	return null


func _place_plate() -> void:
	if _plate == null or _button == null:
		return
	var size := _button.size
	_plate.position = Vector2(_plate_anchor.position.x * size.x, _plate_anchor.position.y * size.y)
	_plate.size = Vector2(_plate_anchor.size.x * size.x, _plate_anchor.size.y * size.y)
	_plate.pivot_offset = _plate.size * 0.5


func _on_enter() -> void:
	if _blocked() or not _shown_in_tree():
		return
	if _touching():
		return
	_inside = true
	if _button.button_pressed or _pressed:
		_pressed = true
		_hover = false
	else:
		_hover = true
	_apply(false)


func _on_exit() -> void:
	# Scaling a child can emit a stray exit while the pointer is still inside.
	if _button != null and _button.is_hovered() and not _touching():
		_inside = true
		_hover = not _pressed
		_apply(false)
		return
	_inside = false
	_hover = false
	if _touch_hold or _touching():
		_apply(false)
		return
	_pressed = false
	_apply(false)


func _on_down() -> void:
	if _blocked() or not _shown_in_tree():
		return
	_armed = true
	_pressed = true
	_hover = false
	_apply(false)


func _on_up() -> void:
	_pressed = false
	if _touching() or _touch_hold:
		_hover = false
		_inside = false
		_touch_hold = false
	elif _engine_hover() or _inside:
		_hover = true
		_inside = true
	_apply(false)
	_clear_arm.call_deferred()


func _on_action() -> void:
	# Touch code emits pressed itself and never delivers button_down.
	if _armed:
		_armed = false
		return
	if _blocked() or not _shown_in_tree():
		return
	_pressed = true
	_hover = false
	_touch_hold = true
	_safety = 0.45
	_apply(false)
	if _host and is_instance_valid(_host) and _host.has_method("hold"):
		_host.hold(self)


func _clear_arm() -> void:
	_armed = false


func _on_visibility() -> void:
	_sync_visibility()


func _on_exit_tree() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if _host and is_instance_valid(_host) and _host.has_method("drop"):
		_host.drop(self)


func _blocked() -> bool:
	return _button == null or _button.disabled or not _button.visible


func _touching() -> bool:
	return _host != null and is_instance_valid(_host) and bool(_host.get("using_touch"))


func _shown_in_tree() -> bool:
	return _button != null and _button.visible and _button.is_visible_in_tree()


func _engine_hover() -> bool:
	return _button != null and is_instance_valid(_button) and _button.is_hovered() and _shown_in_tree() and not _button.disabled


func _sync_visibility() -> void:
	if _button == null or not is_instance_valid(_button):
		return
	if not _shown_in_tree() or _button.disabled:
		_hover = false
		_inside = false
		_pressed = false
		_touch_hold = false
		_apply(true)
		return
	if _touching() or _touch_hold:
		return
	if _button.button_pressed:
		_pressed = true
		_hover = false
		_apply(false)
	elif _engine_hover():
		_hover = true
		_pressed = false
		_apply(false)


func _process(delta: float) -> void:
	service_plates()
	if _button == null or not is_instance_valid(_button):
		set_process(false)
		return
	if not _shown_in_tree() or _button.disabled:
		_saw_engine_hover = false
		_saw_engine_press = false
		if _hover or _pressed or _touch_hold:
			_hover = false
			_inside = false
			_pressed = false
			_touch_hold = false
			_apply(true)
		return
	if _touch_hold:
		_safety -= delta
		if _safety <= 0.0:
			release_touch()
			if _host and is_instance_valid(_host) and _host.has_method("drop"):
				_host.drop(self)
		return
	if _touching():
		_saw_engine_hover = false
		_saw_engine_press = false
		if _hover:
			_hover = false
			_apply(false)
		return
	# Follow the engine when it has actually reported hover or a press.
	# Signal-only tests never set those flags, so a missed signal cannot
	# wipe a highlight that the pointer is still holding.
	if _button.button_pressed:
		_saw_engine_press = true
		if not _pressed or _hover:
			_pressed = true
			_hover = false
			_apply(false)
		return
	if _saw_engine_press:
		_saw_engine_press = false
		_pressed = false
		_hover = _engine_hover() or _inside
		_inside = _hover
		_apply(false)
		return
	if _engine_hover():
		_saw_engine_hover = true
		_inside = true
		if _pressed or not _hover:
			_pressed = false
			_hover = true
			_apply(false)
	elif _saw_engine_hover:
		_saw_engine_hover = false
		_inside = false
		if _hover or _pressed:
			_hover = false
			_pressed = false
			_apply(false)


func _apply(instant: bool) -> void:
	if _button == null or not is_instance_valid(_button):
		return
	var pressing := _pressed and not _button.disabled and _button.visible
	var hovering := _hover and not pressing and not _button.disabled and _button.visible
	var mode := 2 if pressing else 1 if hovering else 0
	# The hitbox never scales. Only a child icon or the painted plate does.
	var scale_mul := 1.0
	var art := _scaled_art()
	if art != null and art != _button and _plate == null:
		scale_mul = PRESS_SCALE if pressing else HOVER_SCALE if hovering else 1.0
	_button.scale = _button_scale
	if art == null or art == _button:
		goal_scale = _button_scale
	else:
		goal_scale = _art_scale * scale_mul
	var tint := _art_modulate
	if art != null and art != _button and (pressing or hovering):
		var mul := PRESS_TINT if pressing else HOVER_TINT
		tint = Color(
			_art_modulate.r * mul.r,
			_art_modulate.g * mul.g,
			_art_modulate.b * mul.b,
			_art_modulate.a
		)
	elif art == _button and (pressing or hovering):
		var mul := PRESS_TINT if pressing else HOVER_TINT
		tint = Color(
			_art_modulate.r * mul.r,
			_art_modulate.g * mul.g,
			_art_modulate.b * mul.b,
			_art_modulate.a
		)
	var plate_color := PLATE_REST
	var plate_scale := Vector2.ONE
	if pressing:
		plate_color = PLATE_PRESS
		plate_scale = Vector2(PRESS_SCALE, PRESS_SCALE)
	elif hovering:
		plate_color = PLATE_HOVER
	var animate := (art != null and art != _button) or art == _button or _plate != null
	if not animate:
		return
	if mode == _mode and not instant:
		return
	_mode = mode
	var seconds := PRESS_SEC if pressing else HOVER_SEC
	if _tween and _tween.is_valid():
		_tween.kill()
	if instant or seconds <= 0.0:
		if art != null and art != _button:
			art.scale = goal_scale
		if art != null:
			art.modulate = tint
		if _plate:
			_plate.modulate = plate_color
			_plate.scale = plate_scale
		return
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_parallel(true)
	if art != null and art != _button:
		_tween.tween_property(art, "scale", goal_scale, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if art != null:
		_tween.tween_property(art, "modulate", tint, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _plate:
		_tween.tween_property(_plate, "modulate", plate_color, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_plate, "scale", plate_scale, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# Spreads the coin-ad silhouette across frames. The crop is already RGBA8 bytes,
# so a death frame never calls get_pixel on the full overlay.
class PlateBaker:
	extends RefCounted

	var data := PackedByteArray()
	var w := 0
	var h := 0
	var auto := false
	var kind_list: Array[String] = []
	var kind_i := 0
	var phase := "face"
	var face := PackedByteArray()
	var seen := PackedByteArray()
	var mask := PackedByteArray()
	var outside := PackedByteArray()
	var stack := PackedInt32Array()
	var comp := PackedInt32Array()
	var best_pixels := PackedInt32Array()
	var edge := PackedInt32Array()
	var grow := PackedInt32Array()
	var best_count := 0
	var head := 0
	var scan := 0
	var cursor := 0
	var grow_step := 0
	var filled := 0
	var any_face := false
	var image: Image
	var best_image: Image
	var best_score := -1.0
	var opaque := 0
	var score_x := 0
	var score_y := 0
	var finished := false
	var pumped := 0

	func setup(bytes: PackedByteArray, width: int, height: int, plate_kind: String) -> void:
		data = bytes
		w = width
		h = height
		auto = plate_kind == "auto"
		kind_list.clear()
		if auto:
			kind_list.append("wood")
			kind_list.append("stone")
			kind_list.append("blue")
			kind_list.append("gold")
			kind_list.append("green")
			kind_list.append("red")
		else:
			kind_list.append(plate_kind)
		kind_i = 0
		_begin_kind()

	func pump(budget: int) -> bool:
		var left := budget
		while left > 0 and not finished:
			var before := left
			left = _pump_once(left)
			if left == before:
				break
		return finished

	func result() -> Image:
		return best_image

	func _begin_kind() -> void:
		if kind_i >= kind_list.size():
			if auto and best_image == null and phase != "bg_water":
				phase = "bg_water"
				_reset_buffers(false)
				return
			finished = true
			return
		phase = "face"
		_reset_buffers(true)

	func _reset_buffers(with_face: bool) -> void:
		var n := w * h
		if with_face:
			face = PackedByteArray()
			face.resize(n)
		seen = PackedByteArray()
		seen.resize(n)
		mask = PackedByteArray()
		mask.resize(n)
		outside = PackedByteArray()
		outside.resize(n)
		stack = PackedInt32Array()
		comp = PackedInt32Array()
		best_pixels = PackedInt32Array()
		edge = PackedInt32Array()
		grow = PackedInt32Array()
		best_count = 0
		head = 0
		scan = 0
		cursor = 0
		grow_step = 0
		filled = 0
		any_face = false
		image = null
		opaque = 0
		score_x = 0
		score_y = 0

	func _pump_once(left: int) -> int:
		match phase:
			"face":
				return _pump_face(left)
			"components":
				return _pump_components(left)
			"mask":
				return _pump_mask(left)
			"outside":
				return _pump_outside(left)
			"holes":
				return _pump_holes(left)
			"grow":
				return _pump_grow(left)
			"grow_apply":
				return _pump_grow_apply(left)
			"paint":
				return _pump_paint(left)
			"score":
				return _pump_score(left)
			"bg_water":
				return _pump_background(left)
			"bg_paint":
				return _pump_background_paint(left)
			_:
				finished = true
				return 0
		return left

	func _color_at(index: int) -> Color:
		var o := index * 4
		return Color(data[o] / 255.0, data[o + 1] / 255.0, data[o + 2] / 255.0, data[o + 3] / 255.0)

	func _is_ink(px: Color) -> bool:
		return px.r + px.g + px.b > 2.15

	func _is_water(px: Color) -> bool:
		var r := px.r
		var g := px.g
		var b := px.b
		if r > 0.55:
			return false
		if g > 0.85 and r > 0.35:
			return false
		return b > 0.25 and g > 0.18 and b + g > r + 0.28 and r < 0.5

	func _is_face(px: Color, kind: String) -> bool:
		var r := px.r
		var g := px.g
		var b := px.b
		if kind == "wood":
			return r > 0.58 and r > b + 0.12 and g > 0.28 and g < 0.9 and b < 0.62
		if kind == "stone":
			return b > 0.45 and b > r + 0.16 and r < 0.45 and g > 0.25 and g < 0.78 and b < 0.92
		if kind == "blue":
			return r < 0.62 and b > 0.45 and b > r + 0.18 and g > 0.18 and g < 0.98
		if kind == "gold":
			return r > 0.72 and g > 0.4 and g < 0.95 and b < 0.45 and r > b + 0.35
		if kind == "green":
			return g > 0.45 and g > r + 0.08 and g > b and r < 0.75
		if kind == "red":
			return r > 0.55 and r > g + 0.12 and r > b and g < 0.55
		return false

	func _pump_face(left: int) -> int:
		var n := w * h
		var current := kind_list[kind_i]
		while left > 0 and scan < n:
			if _is_face(_color_at(scan), current):
				face[scan] = 1
				any_face = true
			scan += 1
			left -= 1
			pumped += 1
		if scan >= n:
			if not any_face:
				_advance_kind()
			else:
				phase = "components"
				scan = 0
				head = 0
		return left

	func _pump_components(left: int) -> int:
		var n := w * h
		while left > 0:
			if head < stack.size():
				var i := stack[head]
				head += 1
				comp.append(i)
				var py := int(i / w)
				var neighbors := [i + 1, i - 1, i + w, i - w]
				for n_i in neighbors.size():
					var ni: int = neighbors[n_i]
					if ni < 0 or ni >= n or seen[ni] != 0 or face[ni] == 0:
						continue
					if n_i < 2 and int(ni / w) != py:
						continue
					seen[ni] = 1
					stack.append(ni)
				left -= 1
				pumped += 1
				continue
			if comp.size() > 0:
				if comp.size() > best_count:
					best_count = comp.size()
					best_pixels = comp.duplicate()
				comp = PackedInt32Array()
				stack = PackedInt32Array()
				head = 0
			if scan >= n:
				phase = "mask"
				cursor = 0
				return left
			var start := scan
			scan += 1
			left -= 1
			pumped += 1
			if face[start] == 0 or seen[start] != 0:
				continue
			stack.append(start)
			seen[start] = 1
			head = 0
		return left

	func _pump_mask(left: int) -> int:
		if best_count < 8:
			_advance_kind()
			return left - 1 if left > 0 else 0
		while left > 0 and cursor < best_pixels.size():
			mask[best_pixels[cursor]] = 1
			cursor += 1
			left -= 1
			pumped += 1
		if cursor < best_pixels.size():
			return left
		edge = PackedInt32Array()
		for x in w:
			edge.append(x)
			edge.append((h - 1) * w + x)
		for y in h:
			edge.append(y * w)
			edge.append(y * w + w - 1)
		head = 0
		phase = "outside"
		return left

	func _pump_outside(left: int) -> int:
		var n := w * h
		while left > 0 and head < edge.size():
			var i := edge[head]
			head += 1
			left -= 1
			pumped += 1
			if i < 0 or i >= n or outside[i] != 0 or mask[i] != 0:
				continue
			if _is_ink(_color_at(i)):
				continue
			outside[i] = 1
			var py := int(i / w)
			var neighbors := [i + 1, i - 1, i + w, i - w]
			for n_i in neighbors.size():
				var ni: int = neighbors[n_i]
				if ni < 0 or ni >= n:
					continue
				if n_i < 2 and int(ni / w) != py:
					continue
				edge.append(ni)
		if head >= edge.size():
			phase = "holes"
			cursor = 0
			filled = 0
		return left

	func _pump_holes(left: int) -> int:
		var n := mask.size()
		while left > 0 and cursor < n:
			if mask[cursor] == 0 and outside[cursor] == 0:
				mask[cursor] = 1
			if mask[cursor] == 1:
				filled += 1
			cursor += 1
			left -= 1
			pumped += 1
		if cursor >= n:
			grow_step = 0
			phase = "grow"
			cursor = 0
			grow = PackedInt32Array()
		return left

	func _pump_grow(left: int) -> int:
		var n := w * h
		while left > 0 and cursor < n:
			var i := cursor
			cursor += 1
			left -= 1
			pumped += 1
			if mask[i] != 0:
				continue
			var x := i % w
			var y := int(i / w)
			var touches := false
			if x > 0 and mask[i - 1] == 1:
				touches = true
			elif x + 1 < w and mask[i + 1] == 1:
				touches = true
			elif y > 0 and mask[i - w] == 1:
				touches = true
			elif y + 1 < h and mask[i + w] == 1:
				touches = true
			if not touches:
				continue
			var px := _color_at(i)
			if px.r < 0.18 and px.g < 0.18 and px.b < 0.18:
				grow.append(i)
		if cursor < n:
			return left
		phase = "grow_apply"
		cursor = 0
		return left

	func _pump_grow_apply(left: int) -> int:
		while left > 0 and cursor < grow.size():
			mask[grow[cursor]] = 1
			filled += 1
			cursor += 1
			left -= 1
			pumped += 1
		if cursor < grow.size():
			return left
		grow_step += 1
		if grow_step < 3:
			phase = "grow"
			cursor = 0
			grow = PackedInt32Array()
			return left
		var coverage := float(filled) / float(maxi(1, w * h))
		if coverage < 0.2 or coverage > 0.96:
			_advance_kind()
			return left
		image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		phase = "paint"
		cursor = 0
		return left

	func _pump_paint(left: int) -> int:
		var n := w * h
		while left > 0 and cursor < n:
			var x := cursor % w
			var y := int(cursor / w)
			if mask[cursor] == 1:
				var px := _color_at(cursor)
				image.set_pixel(x, y, Color(px.r, px.g, px.b, 1.0))
			cursor += 1
			left -= 1
			pumped += 1
		if cursor < n:
			return left
		if auto:
			phase = "score"
			score_y = 0
			opaque = 0
		else:
			best_image = image
			finished = true
		return left

	func _pump_score(left: int) -> int:
		while left > 0 and score_y < h:
			while score_x < w and left > 0:
				if image.get_pixel(score_x, score_y).a > 0.5:
					opaque += 1
				score_x += 2
				left -= 1
				pumped += 1
			if score_x < w:
				return left
			score_x = 0
			score_y += 2
		if score_y < h:
			return left
		var coverage := float(opaque * 4) / float(maxi(1, w * h))
		var score := 1.0 - absf(coverage - 0.62)
		if score > best_score:
			best_score = score
			best_image = image
		_advance_kind()
		return left

	func _pump_background(left: int) -> int:
		var n := w * h
		if edge.is_empty() and head == 0 and scan == 0:
			for x in w:
				edge.append(x)
				edge.append((h - 1) * w + x)
			for y in h:
				edge.append(y * w)
				edge.append(y * w + w - 1)
		while left > 0 and head < edge.size():
			var i := edge[head]
			head += 1
			left -= 1
			pumped += 1
			if i < 0 or i >= n or outside[i] != 0:
				continue
			var py := int(i / w)
			if not _is_water(_color_at(i)):
				continue
			outside[i] = 1
			var neighbors := [i + 1, i - 1, i + w, i - w]
			for n_i in neighbors.size():
				var ni: int = neighbors[n_i]
				if ni < 0 or ni >= n or outside[ni] != 0:
					continue
				if n_i < 2 and int(ni / w) != py:
					continue
				edge.append(ni)
		if head < edge.size():
			return left
		var kept := 0
		for i in n:
			if outside[i] == 0:
				kept += 1
		var coverage := float(kept) / float(maxi(1, n))
		if coverage < 0.35 or coverage > 0.96:
			finished = true
			return left
		filled = kept
		image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		mask = outside
		phase = "bg_paint"
		cursor = 0
		return left

	func _pump_background_paint(left: int) -> int:
		var n := w * h
		while left > 0 and cursor < n:
			if mask[cursor] == 0:
				var px := _color_at(cursor)
				image.set_pixel(cursor % w, int(cursor / w), Color(px.r, px.g, px.b, 1.0))
			cursor += 1
			left -= 1
			pumped += 1
		if cursor >= n:
			best_image = image
			finished = true
		return left

	func _advance_kind() -> void:
		kind_i += 1
		_begin_kind()
