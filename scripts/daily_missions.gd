class_name DailyMissions
extends RefCounted

# Live mission selection happens in Supabase. The mission day is midnight
# America/New_York, the same boundary as the Daily Challenge and Daily board.
# preview_rotation() mirrors the picker for tests. The game never uses it
# to decide which missions a player receives.

const MAX_DAILY_REWARD := 60
const MAX_PIPES_PER_RUN := 20000
const MAX_SECONDS_PER_RUN := 86400
const MAX_STORED_RUNS := 60
const MAX_PENDING_RUNS := 40
const REWARDS := {
	"easy": 5,
	"medium": 10,
	"hard": 20,
	"bonus": 25,
}
const EXCLUDED := [6, 13, 23, 35, 36, 37]

static var _catalog: Array = []


static func catalog() -> Array:
	if _catalog.is_empty():
		_catalog = _build_catalog()
	return _catalog


static func mission_by_id(mission_id: int) -> Dictionary:
	for mission in catalog():
		if int(mission.get("id", 0)) == mission_id:
			return mission
	return {}


static func should_report(mode: String, practice: bool) -> bool:
	return mode == "unlimited" and not practice


static func gameplay_payload(picked_up: int, _ad_bonus: int) -> int:
	return maxi(0, picked_up)


static func scheduled_dives(pipes: int) -> int:
	if pipes < 30:
		return 0
	return 1 + int((pipes - 30) / 30.0)


static func survival_limit(pipes: int, dives_entered: int) -> int:
	# floor(1.8 + pipes * 1.5 + 12 + 12 * (pipes / 20))
	# plus 28 seconds for each Deep Dive the run actually entered.
	var harpoon_slack: int = 12 * int(pipes / 20.0)
	return int(floorf(1.8 + float(pipes) * 1.5 + 12.0 + float(harpoon_slack))) + 28 * dives_entered


static func accept_run(pipes: int, seconds: int, coins: int, dives_entered: int = 0) -> bool:
	if pipes < 0 or pipes > MAX_PIPES_PER_RUN:
		return false
	if seconds < 0 or seconds > MAX_SECONDS_PER_RUN:
		return false
	if coins < 0 or coins > int(pipes / 5.0):
		return false
	if pipes > 0 and seconds < pipes - 1:
		return false
	if dives_entered < 0 or dives_entered > scheduled_dives(pipes):
		return false
	if pipes < 80 and seconds > survival_limit(pipes, dives_entered):
		return false
	if pipes <= 80 and seconds > 1800:
		return false
	if pipes > 80 and seconds > survival_limit(pipes, dives_entered):
		return false
	return true


static func valid_run_id(run_id: String) -> bool:
	if run_id.length() < 8 or run_id.length() > 80:
		return false
	for i in run_id.length():
		var code := run_id.unicode_at(i)
		var digit := code >= 48 and code <= 57
		var upper := code >= 65 and code <= 90
		var lower := code >= 97 and code <= 122
		var extra := code == 45 or code == 95
		if not (digit or upper or lower or extra):
			return false
	return true


static func accept_dive(pipes: int, dive: Dictionary) -> bool:
	var entered := int(dive.get("dives_entered", 0))
	var completed := int(dive.get("dives_completed", 0))
	var dive_seconds := int(dive.get("dive_seconds", 0))
	var lanes := int(dive.get("lane_changes", 0))
	var left := int(dive.get("lanes_left", 0))
	var right := int(dive.get("lanes_right", 0))
	var obstacles := int(dive.get("obstacles", 0))
	var mines := int(dive.get("mines", 0))
	if entered < 0 or entered > scheduled_dives(pipes) or completed < 0 or completed > entered:
		return false
	if pipes < 30 and entered > 0:
		return false
	if pipes < 60 and entered > 1:
		return false
	if dive_seconds < 0 or dive_seconds > entered * 20:
		return false
	var lane_cap := maxi(400, entered * 160)
	var obstacle_cap := maxi(80, entered * 30)
	if lanes < 0 or lanes > lane_cap or left < 0 or right < 0 or left + right != lanes:
		return false
	if obstacles < 0 or obstacles > obstacle_cap or mines < 0 or mines > obstacles:
		return false
	if entered == 0 and (completed > 0 or dive_seconds > 0 or lanes > 0 or obstacles > 0):
		return false
	return true


static func count_lane_change(before: int, after: int) -> Dictionary:
	if after == before:
		return {"lanes": 0, "left": 0, "right": 0}
	if after < before:
		return {"lanes": 1, "left": 1, "right": 0}
	return {"lanes": 1, "left": 0, "right": 1}


static func enqueue(pending: Array, run_id: String, pipes: int, seconds: int, coins: int, dive: Dictionary = {}) -> Array:
	var entered := int(dive.get("dives_entered", 0))
	if not valid_run_id(run_id) or not accept_run(pipes, seconds, coins, entered) or not accept_dive(pipes, dive):
		return pending
	for item in pending:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if str(item.get("id", "")) == run_id:
			return pending
	var next: Array = pending.duplicate(true)
	if next.size() >= MAX_PENDING_RUNS:
		next.pop_front()
	next.append({
		"id": run_id,
		"pipes": pipes,
		"seconds": seconds,
		"coins": coins,
		"dives_entered": entered,
		"dives_completed": int(dive.get("dives_completed", 0)),
		"dive_seconds": int(dive.get("dive_seconds", 0)),
		"lane_changes": int(dive.get("lane_changes", 0)),
		"lanes_left": int(dive.get("lanes_left", 0)),
		"lanes_right": int(dive.get("lanes_right", 0)),
		"obstacles": int(dive.get("obstacles", 0)),
		"mines": int(dive.get("mines", 0)),
	})
	return next


static func reward_delta(applied: int, server_total: int) -> int:
	return maxi(0, server_total - maxi(0, applied))


# The next reward the server can credit. Bonus waits until easy, medium, and hard
# are already claimed. A blocked slot is skipped so a failed request cannot loop.
static func next_auto_claim(board: Dictionary, blocked: String = "") -> String:
	if not bool(board.get("ok", false)):
		return ""
	var found := {}
	var rows: Variant = board.get("slots", [])
	if typeof(rows) == TYPE_ARRAY:
		for row in rows:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var name := str(row.get("slot", ""))
			if name == "easy" or name == "medium" or name == "hard":
				found[name] = row
	for name in ["easy", "medium", "hard"]:
		if name == blocked:
			continue
		var row: Dictionary = found.get(name, {})
		if bool(row.get("complete", false)) and not bool(row.get("claimed", false)):
			return name
	if blocked == "bonus":
		return ""
	var bonus: Variant = board.get("bonus", {})
	if typeof(bonus) != TYPE_DICTIONARY:
		return ""
	if bool(bonus.get("unlocked", false)) and not bool(bonus.get("claimed", false)):
		return "bonus"
	return ""


static func claim_payout(claimed: Dictionary, slot: String, slot_complete: bool, bonus_unlocked: bool) -> int:
	if bool(claimed.get(slot, false)):
		return 0
	var amount := int(REWARDS.get(slot, 0))
	if amount <= 0:
		return 0
	if slot == "bonus":
		if not bonus_unlocked:
			return 0
	elif not slot_complete:
		return 0
	var total := 0
	for key in claimed.keys():
		if bool(claimed[key]):
			total += int(REWARDS.get(str(key), 0))
	if total + amount > MAX_DAILY_REWARD:
		return 0
	return amount


static func utc_date_key(unix_utc: int) -> String:
	var stamp := Time.get_datetime_dict_from_unix_time(unix_utc)
	return "%04d-%02d-%02d" % [int(stamp.year), int(stamp.month), int(stamp.day)]


static func mission_index(key: String, count: int) -> int:
	if count <= 0:
		return 0
	var acc := 0
	for i in key.length():
		acc = (acc * 33 + key.unicode_at(i)) % 1000003
	return acc % count


static func preview_rotation(date_key: String, recent_ids: Array) -> Dictionary:
	var used: Array = []
	var result := {}
	for tier in ["easy", "medium", "hard"]:
		var picked := _pick(date_key, tier, recent_ids, used)
		result[tier] = int(picked.get("id", 0))
		result[tier + "_family"] = str(picked.get("family", ""))
		used.append(str(picked.get("family", "")))
	return result


static func evaluate(rule: String, goal: int, goal_b: int, stats: Dictionary) -> Dictionary:
	var samples: Array = stats.get("run_pipes", [])
	var progress := 0
	var target := goal
	match rule:
		"pipes_total":
			progress = int(stats.get("pipes_total", 0))
		"pipes_best":
			progress = int(stats.get("best_pipes", 0))
		"runs":
			progress = int(stats.get("runs", 0))
		"survive_best":
			progress = int(stats.get("best_seconds", 0))
		"coins_total":
			progress = int(stats.get("gameplay_coins", 0))
		"coin_runs":
			progress = int(stats.get("coin_runs", 0))
		"runs_at_least":
			progress = _count_at_least(samples, goal)
			target = goal_b
		"window_sum":
			progress = _window_sum(samples, goal_b)
			target = goal
		"dives_entered":
			progress = int(stats.get("dives_entered", 0))
		"dives_completed":
			progress = int(stats.get("dives_completed", 0))
		"dives_best":
			progress = int(stats.get("best_dives", 0))
		"dive_seconds":
			progress = int(stats.get("dive_seconds", 0))
		"lanes_total":
			progress = int(stats.get("lane_changes", 0))
		"lanes_left":
			progress = int(stats.get("lanes_left", 0))
		"lanes_right":
			progress = int(stats.get("lanes_right", 0))
		"obstacles_total":
			progress = int(stats.get("obstacles_dodged", 0))
		"obstacles_best":
			progress = int(stats.get("best_obstacles", 0))
		"mines_total":
			progress = int(stats.get("mines_passed", 0))
		_:
			progress = 0
	return {
		"progress": progress,
		"goal": target,
		"complete": target > 0 and progress >= target,
	}


static func remaining_seconds(server_now: int, resets_at: int, fetched_at: int, now_unix: int) -> int:
	return maxi(0, resets_at - server_now - (now_unix - fetched_at))


static func progress_ratio(current: int, goal: int) -> float:
	if goal <= 0:
		return 0.0
	return clampf(float(current) / float(goal), 0.0, 1.0)


# Short labels are display-only. Catalog and database descriptions stay unchanged.
static func display_text(description: String, mission_id: int = -1) -> String:
	var mission := {}
	if mission_id > 0:
		mission = mission_by_id(mission_id)
	if mission.is_empty():
		mission = _mission_by_description(description)
	if mission.is_empty():
		return _strip_period(description)
	return short_label(mission)


static func short_label(mission: Dictionary) -> String:
	var goal := int(mission.get("goal", 0))
	var extra := int(mission.get("goal_b", 0))
	var stored := str(mission.get("description", ""))
	if stored.to_lower().contains("checkpoint"):
		return "Checkpoint %d" % goal
	match str(mission.get("rule", "")):
		"pipes_total":
			return "Pass %d %s" % [goal, _plural("Pipe", goal)]
		"pipes_best":
			return "%d %s One Run" % [goal, _plural("Pipe", goal)]
		"runs":
			return "Play %d %s" % [goal, _plural("Run", goal)]
		"survive_best":
			return "Survive %d %s" % [goal, _plural("Second", goal)]
		"coins_total":
			return "Collect %d %s" % [goal, _plural("Coin", goal)]
		"coin_runs":
			return "Coins In %d %s" % [goal, _plural("Run", goal)]
		"runs_at_least":
			return "%d %s %d %s" % [extra, _plural("Run", extra), goal, _plural("Pipe", goal)]
		"window_sum":
			return "%d %s %d %s" % [goal, _plural("Pipe", goal), extra, _plural("Run", extra)]
		"dives_entered":
			return "Enter %d %s" % [goal, _plural("Dive", goal)]
		"dives_completed":
			return "Finish %d %s" % [goal, _plural("Dive", goal)]
		"dives_best":
			return "%d %s One Run" % [goal, _plural("Dive", goal)]
		"dive_seconds":
			return "Dive %d %s" % [goal, _plural("Second", goal)]
		"lanes_total":
			return "Switch Lanes %d" % goal
		"lanes_left":
			return "Move Left %d" % goal
		"lanes_right":
			return "Move Right %d" % goal
		"obstacles_total":
			return "Dodge %d %s" % [goal, _plural("Obstacle", goal)]
		"obstacles_best":
			return "%d %s One Run" % [goal, _plural("Dodge", goal)]
		"mines_total":
			return "Pass %d %s" % [goal, _plural("Mine", goal)]
		_:
			return _strip_period(stored)


static func _plural(word: String, count: int) -> String:
	if count == 1:
		return word
	return word + "s"


static func _mission_by_description(description: String) -> Dictionary:
	var key := _normalize_desc(description)
	if key.is_empty():
		return {}
	for mission in catalog():
		if _normalize_desc(str(mission.get("description", ""))) == key:
			return mission
	return {}


static func _normalize_desc(text: String) -> String:
	return _strip_period(text).to_lower()


static func _strip_period(text: String) -> String:
	var value := text.strip_edges()
	while value.ends_with("."):
		value = value.substr(0, value.length() - 1).strip_edges()
	return value


static func icon_kind(mission_id: int, description: String = "") -> String:
	var text := description.strip_edges()
	if text.is_empty():
		text = str(mission_by_id(mission_id).get("description", ""))
	var lower := text.to_lower()
	if lower.contains("checkpoint"):
		return "flag"
	var family := str(mission_by_id(mission_id).get("family", ""))
	match family:
		"total_pipes", "one_run_pipes":
			return "pipe"
		"run_count":
			return "fish"
		"survive":
			return "stopwatch"
		"earn_coins", "coin_runs":
			return "coin"
		"multi_threshold", "window_sum", "dive_lanes", "dive_left", "dive_right", "dive_dodge", "dive_mines":
			return "medal"
		"dive_enter", "dive_complete", "dive_one_run":
			return "fish"
		"dive_time":
			return "stopwatch"
		_:
			if lower.contains("second"):
				return "stopwatch"
			if lower.contains("coin"):
				return "coin"
			if lower.contains("pipe"):
				return "pipe"
			if lower.contains("run"):
				return "fish"
			return "medal"


const ICON_DIR := "res://assets/ui/mission_icons/"
const ICON_FALLBACK := "mystery_mission"
const RULE_ICONS := {
	"pipes_total": "pipes",
	"runs_at_least": "pipes",
	"window_sum": "pipes",
	"pipes_best": "high_score",
	"runs": "complete_runs",
	"survive_best": "survive_x_seconds",
	"coins_total": "collect_x_coins",
	"coin_runs": "collect_coins",
	"dives_entered": "enter_deep_dive",
	"dive_seconds": "time_in_deep_dive",
	"dives_completed": "complete_deep_dives",
	"lanes_total": "change_lanes",
	"lanes_left": "move_left",
	"lanes_right": "move_right",
	"obstacles_total": "dodge_obstacles",
	"obstacles_best": "dodge_obstacles",
	"mines_total": "mine",
	"dives_best": "survive_without_hitting",
}

static var _icon_textures: Dictionary = {}
static var _icon_warnings: Dictionary = {}


static func icon_file(mission_id: int) -> String:
	var mission := mission_by_id(mission_id)
	var rule := str(mission.get("rule", ""))
	if mission.is_empty() or not RULE_ICONS.has(rule):
		if mission_id > 0 and not _icon_warnings.has(mission_id):
			_icon_warnings[mission_id] = true
			push_warning("Daily Missions has no icon for mission %d (rule '%s'). Using mystery_mission." % [mission_id, rule])
		return ICON_FALLBACK
	return str(RULE_ICONS[rule])


static func icon_texture(mission_id: int) -> Texture2D:
	var file := icon_file(mission_id)
	if _icon_textures.has(file):
		return _icon_textures[file]
	var path := ICON_DIR + file + ".png"
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	if texture == null:
		push_warning("Daily Missions icon file is missing: %s" % path)
		if file != ICON_FALLBACK and ResourceLoader.exists(ICON_DIR + ICON_FALLBACK + ".png"):
			texture = load(ICON_DIR + ICON_FALLBACK + ".png") as Texture2D
	_icon_textures[file] = texture
	return texture


static func format_countdown(seconds: int) -> String:
	var left := maxi(0, seconds)
	var hours := int(left / 3600)
	var minutes := int((left % 3600) / 60)
	var secs := int(left % 60)
	return "RESETS IN %02d:%02d:%02d" % [hours, minutes, secs]


static func _pick(date_key: String, tier: String, recent_ids: Array, used_families: Array) -> Dictionary:
	var enabled: Array = []
	var fresh: Array = []
	for mission in catalog():
		if str(mission.get("tier", "")) != tier or not bool(mission.get("enabled", false)):
			continue
		enabled.append(mission)
		if not recent_ids.has(int(mission.get("id", 0))):
			fresh.append(mission)
	var pool: Array = fresh if not fresh.is_empty() else enabled
	var preferred: Array = []
	for mission in pool:
		if not used_families.has(str(mission.get("family", ""))):
			preferred.append(mission)
	if not preferred.is_empty():
		pool = preferred
	if pool.is_empty():
		return {}
	var index := mission_index(date_key + "|" + tier, pool.size())
	return pool[index]


static func _count_at_least(samples: Array, threshold: int) -> int:
	var count := 0
	for value in samples:
		if int(value) >= threshold:
			count += 1
	return count


static func _window_sum(samples: Array, max_len: int) -> int:
	var count := samples.size()
	if count == 0 or max_len <= 0:
		return 0
	var best := 0
	var width := 1
	while width <= mini(max_len, count):
		var start := 0
		while start <= count - width:
			var total := 0
			for offset in width:
				total += int(samples[start + offset])
			if total > best:
				best = total
			start += 1
		width += 1
	return best


static func _build_catalog() -> Array:
	return [
		_m(1, "easy", "total_pipes", "Pass 10 pipes total.", 5, "pipes_total", 10, 0, true),
		_m(2, "easy", "total_pipes", "Pass 25 pipes total.", 5, "pipes_total", 25, 0, true),
		_m(3, "easy", "one_run_pipes", "Pass 10 pipes in one run.", 5, "pipes_best", 10, 0, true),
		_m(4, "easy", "run_count", "Complete 3 runs.", 5, "runs", 3, 0, true),
		_m(5, "easy", "run_count", "Complete 5 runs.", 5, "runs", 5, 0, true),
		_m(6, "easy", "one_run_pipes", "Reach checkpoint 5.", 5, "pipes_best", 5, 0, false),
		_m(7, "easy", "survive", "Survive 30 seconds in one run.", 5, "survive_best", 30, 0, true),
		_m(8, "easy", "earn_coins", "Earn 50 coins through normal gameplay.", 5, "coins_total", 50, 0, true),
		_m(9, "easy", "earn_coins", "Earn 100 coins through normal gameplay.", 5, "coins_total", 100, 0, true),
		_m(10, "easy", "coin_runs", "Collect coins in 3 separate runs.", 5, "coin_runs", 3, 0, true),
		_m(11, "easy", "multi_threshold", "Pass at least 5 pipes in 3 different runs.", 5, "runs_at_least", 5, 3, true),
		_m(12, "easy", "one_run_pipes", "Reach 5 pipes in one run.", 5, "pipes_best", 5, 0, true),
		_m(13, "easy", "one_run_pipes", "Reach 10 pipes in one run.", 5, "pipes_best", 10, 0, false),
		_m(14, "easy", "total_pipes", "Pass 15 pipes total.", 5, "pipes_total", 15, 0, true),
		_m(15, "easy", "multi_threshold", "Complete 2 runs with at least 5 pipes each.", 5, "runs_at_least", 5, 2, true),
		_m(16, "medium", "total_pipes", "Pass 50 pipes total.", 10, "pipes_total", 50, 0, true),
		_m(17, "medium", "total_pipes", "Pass 75 pipes total.", 10, "pipes_total", 75, 0, true),
		_m(18, "medium", "total_pipes", "Pass 100 pipes total.", 10, "pipes_total", 100, 0, true),
		_m(19, "medium", "one_run_pipes", "Pass 25 pipes in one run.", 10, "pipes_best", 25, 0, true),
		_m(20, "medium", "one_run_pipes", "Pass 40 pipes in one run.", 10, "pipes_best", 40, 0, true),
		_m(21, "medium", "run_count", "Complete 10 runs.", 10, "runs", 10, 0, true),
		_m(22, "medium", "run_count", "Complete 15 runs.", 10, "runs", 15, 0, true),
		_m(23, "medium", "one_run_pipes", "Reach checkpoint 10.", 10, "pipes_best", 10, 0, false),
		_m(24, "medium", "survive", "Survive 60 seconds in one run.", 10, "survive_best", 60, 0, true),
		_m(25, "medium", "survive", "Survive 90 seconds in one run.", 10, "survive_best", 90, 0, true),
		_m(26, "medium", "earn_coins", "Earn 250 coins through normal gameplay.", 10, "coins_total", 250, 0, true),
		_m(27, "medium", "coin_runs", "Collect coins in 5 separate runs.", 10, "coin_runs", 5, 0, true),
		_m(28, "medium", "multi_threshold", "Pass at least 10 pipes in 3 different runs.", 10, "runs_at_least", 10, 3, true),
		_m(29, "medium", "multi_threshold", "Reach 15 pipes in 2 different runs.", 10, "runs_at_least", 15, 2, true),
		_m(30, "medium", "window_sum", "Pass 50 pipes across no more than 3 runs.", 10, "window_sum", 50, 3, true),
		_m(31, "hard", "total_pipes", "Pass 150 pipes total.", 20, "pipes_total", 150, 0, true),
		_m(32, "hard", "total_pipes", "Pass 200 pipes total.", 20, "pipes_total", 200, 0, true),
		_m(33, "hard", "one_run_pipes", "Pass 50 pipes in one run.", 20, "pipes_best", 50, 0, true),
		_m(34, "hard", "one_run_pipes", "Pass 75 pipes in one run.", 20, "pipes_best", 75, 0, true),
		_m(35, "hard", "one_run_pipes", "Pass 100 pipes in one run.", 20, "pipes_best", 100, 0, false),
		_m(36, "hard", "one_run_pipes", "Pass 125 pipes in one run.", 20, "pipes_best", 125, 0, false),
		_m(37, "hard", "one_run_pipes", "Pass 150 pipes in one run.", 20, "pipes_best", 150, 0, false),
		_m(38, "hard", "run_count", "Complete 20 runs.", 20, "runs", 20, 0, true),
		_m(39, "hard", "one_run_pipes", "Reach checkpoint 20.", 20, "pipes_best", 20, 0, true),
		_m(40, "hard", "survive", "Survive 120 seconds in one run.", 20, "survive_best", 120, 0, true),
		_m(41, "hard", "survive", "Survive 180 seconds in one run.", 20, "survive_best", 180, 0, true),
		_m(42, "hard", "earn_coins", "Earn 500 coins through normal gameplay.", 20, "coins_total", 500, 0, true),
		_m(43, "hard", "multi_threshold", "Pass at least 20 pipes in 3 different runs.", 20, "runs_at_least", 20, 3, true),
		_m(44, "hard", "multi_threshold", "Reach 25 pipes in 2 different runs.", 20, "runs_at_least", 25, 2, true),
		_m(45, "hard", "window_sum", "Pass 100 pipes across no more than 5 runs.", 20, "window_sum", 100, 5, true),
		_m(46, "easy", "dive_enter", "Deep Diver: enter a dive.", 5, "dives_entered", 1, 0, true),
		_m(47, "easy", "dive_lanes", "First Splash: switch lanes 10 times.", 5, "lanes_total", 10, 0, true),
		_m(48, "easy", "dive_time", "Into the Abyss: spend 20 seconds diving.", 5, "dive_seconds", 20, 0, true),
		_m(49, "easy", "dive_left", "Side Stepper: move left 10 times.", 5, "lanes_left", 10, 0, true),
		_m(50, "easy", "dive_enter", "Deep Traveler: enter 2 dives.", 5, "dives_entered", 2, 0, true),
		_m(51, "easy", "dive_dodge", "Quick Fins: dodge 5 obstacles.", 5, "obstacles_total", 5, 0, true),
		_m(52, "easy", "dive_right", "Right Turn: move right 10 times.", 5, "lanes_right", 10, 0, true),
		_m(53, "easy", "dive_time", "Warm Up: spend 10 seconds diving.", 5, "dive_seconds", 10, 0, true),
		_m(54, "easy", "dive_dodge", "Light Dodge: dodge 3 obstacles.", 5, "obstacles_total", 3, 0, true),
		_m(55, "easy", "dive_complete", "Surface: finish a dive.", 5, "dives_completed", 1, 0, true),
		_m(56, "easy", "dive_lanes", "Little Nudge: switch lanes 5 times.", 5, "lanes_total", 5, 0, true),
		_m(57, "easy", "dive_left", "Port Side: move left 5 times.", 5, "lanes_left", 5, 0, true),
		_m(58, "easy", "dive_right", "Starboard: move right 5 times.", 5, "lanes_right", 5, 0, true),
		_m(59, "easy", "dive_dodge", "Clear Path: dodge 8 obstacles.", 5, "obstacles_total", 8, 0, true),
		_m(60, "easy", "dive_time", "Hold Breath: spend 15 seconds diving.", 5, "dive_seconds", 15, 0, true),
		_m(61, "medium", "dive_dodge", "Close Call: dodge 15 obstacles.", 10, "obstacles_total", 15, 0, true),
		_m(62, "medium", "dive_enter", "Deep Explorer: enter 3 dives.", 10, "dives_entered", 3, 0, true),
		_m(63, "medium", "dive_dodge", "Slippery Fish: dodge 30 obstacles.", 10, "obstacles_total", 30, 0, true),
		_m(64, "medium", "dive_lanes", "Ocean Navigator: switch lanes 30 times.", 10, "lanes_total", 30, 0, true),
		_m(65, "medium", "dive_complete", "Deep Survivor: finish 2 dives.", 10, "dives_completed", 2, 0, true),
		_m(66, "medium", "dive_mines", "Mine Dodger: pass 5 mines.", 10, "mines_total", 5, 0, true),
		_m(67, "medium", "dive_time", "Deep Breath: spend 40 seconds diving.", 10, "dive_seconds", 40, 0, true),
		_m(68, "medium", "dive_left", "Left Current: move left 20 times.", 10, "lanes_left", 20, 0, true),
		_m(69, "medium", "dive_right", "Right Current: move right 20 times.", 10, "lanes_right", 20, 0, true),
		_m(70, "medium", "dive_enter", "Return Trip: enter 4 dives.", 10, "dives_entered", 4, 0, true),
		_m(71, "medium", "dive_dodge", "Steady Weave: dodge 20 obstacles.", 10, "obstacles_total", 20, 0, true),
		_m(72, "medium", "dive_mines", "Mine Watch: pass 3 mines.", 10, "mines_total", 3, 0, true),
		_m(73, "medium", "dive_lanes", "Lane Hopper: switch lanes 20 times.", 10, "lanes_total", 20, 0, true),
		_m(74, "medium", "dive_time", "One Minute: spend 60 seconds diving.", 10, "dive_seconds", 60, 0, true),
		_m(75, "medium", "dive_mines", "Mine Line: pass 8 mines.", 10, "mines_total", 8, 0, true),
		_m(76, "hard", "dive_complete", "Survivor of the Deep: finish 3 dives.", 20, "dives_completed", 3, 0, true),
		_m(77, "hard", "dive_complete", "Depth Master: finish 4 dives.", 20, "dives_completed", 4, 0, true),
		_m(78, "hard", "dive_one_run", "Untouchable: finish 2 dives in one run.", 20, "dives_best", 2, 0, true),
		_m(79, "hard", "dive_dodge", "Danger Below: dodge 60 obstacles.", 20, "obstacles_total", 60, 0, true),
		_m(80, "hard", "dive_lanes", "Master Navigator: switch lanes 75 times.", 20, "lanes_total", 75, 0, true),
		_m(81, "hard", "dive_mines", "Minefield Expert: pass 15 mines.", 20, "mines_total", 15, 0, true),
		_m(82, "hard", "dive_dodge", "Wide Berth: dodge 45 obstacles.", 20, "obstacles_total", 45, 0, true),
		_m(83, "hard", "dive_lanes", "Swift Fins: switch lanes 50 times.", 20, "lanes_total", 50, 0, true),
		_m(84, "hard", "dive_mines", "Mine Course: pass 10 mines.", 20, "mines_total", 10, 0, true),
		_m(85, "hard", "dive_time", "Stay Down: spend 80 seconds diving.", 20, "dive_seconds", 80, 0, true),
		_m(86, "hard", "dive_left", "Port Master: move left 35 times.", 20, "lanes_left", 35, 0, true),
		_m(87, "hard", "dive_right", "Starboard Master: move right 35 times.", 20, "lanes_right", 35, 0, true),
		_m(88, "hard", "dive_enter", "Frequent Diver: enter 6 dives.", 20, "dives_entered", 6, 0, true),
		_m(89, "hard", "dive_dodge", "Full Course: dodge 18 obstacles in one run.", 20, "obstacles_best", 18, 0, true),
		_m(90, "hard", "dive_enter", "Five Down: enter 5 dives.", 20, "dives_entered", 5, 0, true),
	]


static func _m(id: int, tier: String, family: String, description: String, reward: int, rule: String, goal: int, goal_b: int, enabled: bool) -> Dictionary:
	return {
		"id": id,
		"tier": tier,
		"family": family,
		"description": description,
		"reward": reward,
		"rule": rule,
		"goal": goal,
		"goal_b": goal_b,
		"enabled": enabled,
	}
