class_name DailyMissions
extends RefCounted

# Live mission selection happens only in tools/supabase/daily_missions.sql.
# preview_rotation() mirrors that algorithm for tests. The game never uses it
# to decide which missions a player receives.

const MAX_DAILY_REWARD := 60
const MAX_PIPES_PER_RUN := 80
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


static func accept_run(pipes: int, seconds: int, coins: int) -> bool:
	if pipes < 0 or pipes > MAX_PIPES_PER_RUN:
		return false
	if seconds < 0 or seconds > 1800:
		return false
	if coins < 0 or coins > int(pipes / 5.0):
		return false
	if pipes > 0 and seconds < pipes - 1:
		return false
	# Matches record_unlimited_mission_run:
	# floor(1.8 + pipes * 1.5 + 12 + 12 * (pipes / 20)).
	var harpoon_slack: int = 12 * int(pipes / 20)
	var survival_limit: int = int(floorf(1.8 + float(pipes) * 1.5 + 12.0 + float(harpoon_slack)))
	if pipes < MAX_PIPES_PER_RUN and seconds > survival_limit:
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


static func enqueue(pending: Array, run_id: String, pipes: int, seconds: int, coins: int) -> Array:
	if not valid_run_id(run_id) or not accept_run(pipes, seconds, coins):
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


static func display_text(description: String) -> String:
	var text := description.strip_edges()
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text


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
		"multi_threshold", "window_sum":
			return "medal"
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
