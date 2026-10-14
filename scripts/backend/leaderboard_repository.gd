extends RefCounted

# Daily board: Daily Challenge rows, written by finalize_daily_attempt.
# Weekly and monthly boards: Unlimited rows, written by submit_leaderboard_score.

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")


func claim_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/claim_daily_attempt"


func status_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/get_daily_attempt_status"


func start_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/start_daily_attempt"


func finalize_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/finalize_daily_attempt"


func list_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/get_leaderboard"


func submit_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/submit_leaderboard_score"


func parse_rows(data: Variant) -> Array:
	var rows: Array = _as_rows(data)
	var out: Array = []
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var name := _name_from_row(row)
		var score := _score_from_row(row)
		if score <= 0:
			continue
		out.append({"name": name, "score": score, "display_name": name})
	return out


func _as_rows(data: Variant) -> Array:
	if data is Array:
		return data
	if typeof(data) == TYPE_DICTIONARY:
		return [data]
	return []


func _name_from_row(row: Dictionary) -> String:
	for key in ["display_name", "name", "player_name"]:
		var value := str(row.get(key, "")).strip_edges()
		if _usable_name(value):
			return value
	return ""


func _score_from_row(row: Dictionary) -> int:
	for key in ["score", "best_score"]:
		if row.has(key):
			return int(row.get(key, 0))
	return 0


func _usable_name(value: String) -> bool:
	if value.is_empty() or value == "<null>" or value == "null":
		return false
	if value.begins_with("local_"):
		return false
	if value.find("-") >= 0 and value.length() >= 32:
		return false
	return true
