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


func describe_raw(data: Variant) -> String:
	if data == null:
		return "null"
	if data is Array:
		if data.is_empty():
			return "array(0)"
		var first: Variant = data[0]
		if typeof(first) == TYPE_DICTIONARY:
			return "array(%d) keys=%s sample=%s" % [data.size(), str(first.keys()), _safe_sample(first)]
		return "array(%d) first_type=%s" % [data.size(), type_string(typeof(first))]
	if typeof(data) == TYPE_DICTIONARY:
		return "object keys=%s sample=%s" % [str(data.keys()), _safe_sample(data)]
	return type_string(typeof(data))


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


func _safe_sample(row: Dictionary) -> String:
	return "{display_name=%s name=%s score=%s}" % [
		str(row.get("display_name", "")),
		str(row.get("name", "")),
		str(row.get("score", row.get("best_score", ""))),
	]
