class_name SpriteText
extends Control

var _text := ""
var _glyph_h := 24.0
var _gold_digits := false
var _align := HORIZONTAL_ALIGNMENT_CENTER
var _kern := 0.74
var _fit_box := false


func configure(p_text: String, height: float, box: Vector2, align := HORIZONTAL_ALIGNMENT_CENTER, gold_digits := false, fit_box := false) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = fit_box
	size = box
	_glyph_h = height
	_align = align
	_gold_digits = gold_digits
	_fit_box = fit_box
	_kern = 1.12
	set_value(p_text)


func set_value(value: String) -> void:
	var next := value.to_upper()
	if _text == next and get_child_count() > 0:
		return
	_text = next
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	var glyphs: Array = []
	var max_h := 1.0
	for i in _text.length():
		var ch := _text.substr(i, 1)
		if ch == " ":
			glyphs.append(null)
			continue
		var tex := Sprites.digit(ch) if _gold_digits and ch >= "0" and ch <= "9" else Sprites.glyph(ch)
		glyphs.append(tex)
		if tex:
			max_h = maxf(max_h, float(tex.get_height()))
	var scale := _glyph_h / max_h
	if _fit_box:
		scale = minf(scale, size.y / max_h)
	var space_w := max_h * scale * 0.34
	var widths: PackedFloat32Array = PackedFloat32Array()
	var total := 0.0
	for i in glyphs.size():
		var tex: Texture2D = glyphs[i]
		var w := space_w
		if tex:
			w = float(tex.get_width()) * scale
		widths.append(w)
		if tex and i > 0 and glyphs[i - 1] != null:
			total -= w * (1.0 - _kern)
		total += w
	if _fit_box and total > size.x and total > 0.0:
		var shrink := size.x / total
		scale *= shrink
		space_w *= shrink
		total *= shrink
		for i in widths.size():
			widths[i] *= shrink
	var x := 0.0
	if _align == HORIZONTAL_ALIGNMENT_CENTER:
		x = (size.x - total) * 0.5
	elif _align == HORIZONTAL_ALIGNMENT_RIGHT:
		x = size.x - total
	for i in glyphs.size():
		var tex: Texture2D = glyphs[i]
		var w := widths[i]
		if tex == null:
			x += w
			continue
		if i > 0 and glyphs[i - 1] != null:
			x -= w * (1.0 - _kern)
		var dh := float(tex.get_height()) * scale
		var digit := TextureRect.new()
		digit.texture = tex
		digit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		digit.stretch_mode = TextureRect.STRETCH_SCALE
		digit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		digit.size = Vector2(w, dh)
		digit.position = Vector2(x, (size.y - dh) * 0.5)
		add_child(digit)
		x += w
