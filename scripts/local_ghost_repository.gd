extends "res://scripts/ghost_repository.gd"

var bank


func _init(p_bank = null) -> void:
	bank = p_bank


func get_runs_for_seed(course_seed: int) -> Array:
	if bank == null:
		return []
	return bank.get_runs(course_seed)
