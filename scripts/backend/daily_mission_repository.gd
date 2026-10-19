extends RefCounted

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")


func board_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/get_daily_missions"


func record_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/record_unlimited_mission_run"


func claim_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/claim_daily_mission"


func record_body(run_id: String, pipes: int, seconds: int, gameplay_coins: int) -> String:
	return JSON.stringify({
		"p_run_id": run_id,
		"p_pipes": pipes,
		"p_seconds": seconds,
		"p_gameplay_coins": gameplay_coins,
	})


func claim_body(slot: String) -> String:
	return JSON.stringify({"p_slot": slot})
