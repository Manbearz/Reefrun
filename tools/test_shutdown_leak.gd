extends SceneTree

# Quits immediately so a --verbose run can name ObjectDB leaks that exist
# before any gameplay scene is created.
# Godot --headless --verbose --path . --script res://tools/test_shutdown_leak.gd

func _initialize() -> void:
	ProjectSettings.set_setting("network/http_proxy/host", "127.0.0.1")
	ProjectSettings.set_setting("network/http_proxy/port", 9)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[shutdown] nodes=%d objects=%d resources=%d" % [
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	])
	quit(0)
