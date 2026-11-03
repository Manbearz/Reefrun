extends SceneTree

const MENU_PATH := "res://scenes/menu/main_menu.tscn"

var _failed := 0


func _initialize() -> void:
	ProjectSettings.set_setting("network/http_proxy/host", "127.0.0.1")
	ProjectSettings.set_setting("network/http_proxy/port", 9)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var screen: Node = load("res://scenes/boot/loading_screen.tscn").instantiate()
	root.add_child(screen)
	var samples: Array = []
	var saw_partial := false
	var previous_shown := -1.0
	var previous_actual := -1.0
	var full_before_ready := 0
	var finish_frames := 0
	var max_step := 0.0
	for _frame in 900:
		await process_frame
		if not is_instance_valid(screen):
			break
		var shown := float(screen._displayed)
		var actual := float(screen._actual)
		if shown > actual + 0.001:
			_bad("bar %.3f ran ahead of loading %.3f" % [shown, actual])
		if previous_shown >= 0.0 and shown + 0.0001 < previous_shown:
			_bad("bar moved backward")
		if previous_shown >= 0.0 and absf(actual - previous_actual) <= 0.0001 and previous_shown >= previous_actual - 0.0001 and shown > previous_shown + 0.0001:
			_bad("bar advanced after loading had paused")
		if previous_shown >= 0.0:
			max_step = maxf(max_step, shown - previous_shown)
		if shown >= 0.999 and actual < 0.999:
			full_before_ready += 1
		if actual >= 0.999 and not bool(screen._handoff):
			finish_frames += 1
		if shown > 0.02 and shown < 0.9:
			saw_partial = true
		samples.append("%d shown=%.3f actual=%.3f fin=%d" % [samples.size(), shown, actual, int(screen._finished)])
		previous_shown = shown
		previous_actual = actual
	var menu: Node = current_scene
	var menu_ok := menu != null and menu.get_script() != null and str(menu.get_script().resource_path).ends_with("main_menu.gd")
	var timing: Dictionary = root.get_meta("boot_ms", {})
	var spawned := float(timing.get("spawned", -1.0))
	var shown_at := float(timing.get("shown", -1.0))
	if samples.is_empty():
		_bad("no samples")
	if full_before_ready > 0:
		_bad("100 percent while the menu was not ready")
	if finish_frames < 2 or finish_frames > 40:
		_bad("finish glide took %d frames" % finish_frames)
	if max_step > 0.15:
		_bad("bar jumped by %.3f in one frame" % max_step)
	if spawned < 0.0 or shown_at < 0.0:
		_bad("missing handoff timestamps")
	if not menu_ok:
		_bad("main menu did not open")
	print("[boot-progress] timing screen=%.0f resources=%.0f spawned=%.0f shown=%.0f prepare=%.0f" % [
		float(timing.get("screen", 0.0)),
		float(timing.get("resources", 0.0)),
		spawned,
		shown_at,
		shown_at - spawned,
	])
	var head := samples.slice(0, mini(6, samples.size()))
	var tail := samples.slice(maxi(samples.size() - 6, 0), samples.size())
	print("[boot-progress] frames=%d partial=%s finish_frames=%d max_step=%.3f menu=%s" % [samples.size(), str(saw_partial), finish_frames, max_step, str(menu_ok)])
	print("[boot-progress] first=%s" % str(head))
	print("[boot-progress] last=%s" % str(tail))
	print("[boot-progress] ok=%s" % str(_failed == 0))
	quit(0 if _failed == 0 else 1)


func _bad(reason: String) -> void:
	_failed += 1
	push_error("[boot-progress] %s" % reason)
