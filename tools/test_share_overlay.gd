extends SceneTree

func _initialize() -> void:
	root.add_child(Runner.new())


class Runner extends Node:
	func _ready() -> void:
		var game: Node = load("res://scenes/game/game.tscn").instantiate()
		add_child(game)
		await get_tree().process_frame
		await get_tree().process_frame
		game.set("finished", true)
		game.set("score", 7)
		game.set("_over_rank", 12)
		game.set("_over_remaining", 11)
		game.call("_show_over", 12, 11)
		await get_tree().process_frame
		var overlay: Node = game.get("overlay")
		if overlay == null:
			push_error("[share] missing wipe out overlay")
			get_tree().quit(1)
			return
		var wipe_share: TextureButton = game.get("_wipe_share")
		var wipe_again: Button = game.get("_wipe_again")
		var wipe_menu: TextureButton = game.get("_wipe_menu")
		if wipe_share == null or wipe_again == null or wipe_menu == null:
			push_error("[share] missing wipe out buttons")
			get_tree().quit(1)
			return
		if wipe_share.position.y <= wipe_again.position.y:
			push_error("[share] small share is not below Continue")
			get_tree().quit(1)
			return
		if wipe_menu.position.y <= wipe_share.position.y:
			push_error("[share] Main Menu is not below small share")
			get_tree().quit(1)
			return
		game.call("_open_share_overlay")
		await get_tree().process_frame
		await get_tree().process_frame
		if wipe_again.disabled != true or wipe_menu.disabled != true:
			push_error("[share] wipe out controls still enabled under overlay")
			get_tree().quit(1)
			return
		var share_layer: CanvasLayer = game.get("_share_layer")
		if share_layer == null or not share_layer.visible:
			push_error("[share] share overlay not visible")
			get_tree().quit(1)
			return
		var png: PackedByteArray = game.call("_capture_share_card_png")
		if png.is_empty():
			push_error("[share] empty ShareCard capture")
			get_tree().quit(1)
			return
		var img := Image.new()
		var err := img.load_png_from_buffer(png)
		if err != OK:
			push_error("[share] capture was not a PNG")
			get_tree().quit(1)
			return
		if img.get_width() != 1153 or img.get_height() != 798:
			push_error("[share] unexpected capture size %sx%s" % [img.get_width(), img.get_height()])
			get_tree().quit(1)
			return
		var out_path := "user://reefrun-share-test.png"
		img.save_png(out_path)
		var lime := 0
		var red_btn := 0
		for y in range(maxi(0, img.get_height() - 40), img.get_height()):
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a < 0.4:
					continue
				if c.g > 0.66 and c.b < 0.22 and c.r < 0.55:
					lime += 1
				if c.r > 0.82 and c.g < 0.28 and c.b < 0.24:
					red_btn += 1
		print("[share] bottom control colors lime=%s red=%s" % [lime, red_btn])
		game.call("_close_share_overlay", true)
		await get_tree().process_frame
		if game.get("_share_layer") != null:
			push_error("[share] overlay did not close")
			get_tree().quit(1)
			return
		if not bool(game.get("finished")):
			push_error("[share] closing overlay reset finished")
			get_tree().quit(1)
			return
		if int(game.get("_over_rank")) != 12 or int(game.get("score")) != 7:
			push_error("[share] closing overlay changed run data")
			get_tree().quit(1)
			return
		if wipe_again.disabled or wipe_menu.disabled:
			push_error("[share] wipe out controls did not restore")
			get_tree().quit(1)
			return
		print("[share] ok size=%sx%s png=%s path=%s" % [img.get_width(), img.get_height(), png.size(), ProjectSettings.globalize_path(out_path)])
		get_tree().quit(0)
