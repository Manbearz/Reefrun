extends RefCounted

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")


func board_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/get_daily_missions"


func record_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/record_unlimited_mission_run"


func claim_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/claim_daily_mission"


func record_body(run_id: String, pipes: int, seconds: int, gameplay_coins: int, dive: Dictionary = {}) -> String:
	return JSON.stringify({
		"p_run_id": run_id,
		"p_pipes": pipes,
		"p_seconds": seconds,
		"p_gameplay_coins": gameplay_coins,
		"p_dives_entered": int(dive.get("dives_entered", 0)),
		"p_dives_completed": int(dive.get("dives_completed", 0)),
		"p_dive_seconds": int(dive.get("dive_seconds", 0)),
		"p_lane_changes": int(dive.get("lane_changes", 0)),
		"p_lanes_left": int(dive.get("lanes_left", 0)),
		"p_lanes_right": int(dive.get("lanes_right", 0)),
		"p_obstacles": int(dive.get("obstacles", 0)),
		"p_mines": int(dive.get("mines", 0)),
	})


func legacy_record_body(run_id: String, pipes: int, seconds: int, gameplay_coins: int) -> String:
	return JSON.stringify({
		"p_run_id": run_id,
		"p_pipes": pipes,
		"p_seconds": seconds,
		"p_gameplay_coins": gameplay_coins,
	})


func claim_body(slot: String) -> String:
	return JSON.stringify({"p_slot": slot})
