extends RefCounted

# STAGE 6 stub. Global weekly/monthly boards will read leaderboard_scores.
# Writes must eventually go through a validated RPC, not a raw client insert.

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")


func list_url(period: String, period_key: String, limit: int = 10) -> String:
	return (
		ConfigScript.project_url()
		+ "/rest/v1/leaderboard_scores?select=display_name,score,period,period_key,created_at"
		+ "&period=eq.%s&period_key=eq.%s&order=score.desc&limit=%d" % [period, period_key, limit]
	)
