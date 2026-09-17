class_name ShareProvider
extends Node

signal share_finished(status: String)


func is_busy() -> bool:
	return false


func share_image(_bytes: PackedByteArray) -> String:
	share_finished.emit("failed")
	return "failed"
