extends "res://scripts/ghost_repository.gd"


var _sources: Array = []


func _init(sources: Array = []) -> void:
	_sources = sources


func get_runs_for_seed(course_seed: int) -> Array:
	return _gather(course_seed, "")


func get_runs_for_challenge(course_seed: int, challenge_id: String) -> Array:
	return _gather(course_seed, challenge_id)


func _gather(course_seed: int, challenge_id: String) -> Array:
	var out: Array = []
	for source in _sources:
		if source == null:
			continue
		var chunk: Array = []
		if challenge_id != "" and source.has_method("get_runs_for_challenge"):
			chunk = source.get_runs_for_challenge(course_seed, challenge_id)
		elif source.has_method("get_runs_for_seed"):
			chunk = source.get_runs_for_seed(course_seed)
		for run in chunk:
			out.append(run)
	return out
