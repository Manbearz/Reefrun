extends Node

signal share_finished(status: String)

const WebShareScript := preload("res://scripts/share/web_share_provider.gd")
const NativeShareScript := preload("res://scripts/share/native_share_provider.gd")

var _provider: ShareProvider


func _ready() -> void:
	_provider = _make_provider()
	add_child(_provider)
	_provider.share_finished.connect(_on_provider_finished)


func is_busy() -> bool:
	return _provider != null and _provider.is_busy()


func share_image(bytes: PackedByteArray) -> String:
	if _provider == null:
		share_finished.emit("failed")
		return "failed"
	return _provider.share_image(bytes)


func _make_provider() -> ShareProvider:
	if OS.has_feature("web"):
		return WebShareScript.new()
	return NativeShareScript.new()


func _on_provider_finished(status: String) -> void:
	share_finished.emit(status)
