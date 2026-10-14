extends RefCounted

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")
const RulesScript := preload("res://scripts/share/referral_rules.gd")


func status_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/get_share_reward_status"


func sync_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/rpc/sync_share_progress"


func sync_body(code: String, completed: bool) -> String:
	return JSON.stringify(RulesScript.sync_body(code, completed))
