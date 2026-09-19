extends "res://scripts/ghost_repository.gd"


var _sources: Array = []


func _init(sources: Array = []) -> void:
	_sources = sources


func get_runs_for_seed(course_seed: int) -> Array:
	var out: Array = []
	for source in _sources:
		if source == null or not source.has_method("get_runs_for_seed"):
			continue
		var chunk: Array = source.get_runs_for_seed(course_seed)
		for run in chunk:
			out.append(run)
	return out
