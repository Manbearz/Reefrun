class_name DailyChallenge
extends RefCounted

# One global course per Eastern date (America/New_York). The daily resets at
# midnight Eastern, including the daylight-saving shift. The seed is a pure
# function of that date and the course version, so every client that agrees on
# the date builds the same reef. Leaderboard awards still require a
# server-confirmed challenge. A matching seed is not proof that a run is legitimate.

const NAMESPACE := "reefrun.daily.v1"
const SUBMIT_GRACE_SEC := 20 * 60
const GHOST_CACHE_TTL_SEC := 180

static func challenge_id(utc_date: String, course_version: int, physics_version: int) -> String:
	return "daily:%s:cv%d:pv%d" % [utc_date, course_version, physics_version]


static func derive_seed(utc_date: String, course_version: int = -1) -> int:
	if course_version < 0:
		course_version = RR.COURSE_VERSION
	return _fnv1a32("%s|%s|cv%d" % [NAMESPACE, utc_date, course_version])


static func make(utc_date: String, server_confirmed: bool = false, as_of_unix: int = 0) -> Dictionary:
	var course_version := RR.COURSE_VERSION
	var physics_version := RR.PHYSICS_VERSION
	return {
		"challenge_id": challenge_id(utc_date, course_version, physics_version),
		"challenge_date": utc_date,
		"course_seed": derive_seed(utc_date, course_version),
		"course_version": course_version,
		"physics_version": physics_version,
		"server_confirmed": server_confirmed,
		"as_of_unix": as_of_unix,
	}


static func from_server(data: Variant) -> Dictionary:
	var row := _first_row(data)
	if row.is_empty():
		return {}
	var date := str(row.get("challenge_date", "")).substr(0, 10)
	var course_version := int(row.get("course_version", 0))
	var physics_version := int(row.get("physics_version", 0))
	var seed := int(row.get("course_seed", 0))
	var cid := str(row.get("challenge_id", ""))
	if not _date_ok(date):
		return {}
	if course_version != RR.COURSE_VERSION or physics_version != RR.PHYSICS_VERSION:
		return {}
	if cid != challenge_id(date, course_version, physics_version):
		return {}
	if seed != derive_seed(date, course_version):
		return {}
	return {
		"challenge_id": cid,
		"challenge_date": date,
		"course_seed": seed,
		"course_version": course_version,
		"physics_version": physics_version,
		"server_confirmed": true,
		"as_of_unix": unix_from_variant(row.get("as_of", 0)),
	}


static func unverified_for_date(utc_date: String) -> Dictionary:
	if not _date_ok(utc_date):
		return {}
	return make(utc_date, false, 0)


static func unverified_local(unix_time: int) -> Dictionary:
	return unverified_for_date(challenge_date_from_unix(unix_time))


static func challenge_from_fetch(ok: bool, payload: Variant, now_local_unix: int) -> Dictionary:
	if ok:
		var parsed := from_server(payload)
		if not parsed.is_empty():
			return parsed
	return unverified_local(now_local_unix)


static func may_submit(challenge: Dictionary) -> bool:
	return (
		bool(challenge.get("server_confirmed", false))
		and str(challenge.get("challenge_id", "")) != ""
		and int(challenge.get("course_seed", 0)) != 0
		and int(challenge.get("course_version", -1)) == RR.COURSE_VERSION
		and int(challenge.get("physics_version", -1)) == RR.PHYSICS_VERSION
		and _date_ok(str(challenge.get("challenge_date", "")))
	)


static func hold(locked: Dictionary, newer: Dictionary) -> Dictionary:
	if int(locked.get("course_seed", 0)) == 0:
		return newer.duplicate(true)
	return locked.duplicate(true)


static func cache_key(challenge: Dictionary) -> String:
	return "%s|cv%d|pv%d" % [
		str(challenge.get("challenge_id", "")),
		int(challenge.get("course_version", 0)),
		int(challenge.get("physics_version", 0)),
	]


static func remember_ghosts(cache: Dictionary, key: String, rows: Array, fetched_unix: int) -> void:
	cache[key] = {"rows": rows, "fetched_unix": fetched_unix}


static func ghost_cache_fresh(cache: Dictionary, key: String, now_unix: int, ttl: int = GHOST_CACHE_TTL_SEC) -> bool:
	if not cache.has(key) or typeof(cache[key]) != TYPE_DICTIONARY:
		return false
	var entry: Dictionary = cache[key]
	if not (entry.get("rows", []) is Array):
		return false
	var age := now_unix - int(entry.get("fetched_unix", 0))
	return age >= 0 and age <= ttl


static func should_download_ghosts(cache: Dictionary, key: String, now_unix: int, ttl: int = GHOST_CACHE_TTL_SEC) -> bool:
	return not ghost_cache_fresh(cache, key, now_unix, ttl)


static func cached_rows(cache: Dictionary, key: String, now_unix: int, ttl: int = GHOST_CACHE_TTL_SEC) -> Array:
	if not ghost_cache_fresh(cache, key, now_unix, ttl):
		return []
	return cache[key]["rows"]


static func estimated_server_unix(as_of_unix: int, fetched_local_unix: int, now_local_unix: int) -> int:
	if as_of_unix <= 0:
		return 0
	return as_of_unix + (now_local_unix - fetched_local_unix)


static func choose_for_new_match(cached: Dictionary, as_of_unix: int, fetched_local_unix: int, now_local_unix: int) -> Dictionary:
	var estimated := estimated_server_unix(as_of_unix, fetched_local_unix, now_local_unix)
	var estimated_date := challenge_date_from_unix(estimated) if estimated > 0 else ""
	if may_submit(cached):
		var cached_date := str(cached.get("challenge_date", ""))
		if estimated_date == "" or estimated_date == cached_date:
			return cached.duplicate(true)
		if estimated_date != "":
			return unverified_for_date(estimated_date)
	if estimated_date != "":
		return unverified_for_date(estimated_date)
	return unverified_local(now_local_unix)


static func utc_date_from_unix(unix_time: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d" % [int(dt.year), int(dt.month), int(dt.day)]


# Calendar date in America/New_York. US DST: second Sunday in March at 2:00am
# Eastern, through first Sunday in November at 2:00am Eastern.
static func challenge_date_from_unix(unix_time: int) -> String:
	var shifted := unix_time + _eastern_offset_seconds(unix_time)
	var dt := Time.get_datetime_dict_from_unix_time(shifted)
	return "%04d-%02d-%02d" % [int(dt.year), int(dt.month), int(dt.day)]


static func eastern_midnight_unix(year: int, month: int, day: int) -> int:
	var hour := 4 if _eastern_daylight_on_date(year, month, day) else 5
	return unix_utc(year, month, day, hour)


static func unix_utc(year: int, month: int, day: int, hour: int = 0, minute: int = 0, second: int = 0) -> int:
	return int(Time.get_unix_time_from_datetime_dict({
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": minute,
		"second": second,
	}))


static func period_keys_for_date(utc_date: String) -> Dictionary:
	return {
		"daily": utc_date,
		"weekly": week_key(utc_date),
		"monthly": utc_date.substr(0, 7),
	}


static func week_key(utc_date: String) -> String:
	var parts := utc_date.split("-")
	if parts.size() != 3:
		return ""
	var unix := unix_utc(int(parts[0]), int(parts[1]), int(parts[2]), 12)
	var dt := Time.get_datetime_dict_from_unix_time(unix)
	var back := (int(dt.weekday) + 6) % 7
	var monday := Time.get_datetime_dict_from_unix_time(unix - back * 86400)
	return "%04d-%02d-%02d" % [int(monday.year), int(monday.month), int(monday.day)]


static func eligible(utc_date: String, server_unix: int) -> bool:
	if not _date_ok(utc_date):
		return false
	var year := int(utc_date.substr(0, 4))
	var month := int(utc_date.substr(5, 2))
	var day := int(utc_date.substr(8, 2))
	var start := eastern_midnight_unix(year, month, day)
	var next := Time.get_datetime_dict_from_unix_time(unix_utc(year, month, day, 12) + 86400)
	var end := eastern_midnight_unix(int(next.year), int(next.month), int(next.day)) + SUBMIT_GRACE_SEC
	return server_unix >= start and server_unix < end


static func ghost_compatible(run, challenge: Dictionary) -> bool:
	if run == null or str(challenge.get("challenge_id", "")) == "":
		return run != null
	return (
		str(run.challenge_id) == str(challenge.get("challenge_id", ""))
		and int(run.course_seed) == int(challenge.get("course_seed", 0))
		and int(run.course_version) == int(challenge.get("course_version", -1))
		and int(run.physics_version) == int(challenge.get("physics_version", -1))
	)


static func empty_book() -> Dictionary:
	return {"rows": []}


static func submit_score(book: Dictionary, player_id: String, display_name: String, score: int, challenge: Dictionary, server_unix: int) -> bool:
	if score <= 0 or player_id == "":
		return false
	if not may_submit(challenge):
		return false
	var date := str(challenge.get("challenge_date", ""))
	if not eligible(date, server_unix):
		return false
	var name := display_name.strip_edges().substr(0, 7)
	if name.is_empty():
		name = "YOU"
	var keys := period_keys_for_date(date)
	var cid := str(challenge.get("challenge_id", ""))
	_upsert_row(book, player_id, name, score, "daily", str(keys["daily"]), cid, server_unix)
	return true


static func submit_unlimited(book: Dictionary, player_id: String, display_name: String, score: int, server_unix: int) -> bool:
	if score <= 0 or player_id == "":
		return false
	var date := utc_date_from_unix(server_unix)
	if not _date_ok(date):
		return false
	var name := display_name.strip_edges().substr(0, 7)
	if name.is_empty():
		name = "YOU"
	var keys := period_keys_for_date(date)
	for period in ["weekly", "monthly"]:
		_upsert_row(book, player_id, name, score, period, str(keys[period]), "", server_unix)
	return true


static func visible_board(book: Dictionary, period: String, server_unix: int) -> Array:
	var today := challenge_date_from_unix(server_unix) if period == "daily" else utc_date_from_unix(server_unix)
	var key := str(period_keys_for_date(today).get(period, ""))
	var rows: Array = []
	for row in book.get("rows", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("period", "")) != period or str(row.get("period_key", "")) != key:
			continue
		var cid := str(row.get("challenge_id", ""))
		if period == "daily" and cid == "":
			continue
		if (period == "weekly" or period == "monthly") and cid != "":
			continue
		if int(row.get("score", 0)) <= 0:
			continue
		rows.append({
			"name": str(row.get("display_name", "")),
			"display_name": str(row.get("display_name", "")),
			"score": int(row.get("score", 0)),
			"created_at": int(row.get("created_at", 0)),
			"player_id": str(row.get("player_id", "")),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("score", 0)) != int(b.get("score", 0)):
			return int(a.get("score", 0)) > int(b.get("score", 0))
		return int(a.get("created_at", 0)) < int(b.get("created_at", 0))
	)
	if rows.size() > 10:
		rows.resize(10)
	return rows


static func row_count(book: Dictionary, player_id: String, period: String) -> int:
	var n := 0
	for row in book.get("rows", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("player_id", "")) == player_id and str(row.get("period", "")) == period:
			n += 1
	return n


static func unix_from_variant(value: Variant) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	var text := str(value).strip_edges()
	if text.is_empty():
		return 0
	return int(Time.get_unix_time_from_datetime_string(text))


static func _upsert_row(book: Dictionary, player_id: String, display_name: String, score: int, period: String, period_key: String, cid: String, server_unix: int) -> void:
	var rows: Array = book["rows"]
	for row in rows:
		if str(row.get("player_id", "")) != player_id:
			continue
		if str(row.get("period", "")) != period or str(row.get("period_key", "")) != period_key:
			continue
		if (str(row.get("challenge_id", "")) != "") != (cid != ""):
			continue
		if score > int(row.get("score", 0)):
			row["score"] = score
			row["display_name"] = display_name
			row["challenge_id"] = cid
		return
	rows.append({
		"player_id": player_id,
		"display_name": display_name,
		"score": score,
		"period": period,
		"period_key": period_key,
		"challenge_id": cid,
		"created_at": server_unix,
	})


static func _first_row(data: Variant) -> Dictionary:
	if data is Array and not data.is_empty() and typeof(data[0]) == TYPE_DICTIONARY:
		return data[0]
	if typeof(data) == TYPE_DICTIONARY:
		return data
	return {}


static func _eastern_offset_seconds(unix_time: int) -> int:
	var year := int(Time.get_datetime_dict_from_unix_time(unix_time).year)
	var start := unix_utc(year, 3, _nth_sunday(year, 3, 2), 7)
	var end := unix_utc(year, 11, _nth_sunday(year, 11, 1), 6)
	if unix_time >= start and unix_time < end:
		return -4 * 3600
	return -5 * 3600


static func _eastern_daylight_on_date(year: int, month: int, day: int) -> bool:
	# Midnight starting the spring-forward Sunday is still standard time.
	# Midnight starting the fall-back Sunday is still daylight time.
	var spring := _date_index(year, 3, _nth_sunday(year, 3, 2))
	var fall := _date_index(year, 11, _nth_sunday(year, 11, 1))
	var today := _date_index(year, month, day)
	return today > spring and today <= fall


static func _nth_sunday(year: int, month: int, n: int) -> int:
	var first := Time.get_datetime_dict_from_unix_time(unix_utc(year, month, 1, 12))
	var weekday := int(first.weekday)
	return 1 + ((7 - weekday) % 7) + (n - 1) * 7


static func _date_index(year: int, month: int, day: int) -> int:
	return year * 10000 + month * 100 + day


static func _date_ok(utc_date: String) -> bool:
	if utc_date.length() != 10 or utc_date.substr(4, 1) != "-" or utc_date.substr(7, 1) != "-":
		return false
	var year := int(utc_date.substr(0, 4))
	var month := int(utc_date.substr(5, 2))
	var day := int(utc_date.substr(8, 2))
	if year < 2020 or month < 1 or month > 12 or day < 1 or day > 31:
		return false
	var back := Time.get_datetime_dict_from_unix_time(unix_utc(year, month, day))
	return int(back.year) == year and int(back.month) == month and int(back.day) == day


static func _fnv1a32(text: String) -> int:
	var hash := 2166136261
	var bytes := text.to_utf8_buffer()
	for i in bytes.size():
		hash = (hash ^ int(bytes[i])) & 0xFFFFFFFF
		hash = (hash * 16777619) & 0xFFFFFFFF
	hash = hash & 0x7FFFFFFF
	if hash == 0:
		hash = 1
	return hash
