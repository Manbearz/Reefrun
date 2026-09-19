extends RefCounted

# Global weekly/monthly boards. Writes go through submit_leaderboard_score RPC
# so player_id is auth.uid(), not a client-chosen UUID.

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")


func submit_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/submit_leaderboard_score"


func list_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/get_leaderboard"


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
