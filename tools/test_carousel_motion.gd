extends SceneTree

## Fish and hat carousels ease between positions and keep the item under the finger.

func _initialize() -> void:
	root.add_child(Runner.new())


class Runner extends Node:
	const SAVE_PATH := "user://reefrun.cfg"

	func _ready() -> void:
		var snap := _snapshot()
		var fail := await _checks()
		if fail != "":
			push_error("[carousel] " + fail)
		_restore(snap)
		var session := get_node("/root/GameSession")
		var code := 0 if fail == "" else 1
		if int(session.fish_index) != int(snap["fish"]) or int(session.hat_index) != int(snap["hat"]) or int(session.coins) != int(snap["coins"]):
			push_error("[carousel] selection was not restored")
			code = 1
		else:
			print("[carousel] restored fish %s hat %s" % [session.fish_index, session.hat_index])
		print("[carousel] %s" % ("ok" if code == 0 else "failed"))
		get_tree().quit(code)

	func _checks() -> String:
		var session := get_node("/root/GameSession")
		var menu: Node = load("res://scenes/menu/main_menu.tscn").instantiate()
		add_child(menu)
		menu.set_process(false)
		menu.set_process_input(false)
		var row := menu.get("_fish_row") as CanvasItem
		var cell := (menu.get("_fish_cells") as Array)[0] as CanvasItem
		if row.physics_interpolation_mode != CanvasItem.PHYSICS_INTERPOLATION_MODE_OFF:
			return "fish row still physics-interpolated"
		if cell.physics_interpolation_mode != CanvasItem.PHYSICS_INTERPOLATION_MODE_OFF:
			return "fish cell still physics-interpolated"
		var hat_row := menu.get("_hat_row") as CanvasItem
		if hat_row.physics_interpolation_mode != CanvasItem.PHYSICS_INTERPOLATION_MODE_OFF:
			return "hat row still physics-interpolated"
		var stride := float(menu.get("_fish_cell")) + float(menu.get("_fish_gap"))
		var slow := _sample_slide(menu, stride, 11, 0.02)
		var fast := _sample_slide(menu, stride, 22, 0.01)
		if absf(slow - fast) > 0.001:
			return "60 Hz slide %.3f differs from 120 Hz %.3f" % [slow, fast]
		if absf(slow - stride) > 0.001:
			return "slide ended at %.3f instead of %.3f" % [slow, stride]
		_reset_fish(menu, 0.0)
		menu.call("_scroll_fish", stride)
		menu.call("_tick_carousels", 0.11)
		var mid := float(menu.get("_fish_scroll_visual"))
		if absf(mid - stride * 0.5) > 0.6:
			return "mid slide %.2f is not eased" % mid
		if absf((menu.get("_fish_row") as Control).position.x + mid) > 0.001:
			return "row position was rounded away from the slide"
		menu.call("_scroll_fish", -stride)
		if absf(float(menu.get("_fish_scroll_visual")) - mid) > 0.001:
			return "reverse snapped away from the current position"
		if absf(float(menu.get("_fish_slide_from")) - mid) > 0.001:
			return "reverse did not start from the visible position"
		menu.call("_tick_carousels", 0.01)
		var backed := float(menu.get("_fish_scroll_visual"))
		if backed >= mid - 0.01 or backed <= 0.0:
			return "reverse did not move smoothly back"
		menu.call("_tick_carousels", 0.22)
		if absf(float(menu.get("_fish_scroll_visual"))) > 0.05:
			return "reverse did not finish at the new target"
		_reset_fish(menu, 0.0)
		menu.call("_scroll_fish", stride)
		menu.call("_scroll_fish", stride)
		menu.call("_scroll_fish", stride)
		if absf(float(menu.get("_fish_scroll_x")) - stride * 3.0) > 0.001:
			return "rapid swipes dropped a step"
		if absf(float(menu.get("_fish_scroll_visual"))) > 0.001:
			return "rapid swipes jumped the row before the slide"
		menu.call("_tick_carousels", 0.22)
		if absf(float(menu.get("_fish_scroll_visual")) - stride * 3.0) > 0.05:
			return "rapid swipes did not arrive together"
		_reset_fish(menu, 40.0)
		menu.call("_scroll_fish", stride)
		menu.call("_tick_carousels", 0.05)
		var during := float(menu.get("_fish_scroll_visual"))
		menu.call("_begin_fish_drag", Vector2(20.0, 8.0))
		menu.call("_move_fish_drag", Vector2(-10.0, 8.0))
		var dragged := float(menu.get("_fish_scroll_visual"))
		if absf(dragged - (during + 30.0)) > 0.05:
			return "drag lagged the finger (%.2f vs %.2f)" % [dragged, during + 30.0]
		if float(menu.get("_fish_slide_t")) < 1.0:
			return "drag left a slide running"
		var before := int(session.fish_index)
		_reset_fish(menu, 0.0)
		menu.set("_fish_scroll_x", stride * 5.0)
		menu.call("_click_fish_at", Vector2(4.0 + float(menu.get("_fish_cell")) * 0.5, 40.0))
		var shown: int = (menu.get("_fish_order") as PackedInt32Array)[0]
		if int(session.fish_index) != shown:
			return "tap selected %s instead of the fish on screen %s" % [session.fish_index, shown]
		session.fish_index = before
		var coins := int(session.coins)
		var locked := _locked_fish(session)
		if locked < 0:
			return "no locked fish to test"
		session.coins = 0
		menu.call("_choose_fish", locked)
		if int(session.fish_index) != before or int(session.coins) != 0:
			return "locked fish changed the selection"
		session.coins = coins
		var hat_before := int(session.hat_index)
		var locked_hat := _locked_hat(session)
		if locked_hat < 0:
			return "no locked hat to test"
		session.coins = 0
		menu.call("_choose_hat", locked_hat)
		if int(session.hat_index) != hat_before or int(session.coins) != 0:
			return "locked hat changed the selection"
		session.coins = coins
		var hat_stride := float(menu.get("_hat_cell")) + float(menu.get("_hat_gap"))
		menu.set("_hat_scroll_x", 0.0)
		menu.call("_apply_hat_scroll")
		menu.call("_scroll_hats", hat_stride)
		menu.call("_tick_carousels", 0.11)
		var hat_mid := float(menu.get("_hat_scroll_visual"))
		if absf(hat_mid - hat_stride * 0.5) > 0.6:
			return "hat slide did not ease"
		menu.call("_tick_carousels", 0.22)
		if absf(float(menu.get("_hat_scroll_visual")) - hat_stride) > 0.05:
			return "hat slide did not finish"
		var goal_icon: TextureRect = null
		for icon in menu.get("_fish_icons"):
			if absf(float(icon.get_meta("scale_goal", 1.0)) - 1.08) < 0.001:
				goal_icon = icon
				break
		if goal_icon == null:
			return "selected fish has no highlight goal"
		goal_icon.scale = Vector2.ONE
		menu.call("_tick_carousels", 0.02)
		if goal_icon.scale.x <= 1.001 or goal_icon.scale.x >= 1.08:
			return "highlight scale did not ease"
		menu.call("_tick_carousels", 0.22)
		if absf(goal_icon.scale.x - 1.08) > 0.01:
			return "highlight did not settle"
		var shared := 0
		var ring_on: StyleBox = menu.get("_fish_ring_on")
		var ring_off: StyleBox = menu.get("_fish_ring_off")
		for ring in menu.get("_fish_rings"):
			var style: StyleBox = ring.get_theme_stylebox("panel")
			if style == ring_on or style == ring_off:
				shared += 1
		if shared != (menu.get("_fish_rings") as Array).size():
			return "selection rebuilt highlight styles"
		var fish_icon := (menu.get("_fish_icons") as Array)[0] as Control
		var hat_icon := (menu.get("_hat_icons") as Array)[0] as Control
		if absf(fish_icon.size.y - 68.0) > 0.05 or absf(hat_icon.size.y - 52.0) > 0.05:
			return "carousel icon size changed"
		if menu.get("_best_row") == null or menu.get("_wallet_coin") == null:
			return "menu chrome missing"
		for height in [960.0, 1170.0, 1260.0]:
			var resized := await _set_portrait(height)
			if resized != "":
				return resized
			menu.call("_sync_menu_anchor")
			_reset_fish(menu, 0.0)
			menu.call("_scroll_fish", stride)
			menu.call("_tick_carousels", 0.22)
			if absf(float(menu.get("_fish_scroll_visual")) - stride) > 0.05:
				return "portrait %s slide missed the slot" % height
			print("[carousel] portrait %.0f slide=%.1f" % [height, float(menu.get("_fish_scroll_visual"))])
		return ""

	func _sample_slide(menu: Node, stride: float, steps: int, dt: float) -> float:
		_reset_fish(menu, 0.0)
		menu.call("_scroll_fish", stride)
		for _i in steps:
			menu.call("_tick_carousels", dt)
		return float(menu.get("_fish_scroll_visual"))

	func _reset_fish(menu: Node, x: float) -> void:
		menu.set("_fish_scroll_x", x)
		menu.call("_apply_fish_scroll")

	func _locked_fish(session: Node) -> int:
		for index in RR.FISH_IDS.size():
			if not session.owns_fish(index):
				return index
		return -1

	func _locked_hat(session: Node) -> int:
		for index in RR.HAT_COUNT:
			if not session.owns_hat(index):
				return index
		return -1

	func _set_portrait(height: float) -> String:
		var win := get_tree().root
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
		win.content_scale_size = Vector2i(int(RR.VIEW_W), int(RR.VIEW_H))
		win.size = Vector2i(int(RR.VIEW_W), int(height))
		await get_tree().process_frame
		if absf(win.get_visible_rect().size.y - height) > 1.0:
			return "portrait %s visible %s" % [height, win.get_visible_rect().size]
		return ""

	func _snapshot() -> Dictionary:
		var existed := FileAccess.file_exists(SAVE_PATH)
		var bytes := PackedByteArray()
		if existed:
			bytes = FileAccess.get_file_as_bytes(SAVE_PATH)
		var session := get_node("/root/GameSession")
		return {
			"existed": existed,
			"bytes": bytes,
			"fish": int(session.fish_index),
			"hat": int(session.hat_index),
			"coins": int(session.coins),
		}

	func _restore(snap: Dictionary) -> void:
		var session := get_node("/root/GameSession")
		if bool(snap["existed"]):
			var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
			if f:
				f.store_buffer(snap["bytes"])
				f.close()
			session._load()
		else:
			session.fish_index = int(snap["fish"])
			session.hat_index = int(snap["hat"])
			session.coins = int(snap["coins"])
