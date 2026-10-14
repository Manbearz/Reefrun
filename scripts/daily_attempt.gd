class_name DailyAttempt
extends RefCounted

# Server claim rules, mirrored here so tests can exercise them without Supabase.
# The live game trusts claim_daily_attempt / finalize_daily_attempt, not this store.
# A matching course seed is not proof that a score is legitimate.

const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")
const COMPLETED_LABEL := "COMPLETED - COME BACK TOMORROW"


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
	var row := _find_player_challenge(store, player_id, str(challenge.get("challenge_id", "")))
	var recoverable := (
		not row.is_empty()
		and idempotency_key != ""
		and str(row.get("idempotency_key", "")) == idempotency_key
		and not bool(row.get("started", false))
		and not bool(row.get("finalized", false))
	)
	return {
		"attempted": not row.is_empty() and not recoverable,
		"recoverable": recoverable,
		"attempt_count": _attempts(store).size(),
	}


static func claim(store: Dictionary, player_id: String, idempotency_key: String, server_challenge: Dictionary, _client_date: String = "") -> Dictionary:
	var cid := str(server_challenge.get("challenge_id", ""))
	var existing := _find_player_challenge(store, player_id, cid)
	if not existing.is_empty():
		var same_key := str(existing.get("idempotency_key", "")) == idempotency_key
		var open_claim := (
			same_key
			and not bool(existing.get("started", false))
			and not bool(existing.get("finalized", false))
		)
		return {
			"claimed": open_claim,
			"already_used": not open_claim,
			"idempotent_replay": same_key,
			"finalized": bool(existing.get("finalized", false)),
			"attempt_id": str(existing.get("attempt_id", "")) if open_claim else "",
			"challenge_id": cid,
			"attempt_count": _attempts(store).size(),
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
	}


static func start(store: Dictionary, player_id: String, attempt_id: String) -> Dictionary:
	var row := _find_attempt(store, player_id, attempt_id)
	if row.is_empty():
		return {"ok": false, "started": false, "already_started": false, "error": "attempt_not_found"}
	if bool(row.get("started", false)) or bool(row.get("finalized", false)):
		return {"ok": true, "started": false, "already_started": true}
	row["started"] = true
	return {"ok": true, "started": true, "already_started": false}


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
		return {"ok": false, "accepted": false, "duplicate": false, "score": 0, "error": "attempt_not_found"}
	if bool(row.get("finalized", false)):
		return {
			"ok": true,
			"accepted": false,
			"duplicate": true,
			"score": int(row.get("score", 0)),
			"stored": true,
		}
	if not bool(row.get("started", false)):
		return {"ok": false, "accepted": false, "duplicate": false, "score": 0, "error": "attempt_not_started"}
	if score < 0:
		return {"ok": false, "accepted": false, "duplicate": false, "score": 0, "error": "invalid_score"}
	row["score"] = score
	row["finalized"] = true
	if score > 0:
		_write_periods(book, player_id, display_name, score, str(row.get("challenge_id", "")), server_unix)
	return {"ok": true, "accepted": true, "duplicate": false, "score": score, "stored": true}


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
	return out


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
