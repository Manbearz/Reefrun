class_name DailyAttempt
extends RefCounted

# Server claim rules, mirrored here so tests can exercise them without Supabase.
# The live game trusts claim_daily_attempt / finalize_daily_attempt, not this store.
# A matching course seed is not proof that a score is legitimate.
# Each player gets three separate runs per Eastern day. Starting a run consumes
# one. The leaderboard keeps only the highest finalized score.

const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")
const COMPLETED_LABEL := "COMPLETED - COME BACK TOMORROW"
const WAITING_LABEL := "CONNECTING"
const ATTEMPT_LIMIT := 3


static func attempt_required(mode: String) -> bool:
	return mode == "daily"


static func should_finalize(mode: String, attempt_id: String) -> bool:
	return mode == "daily" and attempt_id.strip_edges() != ""


# A dropped response or a 5xx may have inserted the claim. Keep the same key
# and retry. A 4xx, including a missing RPC, did not create a server row.
static func keep_claim_key(http_status: int) -> bool:
	return http_status == 0 or http_status >= 500


static func new_idempotency_key() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]


static func reset_label(resets_unix: int, now_unix: int) -> String:
	if resets_unix <= 0:
		return "RESETS AT MIDNIGHT"
	var left := maxi(0, resets_unix - now_unix)
	var hours := int(left / 3600.0)
	var minutes := int(int(left) % 3600 / 60.0)
	return "RESETS IN %dH %dM" % [hours, minutes]


static func empty_store() -> Dictionary:
	return {"attempts": []}


static func status_of(store: Dictionary, player_id: String, challenge: Dictionary, idempotency_key: String = "") -> Dictionary:
	var cid := str(challenge.get("challenge_id", ""))
	var mine := _rows_for(store, player_id, cid)
	var used := _started_count(mine)
	var pending := _pending_row(mine)
	var recoverable := (
		not pending.is_empty()
		and idempotency_key != ""
		and str(pending.get("idempotency_key", "")) == idempotency_key
	)
	var remaining := maxi(0, ATTEMPT_LIMIT - used)
	return {
		# attempted stays true after the first start so an older client, which
		# locks on that flag, still stops at one run. The new client uses
		# attempts_remaining.
		"attempted": used >= 1 and not recoverable,
		"recoverable": recoverable,
		"attempt_count": _attempts(store).size(),
		"attempts_used": used,
		"attempts_remaining": remaining,
		"best_score": _best_score(mine),
	}


static func claim(store: Dictionary, player_id: String, idempotency_key: String, server_challenge: Dictionary, _client_date: String = "") -> Dictionary:
	var cid := str(server_challenge.get("challenge_id", ""))
	var mine := _rows_for(store, player_id, cid)
	var used := _started_count(mine)
	var remaining := maxi(0, ATTEMPT_LIMIT - used)
	var same := _find_key(mine, idempotency_key)
	if not same.is_empty():
		var open_claim := not bool(same.get("started", false)) and not bool(same.get("finalized", false))
		return {
			"claimed": open_claim,
			"already_used": not open_claim,
			"idempotent_replay": true,
			"finalized": bool(same.get("finalized", false)),
			"attempt_id": str(same.get("attempt_id", "")) if open_claim else "",
			"challenge_id": cid,
			"attempt_count": _attempts(store).size(),
			"attempts_used": used,
			"attempts_remaining": remaining,
			"best_score": _best_score(mine),
		}
	if used >= ATTEMPT_LIMIT:
		return {
			"claimed": false,
			"already_used": true,
			"idempotent_replay": false,
			"finalized": false,
			"attempt_id": "",
			"challenge_id": cid,
			"attempt_count": _attempts(store).size(),
			"attempts_used": used,
			"attempts_remaining": 0,
			"best_score": _best_score(mine),
		}
	# An unstarted claim has not been consumed. A new key continues that row
	# instead of stacking a second reservation.
	var pending := _pending_row(mine)
	if not pending.is_empty():
		pending["idempotency_key"] = idempotency_key
		return {
			"claimed": true,
			"already_used": false,
			"idempotent_replay": false,
			"finalized": false,
			"attempt_id": str(pending.get("attempt_id", "")),
			"challenge_id": cid,
			"attempt_count": _attempts(store).size(),
			"attempts_used": used,
			"attempts_remaining": remaining,
			"best_score": _best_score(mine),
		}
	var created := {
		"attempt_id": "attempt-%d" % _attempts(store).size(),
		"player_id": player_id,
		"challenge_id": cid,
		"idempotency_key": idempotency_key,
		"score": null,
		"started": false,
		"finalized": false,
	}
	_attempts(store).append(created)
	return {
		"claimed": true,
		"already_used": false,
		"idempotent_replay": false,
		"finalized": false,
		"attempt_id": str(created.get("attempt_id", "")),
		"challenge_id": cid,
		"attempt_count": _attempts(store).size(),
		"attempts_used": used,
		"attempts_remaining": remaining,
		"best_score": _best_score(mine),
	}


static func start(store: Dictionary, player_id: String, attempt_id: String) -> Dictionary:
	var row := _find_attempt(store, player_id, attempt_id)
	if row.is_empty():
		return {"ok": false, "started": false, "already_started": false, "error": "attempt_not_found", "attempts_used": 0, "attempts_remaining": 0}
	var mine := _rows_for(store, player_id, str(row.get("challenge_id", "")))
	var used := _started_count(mine)
	if bool(row.get("started", false)) or bool(row.get("finalized", false)):
		return {
			"ok": true,
			"started": false,
			"already_started": true,
			"attempts_used": used,
			"attempts_remaining": maxi(0, ATTEMPT_LIMIT - used),
		}
	if used >= ATTEMPT_LIMIT:
		return {
			"ok": false,
			"started": false,
			"already_started": false,
			"error": "attempt_limit",
			"attempts_used": used,
			"attempts_remaining": 0,
		}
	row["started"] = true
	used += 1
	return {
		"ok": true,
		"started": true,
		"already_started": false,
		"attempts_used": used,
		"attempts_remaining": maxi(0, ATTEMPT_LIMIT - used),
	}


# A dropped start response can be retried inside the same call. That retry may
# see already_started because the first request landed. Gameplay has not begun,
# so this call may enter the one run. A later call that did not lose a response
# stays blocked and does not open a second run.
static func start_attempt_uncertain(saw_uncertain: bool, result: Dictionary) -> bool:
	if saw_uncertain or bool(result.get("retried_after_transport", false)):
		return true
	var status := int(result.get("status", 0))
	return status == 0 or status >= 500


static func recover_lost_start(saw_uncertain: bool, parsed: Dictionary) -> Dictionary:
	if (
		saw_uncertain
		and bool(parsed.get("already_started", false))
		and not bool(parsed.get("started", false))
	):
		var out := parsed.duplicate(true)
		out["started"] = true
		out["already_started"] = false
		return out
	return parsed


static func finalize(store: Dictionary, book: Dictionary, player_id: String, attempt_id: String, score: int, display_name: String, server_unix: int) -> Dictionary:
	var row := _find_attempt(store, player_id, attempt_id)
	if row.is_empty():
		return {"ok": false, "accepted": false, "duplicate": false, "score": 0, "best_score": 0, "error": "attempt_not_found"}
	var cid := str(row.get("challenge_id", ""))
	if bool(row.get("finalized", false)):
		return {
			"ok": true,
			"accepted": false,
			"duplicate": true,
			"score": int(row.get("score", 0)),
			"best_score": _board_best(book, player_id, cid),
			"stored": true,
		}
	if not bool(row.get("started", false)):
		return {"ok": false, "accepted": false, "duplicate": false, "score": 0, "best_score": 0, "error": "attempt_not_started"}
	if score < 0:
		return {"ok": false, "accepted": false, "duplicate": false, "score": 0, "best_score": 0, "error": "invalid_score"}
	row["score"] = score
	row["finalized"] = true
	if score > 0:
		_write_periods(book, player_id, display_name, score, cid, server_unix)
	return {
		"ok": true,
		"accepted": true,
		"duplicate": false,
		"score": score,
		"best_score": _board_best(book, player_id, cid),
		"stored": true,
	}


static func parse_claim(result: Dictionary) -> Dictionary:
	var out := {
		"ok": false,
		"already_used": false,
		"cancelled": false,
		"idempotent_replay": false,
		"status": int(result.get("status", 0)),
		"challenge": {},
		"resets_at_unix": 0,
		"error": str(result.get("error", "")),
	}
	if not bool(result.get("ok", false)):
		return out
	var row := _first(result.get("data", null))
	if row.is_empty():
		out.error = "empty_payload"
		return out
	out.resets_at_unix = _unix(row, "resets_unix", "resets_at")
	out.already_used = _flag(row, "already_used")
	out.idempotent_replay = _flag(row, "idempotent_replay")
	_copy_attempt_counts(row, out)
	if _flag(row, "finalized"):
		out.already_used = true
		out.error = "already_finalized"
		return out
	var challenge: Dictionary = DailyChallengeScript.from_server(row)
	var attempt_id := _text(row.get("attempt_id", ""))
	if challenge.is_empty() or not _flag(row, "claimed") or attempt_id == "":
		if out.already_used:
			return out
		out.error = "challenge_mismatch" if challenge.is_empty() else "not_claimed"
		return out
	var as_of := _unix(row, "as_of_unix", "as_of")
	if as_of > 0:
		challenge["as_of_unix"] = as_of
	challenge["attempt_id"] = attempt_id
	challenge["idempotent_replay"] = out.idempotent_replay
	out.challenge = challenge
	out.ok = true
	out.already_used = false
	return out


static func parse_status(result: Dictionary) -> Dictionary:
	var out := {
		"ok": false,
		"attempted": false,
		"recoverable": false,
		"resets_at_unix": 0,
		"as_of_unix": 0,
		"status": int(result.get("status", 0)),
		"error": str(result.get("error", "")),
	}
	if not bool(result.get("ok", false)):
		return out
	var row := _first(result.get("data", null))
	if row.is_empty():
		out.error = "empty_payload"
		return out
	out.ok = true
	out.attempted = _flag(row, "attempted")
	out["recoverable"] = _flag(row, "recoverable")
	out.resets_at_unix = _unix(row, "resets_unix", "resets_at")
	out.as_of_unix = _unix(row, "as_of_unix", "as_of")
	_copy_attempt_counts(row, out)
	if row.has("challenge_id"):
		out["challenge_id"] = str(row.get("challenge_id", "")).strip_edges()
	if not bool(out.get("attempts_counted", false)):
		# A server that still omits the count must not be given a free life.
		# A consumed one-attempt day stays locked. An unknown day stays unknown.
		if out.attempted:
			out["attempts_remaining"] = 0
			out["attempts_used"] = 1
	var course := DailyChallengeScript.from_server(row)
	if not course.is_empty():
		out["course"] = course
	return out


static func parse_finalize(result: Dictionary) -> Dictionary:
	var out := {
		"ok": false,
		"stored": false,
		"accepted": false,
		"duplicate": false,
		"score": 0,
		"status": int(result.get("status", 0)),
		"error": str(result.get("error", "")),
	}
	if not bool(result.get("ok", false)):
		return out
	var row := _first(result.get("data", null))
	if row.is_empty():
		out.error = "empty_payload"
		return out
	out.ok = true
	out.accepted = _flag(row, "accepted")
	out.duplicate = _flag(row, "duplicate")
	out.score = int(row.get("score", 0))
	out.stored = out.accepted or out.duplicate
	if row.has("best_score"):
		out["best_score"] = int(row.get("best_score", 0))
	else:
		out["best_score"] = out.score
	return out


# Transport loss, rate limits, and 5xx may have committed. Retry the same attempt.
# A definite 4xx other than auth or timeout did not store a score.
static func finalize_retryable(result: Dictionary, parsed: Dictionary) -> bool:
	if bool(parsed.get("stored", false)):
		return false
	var status := int(result.get("status", parsed.get("status", 0)))
	if status == 401 or status == 403 or status == 408 or status == 429:
		return true
	if status == 0 or status >= 500:
		return true
	var err := str(parsed.get("error", result.get("error", ""))).to_lower()
	return err.find("invalid_json") >= 0 or err.find("empty_payload") >= 0


static func parse_start(result: Dictionary) -> Dictionary:
	var out := {
		"ok": false,
		"started": false,
		"already_started": false,
		"status": int(result.get("status", 0)),
		"error": str(result.get("error", "")),
	}
	if not bool(result.get("ok", false)):
		return out
	var row := _first(result.get("data", null))
	if row.is_empty():
		out.error = "empty_payload"
		return out
	out.ok = true
	out.already_started = _flag(row, "already_started")
	out.started = _flag(row, "started") and not out.already_started
	_copy_attempt_counts(row, out)
	if not row.has("attempts_remaining") and out.already_started:
		out["attempts_remaining"] = 0
		out["attempts_used"] = 1
	return out


static func _write_periods(book: Dictionary, player_id: String, display_name: String, score: int, challenge_id: String, server_unix: int) -> void:
	var date := ""
	var parts := challenge_id.split(":")
	if parts.size() >= 2:
		date = parts[1]
	var name := display_name.strip_edges().substr(0, 7)
	if name.is_empty():
		name = "YOU"
	if date.length() != 10:
		return
	var keys: Dictionary = DailyChallengeScript.period_keys_for_date(date)
	if not book.has("rows"):
		book["rows"] = []
	_upsert_period(book, player_id, name, score, "daily", str(keys.get("daily", "")), challenge_id, server_unix)


static func submit_unlimited(book: Dictionary, player_id: String, display_name: String, score: int, server_unix: int) -> bool:
	if score <= 0 or player_id == "":
		return false
	var date := DailyChallengeScript.utc_date_from_unix(server_unix)
	if date.length() != 10:
		return false
	var name := display_name.strip_edges().substr(0, 7)
	if name.is_empty():
		name = "YOU"
	var keys: Dictionary = DailyChallengeScript.period_keys_for_date(date)
	if not book.has("rows"):
		book["rows"] = []
	for period in ["weekly", "monthly"]:
		_upsert_period(book, player_id, name, score, period, str(keys.get(period, "")), "", server_unix)
	return true


static func _upsert_period(book: Dictionary, player_id: String, display_name: String, score: int, period: String, period_key: String, challenge_id: String, server_unix: int) -> void:
	var rows: Array = book["rows"]
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("player_id", "")) != player_id:
			continue
		if str(row.get("period", "")) != period or str(row.get("period_key", "")) != period_key:
			continue
		if (str(row.get("challenge_id", "")) != "") != (challenge_id != ""):
			continue
		if score > int(row.get("score", 0)):
			row["score"] = score
			row["display_name"] = display_name
			row["challenge_id"] = challenge_id
		return
	rows.append({
		"player_id": player_id,
		"display_name": display_name,
		"name": display_name,
		"score": score,
		"period": period,
		"period_key": period_key,
		"challenge_id": challenge_id,
		"created_at": server_unix,
	})


# Left fish stays colored longest. A negative remaining means the server
# status is still unknown, so every fish stays gray.
static func fish_lit(index: int, remaining: int) -> bool:
	return remaining > index


static func lives_from_status(status: Dictionary) -> int:
	if not bool(status.get("ok", false)):
		return -1
	if status.has("attempts_remaining"):
		return clampi(int(status.get("attempts_remaining", 0)), 0, ATTEMPT_LIMIT)
	if bool(status.get("attempted", false)):
		return 0
	return -1


# saved_used is the most lives already confirmed for saved_challenge.
# The same challenge can never come back with more lives. A different
# challenge id is the server's next daily period. The device clock is ignored.
static func merge_lives(saved_challenge: String, saved_used: int, status: Dictionary) -> Dictionary:
	var kept_challenge := saved_challenge.strip_edges()
	var kept_used := clampi(saved_used, 0, ATTEMPT_LIMIT)
	var out := {
		"lives": -1,
		"challenge_id": kept_challenge,
		"used": kept_used,
		"store": false,
	}
	if not bool(status.get("ok", false)):
		if kept_challenge != "" and kept_used >= ATTEMPT_LIMIT:
			out["lives"] = 0
		return out
	var cid := str(status.get("challenge_id", "")).strip_edges()
	if cid == "":
		var course: Variant = status.get("course", {})
		if typeof(course) == TYPE_DICTIONARY:
			cid = str(course.get("challenge_id", "")).strip_edges()
	var counted := bool(status.get("attempts_counted", false))
	var lives := lives_from_status(status)
	if not counted:
		if kept_challenge != "" and kept_used >= ATTEMPT_LIMIT and (cid == "" or cid == kept_challenge):
			out["lives"] = 0
			return out
		out["lives"] = 0 if lives == 0 else -1
		if cid != "":
			out["challenge_id"] = cid
		return out
	if cid == "":
		if kept_used >= ATTEMPT_LIMIT:
			lives = mini(lives, 0)
		out["lives"] = lives
		if lives >= 0 and kept_challenge != "":
			out["used"] = maxi(kept_used, ATTEMPT_LIMIT - lives)
			out["store"] = true
		return out
	if cid != kept_challenge:
		out["lives"] = lives
		out["challenge_id"] = cid
		out["used"] = maxi(0, ATTEMPT_LIMIT - lives)
		out["store"] = true
		return out
	var cap := ATTEMPT_LIMIT - kept_used
	if lives > cap:
		lives = cap
	out["lives"] = lives
	out["challenge_id"] = cid
	out["used"] = maxi(kept_used, ATTEMPT_LIMIT - lives)
	out["store"] = true
	return out


static func lives_from_claim(claim: Dictionary) -> int:
	if claim.has("attempts_remaining"):
		return clampi(int(claim.get("attempts_remaining", 0)), 0, ATTEMPT_LIMIT)
	if bool(claim.get("already_used", false)):
		return 0
	return -1


static func _copy_attempt_counts(row: Dictionary, out: Dictionary) -> void:
	if row.has("attempts_remaining") and row.get("attempts_remaining") != null:
		out["attempts_remaining"] = int(row.get("attempts_remaining", 0))
		out["attempts_counted"] = true
	if row.has("attempts_used") and row.get("attempts_used") != null:
		out["attempts_used"] = int(row.get("attempts_used", 0))
	if row.has("best_score"):
		out["best_score"] = int(row.get("best_score", 0))


static func _rows_for(store: Dictionary, player_id: String, challenge_id: String) -> Array:
	var found: Array = []
	for row in _attempts(store):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("player_id", "")) == player_id and str(row.get("challenge_id", "")) == challenge_id:
			found.append(row)
	return found


static func _started_count(rows: Array) -> int:
	var n := 0
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and bool(row.get("started", false)):
			n += 1
	return n


static func _pending_row(rows: Array) -> Dictionary:
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if not bool(row.get("started", false)) and not bool(row.get("finalized", false)):
			return row
	return {}


static func _find_key(rows: Array, idempotency_key: String) -> Dictionary:
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and str(row.get("idempotency_key", "")) == idempotency_key:
			return row
	return {}


static func _best_score(rows: Array) -> int:
	var best := 0
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY or not bool(row.get("finalized", false)):
			continue
		best = maxi(best, int(row.get("score", 0)))
	return best


static func _board_best(book: Dictionary, player_id: String, challenge_id: String) -> int:
	var date := ""
	var parts := challenge_id.split(":")
	if parts.size() >= 2:
		date = parts[1]
	if date.length() != 10 or not book.has("rows"):
		return 0
	var keys: Dictionary = DailyChallengeScript.period_keys_for_date(date)
	var best := 0
	for row in book["rows"]:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("player_id", "")) != player_id:
			continue
		if str(row.get("period", "")) != "daily" or str(row.get("period_key", "")) != str(keys.get("daily", "")):
			continue
		if str(row.get("challenge_id", "")) == "":
			continue
		best = maxi(best, int(row.get("score", 0)))
	return best


static func _find_player_challenge(store: Dictionary, player_id: String, challenge_id: String) -> Dictionary:
	for row in _attempts(store):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("player_id", "")) == player_id and str(row.get("challenge_id", "")) == challenge_id:
			return row
	return {}


static func _find_attempt(store: Dictionary, player_id: String, attempt_id: String) -> Dictionary:
	for row in _attempts(store):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("player_id", "")) == player_id and str(row.get("attempt_id", "")) == attempt_id:
			return row
	return {}


static func _attempts(store: Dictionary) -> Array:
	if not store.has("attempts") or not (store["attempts"] is Array):
		store["attempts"] = []
	return store["attempts"]


static func _first(data: Variant) -> Dictionary:
	if data is Array and not data.is_empty() and typeof(data[0]) == TYPE_DICTIONARY:
		return data[0]
	if typeof(data) == TYPE_DICTIONARY:
		var err := str(data.get("message", data.get("error", ""))).strip_edges()
		if err != "":
			return {}
		if data.has("challenge_id") or data.has("attempt_id") or data.has("attempted") or data.has("accepted"):
			return data
	return {}


static func _flag(row: Dictionary, key: String) -> bool:
	var value: Variant = row.get(key, false)
	if typeof(value) == TYPE_BOOL:
		return value
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value) != 0
	var text := str(value).strip_edges().to_lower()
	return text == "true" or text == "t" or text == "1"


static func _text(value: Variant) -> String:
	if value == null:
		return ""
	var text := str(value).strip_edges()
	if text == "<null>" or text.to_lower() == "null":
		return ""
	return text


static func _unix(row: Dictionary, primary: String, fallback: String) -> int:
	if primary != "" and row.has(primary) and row.get(primary) != null:
		return DailyChallengeScript.unix_from_variant(row.get(primary))
	if fallback != "" and row.has(fallback):
		return DailyChallengeScript.unix_from_variant(row.get(fallback))
	return 0
