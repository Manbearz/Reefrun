extends SceneTree

const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")
const DailyAttemptScript := preload("res://scripts/daily_attempt.gd")
const LeaderboardScript := preload("res://scripts/backend/leaderboard_repository.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _check("claim_succeeds", _test_claim_succeeds()) and ok
	ok = _check("same_player_denied", _test_same_player_denied()) and ok
	ok = _check("other_device_denied", _test_other_device_denied()) and ok
	ok = _check("other_player_allowed", _test_other_player_allowed()) and ok
	ok = _check("lost_response_recovers", _test_lost_response()) and ok
	ok = _check("status_does_not_claim", _test_status_does_not_claim()) and ok
	ok = _check("recover_unplayed_claim", _test_recover_unplayed_claim()) and ok
	ok = _check("started_blocks_second_run", _test_started_blocks_second_run()) and ok
	ok = _check("lost_start_still_enters", _test_lost_start_still_enters()) and ok
	ok = _check("transport_retry_still_enters", _test_transport_retry_still_enters()) and ok
	ok = _check("unstarted_not_finalized", _test_unstarted_not_finalized()) and ok
	ok = _check("week_keeps_higher_score", _test_week_keeps_higher_score()) and ok
	ok = _check("score_submit", _test_score_submit()) and ok
	ok = _check("daily_board", _test_board("daily")) and ok
	ok = _check("weekly_board", _test_board("weekly")) and ok
	ok = _check("monthly_board", _test_board("monthly")) and ok
	ok = _check("unlimited_open", _test_unlimited()) and ok
	ok = _check("next_utc_day", _test_next_day()) and ok
	ok = _check("retry_same_attempt", _test_retry_same_attempt()) and ok
	ok = _check("duplicate_finalize", _test_duplicate_finalize()) and ok
	ok = _check("client_date_ignored", _test_client_date_ignored()) and ok
	ok = _check("parse_payloads", _test_parse_payloads()) and ok
	ok = _check("failed_claim_not_completed", _test_failed_claim_not_completed()) and ok
	ok = _check("rpc_urls", _test_rpc_urls()) and ok
	ok = _check("wired", _test_wired()) and ok
	print("[attempt] ok=%s" % ok)
	quit(0 if ok else 1)


func _check(name: String, passed: bool) -> bool:
	print("[attempt] %s=%s" % [name, passed])
	return passed


func _today() -> Dictionary:
	return DailyChallengeScript.make("2026-10-12", true, DailyChallengeScript.unix_utc(2026, 10, 12, 12))


func _tomorrow() -> Dictionary:
	return DailyChallengeScript.make("2026-10-13", true, DailyChallengeScript.unix_utc(2026, 10, 13, 12))


func _unix() -> int:
	return DailyChallengeScript.unix_utc(2026, 10, 12, 15)


func _test_claim_succeeds() -> bool:
	var store := DailyAttemptScript.empty_store()
	var got: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-a", _today())
	return bool(got.get("claimed", false)) and str(got.get("attempt_id", "")) != "" and int(got.get("attempt_count", 0)) == 1


func _test_same_player_denied() -> bool:
	var store := DailyAttemptScript.empty_store()
	DailyAttemptScript.claim(store, "player-a", "key-a", _today())
	var again: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-b", _today())
	return bool(again.get("already_used", false)) and not bool(again.get("claimed", false)) and int(again.get("attempt_count", 0)) == 1


func _test_other_device_denied() -> bool:
	var store := DailyAttemptScript.empty_store()
	DailyAttemptScript.claim(store, "player-a", "phone-key", _today())
	var tablet: Dictionary = DailyAttemptScript.claim(store, "player-a", "tablet-key", _today())
	return bool(tablet.get("already_used", false)) and int(tablet.get("attempt_count", 0)) == 1


func _test_other_player_allowed() -> bool:
	var store := DailyAttemptScript.empty_store()
	var first: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-a", _today())
	var second: Dictionary = DailyAttemptScript.claim(store, "player-b", "key-b", _today())
	return bool(first.get("claimed", false)) and bool(second.get("claimed", false)) and int(second.get("attempt_count", 0)) == 2


func _test_lost_response() -> bool:
	var store := DailyAttemptScript.empty_store()
	var first: Dictionary = DailyAttemptScript.claim(store, "player-a", "same-key", _today())
	var retry: Dictionary = DailyAttemptScript.claim(store, "player-a", "same-key", _today())
	return (
		bool(retry.get("claimed", false))
		and bool(retry.get("idempotent_replay", false))
		and str(retry.get("attempt_id", "")) == str(first.get("attempt_id", ""))
		and int(retry.get("attempt_count", 0)) == 1
	)


func _test_status_does_not_claim() -> bool:
	var store := DailyAttemptScript.empty_store()
	var before := int(DailyAttemptScript.status_of(store, "player-a", _today()).get("attempt_count", -1))
	var status: Dictionary = DailyAttemptScript.status_of(store, "player-a", _today())
	return before == 0 and not bool(status.get("attempted", true)) and int(status.get("attempt_count", -1)) == 0


func _test_recover_unplayed_claim() -> bool:
	var store := DailyAttemptScript.empty_store()
	DailyAttemptScript.claim(store, "player-a", "same-key", _today())
	var open_screen: Dictionary = DailyAttemptScript.status_of(store, "player-a", _today(), "same-key")
	var other_device: Dictionary = DailyAttemptScript.status_of(store, "player-a", _today(), "other-key")
	var replay: Dictionary = DailyAttemptScript.claim(store, "player-a", "same-key", _today())
	return (
		bool(open_screen.get("recoverable", false))
		and not bool(open_screen.get("attempted", true))
		and bool(other_device.get("attempted", false))
		and bool(replay.get("claimed", false))
		and int(open_screen.get("attempt_count", 0)) == 1
	)


func _test_started_blocks_second_run() -> bool:
	var store := DailyAttemptScript.empty_store()
	var claimed: Dictionary = DailyAttemptScript.claim(store, "player-a", "same-key", _today())
	var attempt_id := str(claimed.get("attempt_id", ""))
	var began: Dictionary = DailyAttemptScript.start(store, "player-a", attempt_id)
	var again: Dictionary = DailyAttemptScript.start(store, "player-a", attempt_id)
	var replay: Dictionary = DailyAttemptScript.claim(store, "player-a", "same-key", _today())
	var status: Dictionary = DailyAttemptScript.status_of(store, "player-a", _today(), "same-key")
	return (
		bool(began.get("started", false))
		and not bool(began.get("already_started", true))
		and bool(again.get("already_started", false))
		and not bool(again.get("started", true))
		and bool(replay.get("already_used", false))
		and not bool(replay.get("claimed", true))
		and str(replay.get("attempt_id", "x")) == ""
		and bool(status.get("attempted", false))
		and not bool(status.get("recoverable", true))
		and int(status.get("attempt_count", 0)) == 1
	)


func _test_lost_start_still_enters() -> bool:
	var retry := {
		"ok": true,
		"started": false,
		"already_started": true,
		"status": 200,
	}
	var recovered: Dictionary = DailyAttemptScript.recover_lost_start(true, retry)
	var later: Dictionary = DailyAttemptScript.recover_lost_start(false, retry)
	return (
		bool(recovered.get("started", false))
		and not bool(recovered.get("already_started", true))
		and bool(later.get("already_started", false))
		and not bool(later.get("started", true))
	)


func _test_transport_retry_still_enters() -> bool:
	var landed := {
		"ok": true,
		"status": 200,
		"retried_after_transport": true,
		"data": [{"attempt_id": "attempt-1", "started": false, "already_started": true}],
	}
	var fresh := {
		"ok": true,
		"status": 200,
		"data": [{"attempt_id": "attempt-1", "started": false, "already_started": true}],
	}
	var recovered: Dictionary = DailyAttemptScript.recover_lost_start(
		DailyAttemptScript.start_attempt_uncertain(false, landed),
		DailyAttemptScript.parse_start(landed)
	)
	var blocked: Dictionary = DailyAttemptScript.recover_lost_start(
		DailyAttemptScript.start_attempt_uncertain(false, fresh),
		DailyAttemptScript.parse_start(fresh)
	)
	return (
		DailyAttemptScript.start_attempt_uncertain(false, {"status": 0})
		and DailyAttemptScript.start_attempt_uncertain(false, {"status": 503})
		and not DailyAttemptScript.start_attempt_uncertain(false, {"status": 400})
		and bool(recovered.get("started", false))
		and not bool(recovered.get("already_started", true))
		and bool(blocked.get("already_started", false))
		and not bool(blocked.get("started", true))
	)


func _test_unstarted_not_finalized() -> bool:
	var store := DailyAttemptScript.empty_store()
	var book := DailyChallengeScript.empty_book()
	var claimed: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-a", _today())
	var denied: Dictionary = DailyAttemptScript.finalize(
		store,
		book,
		"player-a",
		str(claimed.get("attempt_id", "")),
		12,
		"REEF",
		_unix()
	)
	var rows: Array = book.get("rows", [])
	return (
		not bool(denied.get("ok", true))
		and str(denied.get("error", "")) == "attempt_not_started"
		and rows.is_empty()
		and not bool(DailyAttemptScript.status_of(store, "player-a", _today(), "key-a").get("attempted", true))
	)


func _test_week_keeps_higher_score() -> bool:
	var store := DailyAttemptScript.empty_store()
	var book := DailyChallengeScript.empty_book()
	var monday: Dictionary = DailyAttemptScript.claim(store, "player-a", "day-1", _today())
	DailyAttemptScript.start(store, "player-a", str(monday.get("attempt_id", "")))
	DailyAttemptScript.finalize(store, book, "player-a", str(monday.get("attempt_id", "")), 30, "LONGNAME", _unix())
	var daily_rows: Array = DailyChallengeScript.visible_board(book, "daily", _unix())
	var leaked: Array = DailyChallengeScript.visible_board(book, "weekly", _unix())
	DailyAttemptScript.submit_unlimited(book, "player-a", "LONGNAME", 30, _unix())
	DailyAttemptScript.submit_unlimited(book, "player-a", "REEF", 10, DailyChallengeScript.unix_utc(2026, 10, 13, 15))
	var rows: Array = DailyChallengeScript.visible_board(book, "weekly", _unix())
	if rows.is_empty() or daily_rows.is_empty():
		return false
	return (
		leaked.is_empty()
		and str(daily_rows[0].get("display_name", "")) == "LONGNAM"
		and int(daily_rows[0].get("score", 0)) == 30
		and rows.size() == 1
		and str(rows[0].get("display_name", "")) == "LONGNAM"
		and int(rows[0].get("score", 0)) == 30
	)


func _played() -> Dictionary:
	var store := DailyAttemptScript.empty_store()
	var book := DailyChallengeScript.empty_book()
	var claimed: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-a", _today())
	DailyAttemptScript.start(store, "player-a", str(claimed.get("attempt_id", "")))
	var done: Dictionary = DailyAttemptScript.finalize(
		store,
		book,
		"player-a",
		str(claimed.get("attempt_id", "")),
		27,
		"REEF",
		_unix()
	)
	return {"store": store, "book": book, "done": done, "claimed": claimed}


func _test_score_submit() -> bool:
	var played := _played()
	var done: Dictionary = played["done"]
	return bool(done.get("accepted", false)) and int(done.get("score", 0)) == 27


func _test_board(period: String) -> bool:
	var book: Dictionary = DailyChallengeScript.empty_book()
	if period == "daily":
		book = _played()["book"]
	else:
		DailyAttemptScript.submit_unlimited(book, "player-a", "REEF", 27, _unix())
		DailyAttemptScript.submit_unlimited(book, "player-a", "REEF", 9, _unix())
	var rows: Array = DailyChallengeScript.visible_board(book, period, _unix())
	if rows.is_empty():
		return false
	var other := "weekly" if period == "daily" else "daily"
	var crossed: Array = DailyChallengeScript.visible_board(book, other, _unix())
	return crossed.is_empty() and str(rows[0].get("display_name", "")) == "REEF" and int(rows[0].get("score", 0)) == 27


func _test_unlimited() -> bool:
	return (
		not DailyAttemptScript.attempt_required("unlimited")
		and DailyAttemptScript.attempt_required("daily")
		and not DailyAttemptScript.should_finalize("unlimited", "attempt-1")
		and not DailyAttemptScript.should_finalize("daily", "")
		and DailyAttemptScript.should_finalize("daily", "attempt-1")
	)


func _test_next_day() -> bool:
	var store := DailyAttemptScript.empty_store()
	DailyAttemptScript.claim(store, "player-a", "day-1", _today())
	var next: Dictionary = DailyAttemptScript.claim(store, "player-a", "day-2", _tomorrow())
	var denied: Dictionary = DailyAttemptScript.claim(store, "player-a", "day-1b", _today())
	return bool(next.get("claimed", false)) and bool(denied.get("already_used", false)) and int(next.get("attempt_count", 0)) == 2


func _test_retry_same_attempt() -> bool:
	var store := DailyAttemptScript.empty_store()
	var book := DailyChallengeScript.empty_book()
	var claimed: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-a", _today())
	var attempt_id := str(claimed.get("attempt_id", ""))
	var blocked: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-b", _today())
	DailyAttemptScript.start(store, "player-a", attempt_id)
	var first: Dictionary = DailyAttemptScript.finalize(store, book, "player-a", attempt_id, 40, "REEF", _unix())
	var count_after := int(DailyAttemptScript.status_of(store, "player-a", _today()).get("attempt_count", 0))
	return bool(blocked.get("already_used", false)) and bool(first.get("accepted", false)) and count_after == 1


func _test_duplicate_finalize() -> bool:
	var store := DailyAttemptScript.empty_store()
	var book := DailyChallengeScript.empty_book()
	var claimed: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-a", _today())
	var attempt_id := str(claimed.get("attempt_id", ""))
	DailyAttemptScript.start(store, "player-a", attempt_id)
	DailyAttemptScript.finalize(store, book, "player-a", attempt_id, 40, "REEF", _unix())
	var second: Dictionary = DailyAttemptScript.finalize(store, book, "other-player", attempt_id, 99, "NOPE", _unix())
	var replay: Dictionary = DailyAttemptScript.finalize(store, book, "player-a", attempt_id, 99, "REEF", _unix())
	var rows: Array = DailyChallengeScript.visible_board(book, "daily", _unix())
	var shown := 0
	if not rows.is_empty():
		shown = int(rows[0].get("score", 0))
	return (
		not bool(second.get("ok", true))
		and bool(replay.get("duplicate", false))
		and int(replay.get("score", 0)) == 40
		and shown == 40
		and int(DailyAttemptScript.status_of(store, "player-a", _today()).get("attempt_count", 0)) == 1
	)


func _test_client_date_ignored() -> bool:
	var store := DailyAttemptScript.empty_store()
	var server := _today()
	var got: Dictionary = DailyAttemptScript.claim(store, "player-a", "key-a", server, "1999-01-01")
	return str(got.get("challenge_id", "")) == str(server.get("challenge_id", ""))


func _test_parse_payloads() -> bool:
	var made := _today()
	var row := {
		"challenge_id": made["challenge_id"],
		"challenge_date": "2026-10-12",
		"course_seed": made["course_seed"],
		"course_version": RR.COURSE_VERSION,
		"physics_version": RR.PHYSICS_VERSION,
		"as_of_unix": int(made["as_of_unix"]),
		"resets_unix": DailyChallengeScript.unix_utc(2026, 10, 13),
		"attempt_id": "6f1e8c2a-9b34-4d5e-8f70-123456789abc",
		"claimed": true,
		"already_used": false,
		"idempotent_replay": true,
		"finalized": false,
	}
	var claimed: Dictionary = DailyAttemptScript.parse_claim({"ok": true, "status": 200, "data": [row]})
	row["claimed"] = false
	row["already_used"] = true
	row["finalized"] = false
	var denied: Dictionary = DailyAttemptScript.parse_claim({"ok": true, "status": 200, "data": [row]})
	var finished: Dictionary = DailyAttemptScript.parse_finalize({
		"ok": true,
		"status": 200,
		"data": [{"attempt_id": row["attempt_id"], "score": 40, "accepted": false, "duplicate": true}],
	})
	var status: Dictionary = DailyAttemptScript.parse_status({
		"ok": true,
		"status": 200,
		"data": [{"attempted": true, "resets_unix": DailyChallengeScript.unix_utc(2026, 10, 13), "as_of_unix": _unix()}],
	})
	var reset := DailyAttemptScript.reset_label(DailyChallengeScript.unix_utc(2026, 10, 13), DailyChallengeScript.unix_utc(2026, 10, 12, 20, 30))
	var key := DailyAttemptScript.new_idempotency_key()
	return (
		bool(claimed.get("ok", false))
		and str(claimed.get("challenge", {}).get("attempt_id", "")) == "6f1e8c2a-9b34-4d5e-8f70-123456789abc"
		and not bool(denied.get("ok", true))
		and bool(denied.get("already_used", false))
		and bool(finished.get("stored", false))
		and int(finished.get("score", 0)) == 40
		and bool(status.get("attempted", false))
		and not bool(status.get("recoverable", true))
		and reset == "RESETS IN 3H 30M"
		and key.length() == 36
		and key.substr(14, 1) == "4"
	)


func _test_failed_claim_not_completed() -> bool:
	var missing: Dictionary = DailyAttemptScript.parse_claim({"ok": false, "status": 404, "error": "http_404"})
	var offline: Dictionary = DailyAttemptScript.parse_claim({"ok": false, "status": 0, "error": "http_0"})
	var status: Dictionary = DailyAttemptScript.parse_status({"ok": false, "status": 404, "error": "http_404"})
	return (
		not bool(missing.get("ok", true))
		and not bool(missing.get("already_used", true))
		and not bool(offline.get("already_used", true))
		and not bool(status.get("attempted", true))
		and not bool(status.get("ok", true))
		and not DailyAttemptScript.keep_claim_key(404)
		and not DailyAttemptScript.keep_claim_key(400)
		and DailyAttemptScript.keep_claim_key(0)
		and DailyAttemptScript.keep_claim_key(503)
	)


func _test_rpc_urls() -> bool:
	var repo = LeaderboardScript.new()
	return (
		str(repo.claim_url()).ends_with("/rest/v1/rpc/claim_daily_attempt")
		and str(repo.status_url()).ends_with("/rest/v1/rpc/get_daily_attempt_status")
		and str(repo.start_url()).ends_with("/rest/v1/rpc/start_daily_attempt")
		and str(repo.finalize_url()).ends_with("/rest/v1/rpc/finalize_daily_attempt")
		and str(repo.list_url()).ends_with("/rest/v1/rpc/get_leaderboard")
		and str(repo.submit_url()).ends_with("/rest/v1/rpc/submit_leaderboard_score")
	)


func _test_wired() -> bool:
	var backend = get_root().get_node_or_null("Backend")
	var session = get_root().get_node_or_null("GameSession")
	return (
		backend != null
		and backend.has_method("claim_daily_attempt")
		and backend.has_method("fetch_daily_attempt_status")
		and backend.has_method("start_daily_attempt")
		and backend.has_method("finalize_daily_attempt")
		and backend.has_method("submit_unlimited_score")
		and backend.has_method("prepare_claimed_daily")
		and session != null
		and session.has_method("begin_claimed_daily")
		and session.has_method("has_pending_finalize")
		and session.has_method("remember_pending_finalize")
	)
