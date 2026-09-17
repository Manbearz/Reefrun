extends ShareProvider

# Future native iOS/Android export should open the OS share sheet here.
# Godot has no built-in mobile share plugin in this project yet, so desktop
# and non-web exports save the PNG and let the OS open it.


func share_image(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		share_finished.emit("failed")
		return "failed"
	var path := "user://reefrun-run.png"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		share_finished.emit("failed")
		return "failed"
	file.store_buffer(bytes)
	file.close()
	if DisplayServer.get_name() != "headless":
		var abs_path := ProjectSettings.globalize_path(path)
		if not abs_path.is_empty():
			OS.shell_open(abs_path)
	share_finished.emit("saved")
	return "saved"
