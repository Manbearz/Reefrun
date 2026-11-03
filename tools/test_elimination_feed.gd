extends SceneTree

## Elimination names are 21px, 150% of the original 14px. The rest of the feed stays 14px.

func _initialize() -> void:
	root.add_child(Runner.new())


class Runner extends Node:
	func _ready() -> void:
		var fail := await _checks()
		if fail != "":
			push_error("[feed] " + fail)
		print("[feed] %s" % ("ok" if fail == "" else "failed"))
		get_tree().quit(0 if fail == "" else 1)

	func _checks() -> String:
		var hud: Node = load("res://scenes/game/hud.gd").new()
		add_child(hud)
		hud.set_process(true)
		await get_tree().process_frame
		if absf(float(hud.score_text.get("_glyph_h")) - 40.0) > 0.05:
			return "score size changed"
		if absf(float(hud.swimming_text.get("_glyph_h")) - 12.0) > 0.05:
			return "swimming label size changed"
		var short := _measure(hud, "A")
		if short != "":
			return short
		var wide := ""
		var widest := 0.0
		var alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
		for i in alphabet.length():
			var ch := alphabet.substr(i, 1)
			var width: float = hud.feed_name.layout_width(ch.repeat(7), hud.FEED_NAME_GLYPH)
			if width > widest:
				widest = width
				wide = ch
		var long := _measure(hud, wide.repeat(7))
		if long != "":
			return long
		hud.show_elimination("AL")
		hud.show_elimination("REEFRUN")
		if str(hud.feed_name.get("_text")) != "REEFRUN":
			return "second elimination left %s" % hud.feed_name.get("_text")
		if _glyph_count(hud.feed_name) != 7:
			return "stacked elimination glyphs"
		var gap := _gap(hud)
		if gap < -0.5:
			return "consecutive name overlapped the message"
		hud.show_feed("Harpoons incoming")
		if hud.feed_name.visible:
			return "other feed messages enlarged the name"
		if absf(_max_glyph(hud.feed_text) - hud.FEED_GLYPH) > 0.4:
			return "other feed message changed size"
		hud.show_elimination("PIP")
		if absf(hud.feed_row.modulate.a - 1.0) > 0.01:
			return "feed did not appear"
		var timing := await _fade_window(hud)
		if timing != "":
			return timing
		for height in [960.0, 1080.0, 1170.0, 1260.0]:
			var resized := await _set_portrait(height)
			if resized != "":
				return resized
			hud.apply_screen_layout()
			var fit := _measure(hud, wide.repeat(7))
			if fit != "":
				return "portrait %s %s" % [height, fit]
			var bottom := float(hud.feed_row.position.y + hud.feed_row.size.y)
			print("[feed] h=%.0f y=%.1f bottom=%.1f name=%.1f" % [height, hud.feed_row.position.y, bottom, _max_glyph(hud.feed_name)])
			if bottom > RR.screen_bottom() + 0.5 or hud.feed_row.position.y < RR.screen_bottom() - 120.0:
				return "portrait %s feed left its bottom slot" % height
		return ""

	func _measure(hud: Node, name: String) -> String:
		hud.show_elimination(name)
		var name_h := _max_glyph(hud.feed_name)
		var rest_h := _max_glyph(hud.feed_text)
		var gap := _gap(hud)
		var right := float(hud.feed_row.position.x + hud.feed_text.position.x) + _right(hud.feed_text)
		print("[feed] name=%s glyphs=%.1f/%.1f gap=%.1f right=%.1f" % [name, name_h, rest_h, gap, right])
		if absf(name_h - hud.FEED_NAME_GLYPH) > 0.4:
			return "name %s height %.2f" % [name, name_h]
		if absf(rest_h - hud.FEED_GLYPH) > 0.4:
			return "wiped-out height %.2f" % rest_h
		if absf(name_h / rest_h - 1.5) > 0.04:
			return "name %s is not 150 percent of the original" % name
		if gap < -0.5:
			return "name %s overlaps wiped out" % name
		if right > RR.VIEW_W - 4.0 or hud.feed_row.position.x < 0.0:
			return "name %s leaves the screen" % name
		var name_mid := _mid_y(hud.feed_name)
		var rest_mid := _mid_y(hud.feed_text)
		if absf(name_mid - rest_mid) > 1.0:
			return "name %s is not aligned with the message" % name
		return ""

	func _gap(hud: Node) -> float:
		return hud.feed_text.position.x + _left(hud.feed_text) - _right(hud.feed_name)

	func _left(node: Control) -> float:
		var left := node.size.x
		for child in node.get_children():
			left = minf(left, child.position.x)
		return left

	func _right(node: Control) -> float:
		var right := 0.0
		for child in node.get_children():
			right = maxf(right, child.position.x + child.size.x)
		return right

	func _mid_y(node: Control) -> float:
		var top := node.size.y
		var bottom := 0.0
		for child in node.get_children():
			top = minf(top, child.position.y)
			bottom = maxf(bottom, child.position.y + child.size.y)
		return node.position.y + (top + bottom) * 0.5

	func _max_glyph(node: Control) -> float:
		var h := 0.0
		for child in node.get_children():
			h = maxf(h, child.size.y)
		return h

	func _glyph_count(node: Control) -> int:
		return node.get_child_count()

	func _fade_window(hud: Node) -> String:
		var elapsed := 0.0
		var hold := -1.0
		var gone := -1.0
		for _frame in 240:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
			var alpha := float(hud.feed_row.modulate.a)
			if hold < 0.0 and alpha < 0.98:
				hold = elapsed
			if alpha < 0.05:
				gone = elapsed
				break
		print("[feed] hold=%.2f gone=%.2f" % [hold, gone])
		if hold < 0.75 or hold > 1.05:
			return "hold was %.2f seconds" % hold
		if gone < 0.0 or gone - hold < 0.35 or gone - hold > 0.7:
			return "fade lasted %.2f seconds" % (gone - hold)
		return ""

	func _set_portrait(height: float) -> String:
		var win := get_tree().root
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
		win.content_scale_size = Vector2i(int(RR.VIEW_W), int(RR.VIEW_H))
		win.size = Vector2i(int(RR.VIEW_W), int(height))
		await get_tree().process_frame
		if absf(RR.screen_bottom() - height) > 1.0:
			return "portrait %s screen %s" % [height, RR.screen_bottom()]
		return ""
