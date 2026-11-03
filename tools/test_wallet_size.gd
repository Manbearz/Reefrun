extends SceneTree

## Main-menu coin balance is larger. Cosmetic prices and icons stay the same size.

func _initialize() -> void:
	root.add_child(Runner.new())


class Runner extends Node:
	const SAVE_PATH := "user://reefrun.cfg"

	func _ready() -> void:
		var snap := _snapshot()
		var fail := await _checks()
		if fail != "":
			push_error("[wallet] " + fail)
		_restore(snap)
		var session := get_node("/root/GameSession")
		var code := 0 if fail == "" else 1
		if int(session.coins) != int(snap["coins"]):
			push_error("[wallet] coins were not restored")
			code = 1
		else:
			print("[wallet] restored coins %s" % session.coins)
		print("[wallet] %s" % ("ok" if code == 0 else "failed"))
		get_tree().quit(code)

	func _checks() -> String:
		var session := get_node("/root/GameSession")
		var menu: Node = load("res://scenes/menu/main_menu.tscn").instantiate()
		add_child(menu)
		menu.set_process(false)
		menu.set_process_input(false)
		await get_tree().process_frame
		var coin := menu.get("_wallet_coin") as TextureRect
		var text := menu.get("_wallet_text") as Control
		if coin == null or text == null:
			return "wallet nodes missing"
		if absf(coin.size.x - 55.296) > 0.05 or absf(coin.size.y - 55.296) > 0.05:
			return "coin size %s" % coin.size
		if absf(text.size.y - 30.8) > 0.05:
			return "balance height %s" % text.size.y
		var prices := _price_coin_size(menu)
		if absf(prices - 16.0) > 0.05:
			return "cosmetic price coin changed to %s" % prices
		var hat_icon := (menu.get("_hat_icons") as Array)[0] as Control
		var fish_icon := (menu.get("_fish_icons") as Array)[0] as Control
		if hat_icon == null or absf(hat_icon.size.y - 52.0) > 0.05:
			return "hat icon resized"
		if fish_icon == null or absf(fish_icon.size.y - 68.0) > 0.05:
			return "fish icon resized"
		if _find(menu, "PersonalBest") == null:
			return "personal best missing"
		var heights: Array[float] = [960.0, 1080.0, 1170.0, 1200.0, 1260.0]
		var amounts: Array[int] = [0, 999, 2500, 10000]
		for height in heights:
			var resized := await _set_portrait(height)
			if resized != "":
				return resized
			menu.call("_sync_menu_anchor")
			await get_tree().process_frame
			for amount in amounts:
				session.coins = amount
				menu.call("_refresh_wallet")
				var fit := _measure(menu, height, amount)
				if fit != "":
					return fit
		return ""

	func _measure(menu: Node, height: float, amount: int) -> String:
		var coin := menu.get("_wallet_coin") as Control
		var text := menu.get("_wallet_text") as Control
		var clip := menu.get("_hat_clip") as Control
		var left := text.position.x + text.size.x
		var right := text.position.x
		var glyph_top := text.position.y
		var glyph_bottom := text.position.y + text.size.y
		var glyph_h := 0.0
		var count := 0
		for child in text.get_children():
			var glyph := child as TextureRect
			if glyph == null or glyph.texture == null:
				continue
			count += 1
			var x := text.position.x + glyph.position.x
			var y := text.position.y + glyph.position.y
			left = minf(left, x)
			right = maxf(right, x + glyph.size.x)
			glyph_top = minf(glyph_top, y)
			glyph_bottom = maxf(glyph_bottom, y + glyph.size.y)
			glyph_h = maxf(glyph_h, glyph.size.y)
			if not glyph.texture.resource_path.contains("num_gold"):
				return "balance %s is not the gold digit font" % amount
		if count != str(amount).length():
			return "height %s balance %s drew %s glyphs" % [height, amount, count]
		var gap := left - (coin.position.x + coin.size.x)
		var coin_mid := coin.position.y + coin.size.y * 0.5
		var text_mid := (glyph_top + glyph_bottom) * 0.5
		var screen_bottom := RR.screen_bottom()
		print("[wallet] h=%.0f coins=%s icon=%.1f num=%.1f gap=%.1f right=%.1f off=%.1f" % [
			height, amount, coin.size.y, glyph_h, gap, right, clip.position.x,
		])
		if absf(gap - 4.0) > 0.6:
			return "height %s balance %s gap %.2f" % [height, amount, gap]
		if absf(coin_mid - text_mid) > 1.0:
			return "height %s balance %s vertical centers %.1f %.1f" % [height, amount, coin_mid, text_mid]
		if absf(glyph_h - 30.8) > 0.6:
			return "height %s number height %.2f" % [height, glyph_h]
		if coin.position.x < 0.0 or right > RR.VIEW_W - 1.0 or glyph_top < 0.0 or glyph_bottom > screen_bottom:
			return "height %s balance %s leaves the screen" % [height, amount]
		if right > clip.position.x - 2.0:
			return "height %s balance %s overlaps OFF at %.1f" % [height, amount, clip.position.x]
		return ""

	func _price_coin_size(menu: Node) -> float:
		var prices: Array = menu.get("_hat_prices")
		if prices.is_empty():
			prices = menu.get("_fish_prices")
		for wrap in prices:
			var node := wrap as Node
			if node == null:
				continue
			for child in node.get_children():
				if child is TextureRect:
					return (child as Control).size.y
		return -1.0

	func _set_portrait(height: float) -> String:
		var win := get_tree().root
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
		win.content_scale_size = Vector2i(int(RR.VIEW_W), int(RR.VIEW_H))
		win.size = Vector2i(int(RR.VIEW_W), int(height))
		await get_tree().process_frame
		var visible := win.get_visible_rect().size
		if absf(visible.y - height) > 1.0:
			return "portrait %s visible %s" % [height, visible]
		return ""

	func _find(node: Node, wanted: String) -> Node:
		if node == null:
			return null
		if str(node.name) == wanted:
			return node
		for child in node.get_children():
			var found := _find(child, wanted)
			if found:
				return found
		return null

	func _snapshot() -> Dictionary:
		var existed := FileAccess.file_exists(SAVE_PATH)
		var bytes := PackedByteArray()
		if existed:
			bytes = FileAccess.get_file_as_bytes(SAVE_PATH)
		var session := get_node("/root/GameSession")
		return {"existed": existed, "bytes": bytes, "coins": int(session.coins)}

	func _restore(snap: Dictionary) -> void:
		var session := get_node("/root/GameSession")
		session.coins = int(snap["coins"])
		if bool(snap["existed"]):
			var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
			if f:
				f.store_buffer(snap["bytes"])
				f.close()
			session._load()
		elif FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
