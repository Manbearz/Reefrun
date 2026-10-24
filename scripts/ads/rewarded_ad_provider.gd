class_name RewardedAdProvider
extends Node

# session_id is assigned by begin_show_session() before show_session().
# Callbacks repeat that id. They do not carry an AdMob response id.
signal reward_earned(session_id: int)
signal ad_closed(session_id: int)
signal ad_failed(reason: String, session_id: int)
signal ad_unavailable(session_id: int)

var _session_serial := 0


func is_available() -> bool:
	return false


func begin_show_session() -> int:
	_session_serial += 1
	return _session_serial


func show_session(session_id: int) -> void:
	_emit_unavailable(session_id)


func _emit_reward(session_id: int) -> void:
	reward_earned.emit(session_id)


func _emit_closed(session_id: int) -> void:
	ad_closed.emit(session_id)


func _emit_failed(reason: String, session_id: int) -> void:
	ad_failed.emit(reason, session_id)


func _emit_unavailable(session_id: int) -> void:
	ad_unavailable.emit(session_id)
