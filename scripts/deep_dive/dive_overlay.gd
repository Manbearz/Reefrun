class_name DiveOverlay
extends CanvasLayer

const SpriteTextScript := preload("res://scripts/sprite_text.gd")

var _banner: TextureRect
var _seconds: TextureRect
var _count: TextureRect
var _hint: SpriteText
var _survived: SpriteText


func _ready() -> void:
	layer = 24
	_banner = _picture("banner_deep_dive", 0.72)
	_seconds = _picture("banner_seconds", 0.46)
	_count = _picture("count_3", 0.34)
	_hint = SpriteTextScript.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_hint.configure("TAP LEFT OR RIGHT", 20, Vector2(RR.VIEW_W - 24, 28), HORIZONTAL_ALIGNMENT_CENTER)
	_survived = SpriteTextScript.new()
	_survived.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_survived)
	_survived.configure("SURVIVED!", 42, Vector2(RR.VIEW_W, 56), HORIZONTAL_ALIGNMENT_CENTER)
	hide_all()


func hide_all() -> void:
	if _banner:
		_banner.visible = false
	if _seconds:
		_seconds.visible = false
	if _count:
		_count.visible = false
	if _hint:
		_hint.visible = false
	if _survived:
		_survived.visible = false


func sync(events: GameplayEvents) -> void:
	if events == null:
		hide_all()
		return
	var count := events.intro_count()
	_banner.visible = false
	_seconds.visible = false
	_hint.visible = events.intro_title_visible() or count > 0
	_count.visible = count > 0
	if count > 0:
		_count.texture = DiveAssets.tex("count_%d" % count)
		_place(_count, 0.34, 168.0)
	_survived.visible = events.survived_visible()
	_layout()


func _picture(id: String, width_ratio: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = DiveAssets.tex(id)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(rect)
	rect.set_meta("width_ratio", width_ratio)
	return rect


func _layout() -> void:
	var insets := RR.display_insets(RR.screen_size())
	_place(_banner, 0.72, 168.0 + insets.y)
	_place(_seconds, 0.46, 252.0 + insets.y)
	if _hint:
		_hint.position = Vector2(12, RR.screen_bottom() - 78.0 - insets.w)
		_hint.size = Vector2(RR.VIEW_W - 24, 28)
	if _survived:
		_survived.position = Vector2(0, 168.0 + insets.y)
		_survived.size = Vector2(RR.VIEW_W, 56)


func _place(rect: TextureRect, width_ratio: float, y: float) -> void:
	if rect == null or rect.texture == null:
		return
	var tex := rect.texture
	var w := RR.VIEW_W * width_ratio
	var h := w * float(tex.get_height()) / maxf(1.0, float(tex.get_width()))
	rect.size = Vector2(w, h)
	rect.position = Vector2((RR.VIEW_W - w) * 0.5, y)
