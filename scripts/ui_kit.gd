class_name UIKit
extends Object


static func font(size: int, color: Color, outline := true) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	if outline:
		settings.outline_size = maxi(2, int(round(size / 12.0)))
		settings.outline_color = Color(0.01, 0.05, 0.08, 0.9)
		settings.shadow_size = 2
		settings.shadow_color = Color(0, 0, 0, 0.35)
		settings.shadow_offset = Vector2(0, 2)
	return settings


static func make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.label_settings = font(size, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func make_icon_button(texture: Texture2D, pressed: Callable, scale := 0.72) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = texture
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var size := Vector2(72, 72)
	if texture:
		size = texture.get_size() * scale
	button.custom_minimum_size = size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(pressed)
	return button
