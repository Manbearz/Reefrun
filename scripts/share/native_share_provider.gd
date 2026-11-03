extends ShareProvider

# Android opens the system Sharesheet through the built-in AndroidRuntime and
# Godot's FileProvider. iOS presents UIActivityViewController through the
# SharePlugin library in res://ios/plugins. Desktop saves the card and does
# not present a native share sheet.

const _PNG_PATH := "user://reefrun-run.png"

var _busy := false
var _last_status := ""
var _sheet_open := false
var _saw_background := false
var _saw_return := false
var _present_returned := false
var _ios_plugin: Object
var _ios_connected := false
var _android_task: Callable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_busy() -> bool:
	return _busy


func share_image(bytes: PackedByteArray, message: String = "") -> String:
	if _busy:
		return "busy"
	if bytes.is_empty():
		share_finished.emit("failed")
		return "failed"
	if OS.has_feature("android"):
		return _share_android(bytes, message)
	if OS.has_feature("ios"):
		return _share_ios(bytes, message)
	return _share_desktop(bytes, message)


func _notification(what: int) -> void:
	if not _sheet_open:
		return
	if (
		what == NOTIFICATION_APPLICATION_PAUSED
		or what == NOTIFICATION_APPLICATION_FOCUS_OUT
		or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT
	):
		_saw_background = true
		return
	if (
		what == NOTIFICATION_APPLICATION_RESUMED
		or what == NOTIFICATION_APPLICATION_FOCUS_IN
		or what == NOTIFICATION_WM_WINDOW_FOCUS_IN
	):
		_saw_return = true
		if _present_returned and _saw_background:
			_complete("closed")


func _share_android(bytes: PackedByteArray, message: String) -> String:
	var abs_path := _write_png(bytes)
	if abs_path.is_empty():
		share_finished.emit("failed")
		return "failed"
	if not Engine.has_singleton("AndroidRuntime"):
		share_finished.emit("failed")
		return "failed"
	var runtime: Object = Engine.get_singleton("AndroidRuntime")
	if runtime == null or not runtime.has_method("getActivity") or not runtime.has_method("createRunnableFromGodotCallable"):
		share_finished.emit("failed")
		return "failed"
	var activity: Object = runtime.getActivity()
	if activity == null:
		share_finished.emit("failed")
		return "failed"
	_busy = true
	_sheet_open = true
	_saw_background = false
	_saw_return = false
	_present_returned = false
	_android_task = _run_android_sheet.bind(runtime, activity, abs_path, message)
	activity.runOnUiThread(runtime.createRunnableFromGodotCallable(_android_task))
	_present_returned = true
	if not _busy:
		return _last_status
	if _saw_background and _saw_return:
		_complete("closed")
		return _last_status
	return "started"


func _run_android_sheet(runtime: Object, activity: Object, abs_path: String, message: String) -> void:
	if not _busy:
		return
	if not _open_android_sheet(runtime, activity, abs_path, message):
		_complete("failed")


func _open_android_sheet(runtime: Object, activity: Object, abs_path: String, message: String) -> bool:
	var java := _java_wrapper()
	if java == null:
		return false
	_clear_java_exception()
	var Intent: Object = java.wrap("android.content.Intent")
	if _java_failed():
		return false
	var intent: Object = Intent.Intent()
	if intent == null or _java_failed():
		return false
	intent.setAction(Intent.ACTION_SEND)
	var uri: Object = _android_image_uri(runtime, abs_path)
	var text := message.strip_edges()
	if uri == null:
		_clear_java_exception()
	if uri != null:
		intent.setType("image/png")
		intent.putExtra(Intent.EXTRA_STREAM, uri)
		if text != "":
			intent.putExtra(Intent.EXTRA_TEXT, text)
		var ClipData: Object = _java_wrapper().wrap("android.content.ClipData")
		intent.setClipData(ClipData.newRawUri("ReefRun", uri))
		intent.addFlags(int(Intent.FLAG_GRANT_READ_URI_PERMISSION))
	elif text != "":
		intent.setType("text/plain")
		intent.putExtra(Intent.EXTRA_TEXT, text)
	else:
		return false
	if _java_failed():
		return false
	var chooser: Object = Intent.createChooser(intent, "Share")
	if chooser == null or _java_failed():
		return false
	if uri != null:
		chooser.addFlags(int(Intent.FLAG_GRANT_READ_URI_PERMISSION))
	activity.startActivity(chooser)
	return not _java_failed()


func _android_image_uri(runtime: Object, abs_path: String) -> Object:
	if abs_path.is_empty() or not runtime.has_method("getApplicationContext"):
		return null
	var context: Object = runtime.getApplicationContext()
	if context == null or _java_failed():
		return null
	var java := _java_wrapper()
	if java == null:
		return null
	var File: Object = java.wrap("java.io.File")
	var file: Object = File.File(abs_path)
	if file == null or _java_failed() or not bool(file.exists()):
		return null
	var package_name := str(context.getPackageName())
	if package_name.is_empty() or _java_failed():
		return null
	var FileProvider: Object = _java_wrapper().wrap("androidx.core.content.FileProvider")
	var uri: Object = FileProvider.getUriForFile(context, package_name + ".fileprovider", file)
	if uri == null or _java_failed():
		return null
	return uri


func _share_ios(bytes: PackedByteArray, message: String) -> String:
	var abs_path := _write_png(bytes)
	var plugin := _ensure_ios_plugin()
	if abs_path.is_empty() or plugin == null or not plugin.has_method("share"):
		share_finished.emit("failed")
		return "failed"
	_busy = true
	plugin.call("share", {
		"title": "ReefRun",
		"subject": "ReefRun",
		"content": message,
		"file_path": abs_path,
		"mime_type": "image/png",
	})
	if not _busy:
		return _last_status
	return "started"


func _ensure_ios_plugin() -> Object:
	if not Engine.has_singleton("SharePlugin"):
		return null
	if _ios_plugin == null:
		_ios_plugin = Engine.get_singleton("SharePlugin")
	if _ios_plugin != null and not _ios_connected:
		_ios_plugin.connect("share_completed", _on_ios_completed)
		_ios_plugin.connect("share_canceled", _on_ios_canceled)
		_ios_plugin.connect("share_failed", _on_ios_failed)
		_ios_connected = true
	return _ios_plugin


func _on_ios_completed(_activity_type: String) -> void:
	_complete("ok")


func _on_ios_canceled() -> void:
	_complete("cancel")


func _on_ios_failed(_error_message: String) -> void:
	_complete("failed")


func _share_desktop(bytes: PackedByteArray, message: String) -> String:
	if message.strip_edges() != "" and DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(message)
	var file := FileAccess.open(_PNG_PATH, FileAccess.WRITE)
	if file == null:
		share_finished.emit("failed")
		return "failed"
	file.store_buffer(bytes)
	file.close()
	if DisplayServer.get_name() != "headless":
		var abs_path := ProjectSettings.globalize_path(_PNG_PATH)
		if not abs_path.is_empty():
			OS.shell_open(abs_path)
	share_finished.emit("saved")
	return "saved"


func _write_png(bytes: PackedByteArray) -> String:
	var file := FileAccess.open(_PNG_PATH, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.close()
	return ProjectSettings.globalize_path(_PNG_PATH)


func _complete(status: String) -> void:
	if not _busy:
		return
	_busy = false
	_sheet_open = false
	_saw_background = false
	_saw_return = false
	_present_returned = false
	_last_status = status
	share_finished.emit(status)


func _java_wrapper() -> Object:
	if not Engine.has_singleton("JavaClassWrapper"):
		return null
	return Engine.get_singleton("JavaClassWrapper")


func _java_failed() -> bool:
	var java := _java_wrapper()
	if java == null or not java.has_method("get_exception"):
		return false
	return java.get_exception() != null


func _clear_java_exception() -> void:
	var java := _java_wrapper()
	if java != null and java.has_method("get_exception"):
		java.get_exception()
