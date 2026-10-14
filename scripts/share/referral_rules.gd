class_name ReferralRules
extends RefCounted

# Pure referral rules. The Supabase functions in tools/supabase/share_rewards.sql
# are the authority. This mirror is what the headless tests exercise.
# The client never sends a referral count or a coin balance.

const REWARD_COINS := 100
const TARGET := 3
const SHARE_ORIGIN := "https://lunarent.gg/?ref="
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


static func normalize_code(raw: String) -> String:
	var out := ""
	var upper := raw.strip_edges().to_upper()
	for i in upper.length():
		var ch := upper.substr(i, 1)
		var letter := (ch >= "A" and ch <= "Z")
		var digit := (ch >= "0" and ch <= "9")
		if not letter and not digit:
			continue
		out += ch
		if out.length() >= 16:
			break
	return out


static func parse_ref(raw: String) -> String:
	var text := raw.strip_edges()
	if text.is_empty():
		return ""
	var lower := text.to_lower()
	var slash := lower.find("://ref/")
	if slash >= 0:
		var deep := text.substr(slash + 7)
		var stop := _cut_token(deep)
		return normalize_code(stop.uri_decode())
	var key := "ref="
	var at := lower.find(key)
	if at < 0:
		return ""
	var value := text.substr(at + key.length())
	value = _cut_token(value)
	return normalize_code(value.uri_decode())


static func from_arg(arg: String) -> String:
	var text := arg.strip_edges()
	if text.begins_with("--ref="):
		return normalize_code(text.substr(6).uri_decode())
	if text.to_lower().find("ref=") >= 0 or text.to_lower().find("://ref/") >= 0:
		return parse_ref(text)
	return ""


static func share_url(code: String) -> String:
	var clean := normalize_code(code)
	if clean.is_empty():
		return ""
	return SHARE_ORIGIN + clean


static func share_message(code: String) -> String:
	var url := share_url(code)
	if url.is_empty():
		return ""
	return "Swim with me in ReefRun! " + url


static func progress_label(qualified: int) -> String:
	return "FRIENDS %d/%d" % [clampi(qualified, 0, TARGET), TARGET]


static func rewards_change_on_share(_status: String) -> bool:
	return false


static func sync_body(code: String, completed: bool) -> Dictionary:
	return {
		"p_code": normalize_code(code),
		"p_run_completed": completed,
	}


static func coin_delta(applied: int, granted: int) -> int:
	var cap := clampi(granted, 0, REWARD_COINS)
	var have := clampi(applied, 0, REWARD_COINS)
	return maxi(0, cap - have)


static func clear_pending_code(http_status: int, attach: String) -> bool:
	if attach.is_empty() or attach == "skipped":
		return false
	if http_status == 0 or http_status >= 500:
		return false
	return (
		attach == "attached"
		or attach == "already_attached"
		or attach == "self"
		or attach == "unknown"
		or attach == "already_played"
		or attach == "empty"
	)


static func parse_status(data: Variant) -> Dictionary:
	var row: Dictionary = {}
	if typeof(data) == TYPE_DICTIONARY:
		row = data
	elif typeof(data) == TYPE_STRING:
		var parsed: Variant = JSON.parse_string(str(data))
		if typeof(parsed) == TYPE_DICTIONARY:
			row = parsed
	return {
		"code": normalize_code(str(row.get("code", ""))),
		"qualified": clampi(int(row.get("qualified", 0)), 0, TARGET),
		"granted_coins": clampi(int(row.get("granted_coins", 0)), 0, REWARD_COINS),
		"first_run": bool(row.get("first_run", false)),
		"attach": str(row.get("attach", "")),
	}


static func fresh_store() -> Dictionary:
	return {
		"profiles": {},
		"referrals": {},
		"grants": {},
		"seq": 0,
	}


static func ensure_code(store: Dictionary, player_id: String) -> String:
	var profile := _profile(store, player_id)
	if str(profile["code"]) != "":
		return str(profile["code"])
	var n := int(store.get("seq", 0)) + 1
	store["seq"] = n
	profile["code"] = _code_from_int(n)
	return str(profile["code"])


static func sync(store: Dictionary, player_id: String, code: String, completed: bool, _client_qualified := -1) -> Dictionary:
	ensure_code(store, player_id)
	var attach := "skipped"
	if normalize_code(code) != "":
		attach = _attach(store, player_id, code)
	if completed:
		_complete(store, player_id)
	var row := _status_row(store, player_id)
	row["ok"] = true
	row["attach"] = attach
	return row


static func status_of(store: Dictionary, player_id: String) -> Dictionary:
	ensure_code(store, player_id)
	var row := _status_row(store, player_id)
	row["ok"] = true
	row["attach"] = "skipped"
	return row


static func _attach(store: Dictionary, player_id: String, code: String) -> String:
	var clean := normalize_code(code)
	if clean.is_empty():
		return "empty"
	var referrer_id := ""
	var profiles: Dictionary = store["profiles"]
	for id in profiles.keys():
		var row: Dictionary = profiles[id]
		if str(row.get("code", "")) == clean:
			referrer_id = str(id)
			break
	if referrer_id.is_empty():
		return "unknown"
	if referrer_id == player_id:
		return "self"
	var profile := _profile(store, player_id)
	if bool(profile["first_run"]):
		return "already_played"
	var referrals: Dictionary = store["referrals"]
	if referrals.has(player_id):
		return "already_attached"
	referrals[player_id] = {"referrer": referrer_id, "qualified": false}
	return "attached"


static func _complete(store: Dictionary, player_id: String) -> void:
	var profile := _profile(store, player_id)
	if bool(profile["first_run"]):
		return
	profile["first_run"] = true
	var referrals: Dictionary = store["referrals"]
	if not referrals.has(player_id):
		return
	var link: Dictionary = referrals[player_id]
	if bool(link.get("qualified", false)):
		return
	link["qualified"] = true
	var referrer_id := str(link.get("referrer", ""))
	var count := 0
	for id in referrals.keys():
		var item: Dictionary = referrals[id]
		if str(item.get("referrer", "")) == referrer_id and bool(item.get("qualified", false)):
			count += 1
	if count < TARGET:
		return
	var grants: Dictionary = store["grants"]
	if not grants.has(referrer_id):
		grants[referrer_id] = REWARD_COINS
	var referrer := _profile(store, referrer_id)
	if int(referrer["share_reward_coins"]) != 0:
		return
	referrer["coins"] = int(referrer["coins"]) + REWARD_COINS
	referrer["share_reward_coins"] = REWARD_COINS


static func _status_row(store: Dictionary, player_id: String) -> Dictionary:
	var profile := _profile(store, player_id)
	var count := 0
	var referrals: Dictionary = store["referrals"]
	for id in referrals.keys():
		var item: Dictionary = referrals[id]
		if str(item.get("referrer", "")) == player_id and bool(item.get("qualified", false)):
			count += 1
	return {
		"code": str(profile["code"]),
		"qualified": count,
		"target": TARGET,
		"reward_coins": REWARD_COINS,
		"granted_coins": int(profile["share_reward_coins"]),
		"first_run": bool(profile["first_run"]),
	}


static func _profile(store: Dictionary, player_id: String) -> Dictionary:
	var profiles: Dictionary = store["profiles"]
	if not profiles.has(player_id):
		profiles[player_id] = {
			"code": "",
			"first_run": false,
			"coins": 0,
			"share_reward_coins": 0,
		}
	return profiles[player_id]


static func _code_from_int(n: int) -> String:
	var value := maxi(n, 1)
	var chars := ""
	for _i in 8:
		chars = ALPHABET.substr(value % 32, 1) + chars
		value = int(value / 32)
	return chars


static func _cut_token(value: String) -> String:
	var cut := value
	for sep in ["&", "#", "/", " "]:
		var at := cut.find(sep)
		if at >= 0:
			cut = cut.substr(0, at)
	return cut
