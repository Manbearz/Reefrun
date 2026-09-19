extends RefCounted

# STAGE 3 — profile + cosmetics.
# Client may update display_name / selected fish / hat.
# coins, best_score, games_played must eventually be written only by
# server-side functions after validation. See tools/supabase/schema.sql.

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")


func profiles_url(user_id: String) -> String:
	return ConfigScript.project_url() + "/rest/v1/profiles?id=eq.%s" % user_id


func profile_insert_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/profiles"


func cosmetics_url(user_id: String) -> String:
	return ConfigScript.project_url() + "/rest/v1/player_cosmetics?player_id=eq.%s" % user_id


func cosmetic_insert_url() -> String:
	return ConfigScript.project_url() + "/rest/v1/player_cosmetics"


func from_row(row: Dictionary) -> Dictionary:
	return {
		"player_id": str(row.get("id", "")),
		"display_name": str(row.get("display_name", "")),
		"coins": int(row.get("coins", 0)),
		"selected_fish": int(row.get("selected_fish", 0)),
		"selected_hat": int(row.get("selected_hat", -1)),
		"best_score": int(row.get("best_score", 0)),
		"best_rank": int(row.get("best_rank", 100)),
		"games_played": int(row.get("games_played", 0)),
	}


func local_safe_patch(session: Node) -> Dictionary:
	return {
		"display_name": session.player_name,
		"selected_fish": session.fish_index,
		"selected_hat": session.hat_index,
	}
