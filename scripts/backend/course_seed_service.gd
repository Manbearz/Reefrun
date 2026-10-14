extends RefCounted

# Shared/rotating course seeds so many players record GhostRuns on the same course.
# Unconfigured / failed fetch: GameSession keeps its existing local seed behavior.

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")
const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")


func challenge_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/get_daily_challenge"


func parse_challenge(data: Variant) -> Dictionary:
	return DailyChallengeScript.from_server(data)


func current_url() -> String:
	return (
		ConfigScript.project_url()
		+ "/rest/v1/course_rotations?select=course_seed,course_version,physics_version,starts_at,ends_at"
		+ "&order=starts_at.desc&limit=1"
	)


func parse_seed(data: Variant) -> int:
	if data is Array and not data.is_empty() and typeof(data[0]) == TYPE_DICTIONARY:
		return int(data[0].get("course_seed", 0))
	if typeof(data) == TYPE_DICTIONARY:
		return int(data.get("course_seed", 0))
	return 0
