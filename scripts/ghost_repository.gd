extends RefCounted

# Swap this implementation later (Supabase/Firebase/server) without changing game.gd.
# Contract: get_runs_for_seed(course_seed) -> Array of GhostRun.


func get_runs_for_seed(_course_seed: int) -> Array:
	return []
