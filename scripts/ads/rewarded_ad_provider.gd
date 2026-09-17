class_name RewardedAdProvider
extends Node

signal reward_earned
signal ad_closed
signal ad_failed(reason: String)
signal ad_unavailable


func is_available() -> bool:
	return false


func show() -> void:
	ad_unavailable.emit()
