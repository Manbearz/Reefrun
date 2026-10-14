extends SceneTree

const DailyTestModeScript := preload("res://scripts/daily_test_mode.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = get_root().get_node_or_null("GameSession")
	var backend = get_root().get_node_or_null("Backend")
	var before_mode: String = session.match_mode
	var before_seed: int = session.course_seed
	var before_games: int = session.games_played
	var before_coins: int = session.coins
	var before_best: int = session.best_score
	var before_last: int = session.last_score
	var started: bool = session.begin_practice_daily({
		"challenge_id": "daily:2026-10-14:cv1:pv1",
		"course_seed": 5,
		"attempt_id": "6f1e8c2a-9b34-4d5e-8f70-123456789abc",
		"server_confirmed": true,
	})
	var active: bool = DailyTestModeScript.enabled()
	var gate_ok: bool = false
	if active:
		gate_ok = (
			started
			and session.practice_daily
			and session.course_seed == 5
			and str(session.current_challenge().get("attempt_id", "")) == ""
			and session.games_played == before_games
			and session.coins == before_coins
		)
		session.end_practice_daily()
		gate_ok = gate_ok and not session.practice_daily and session.course_seed == before_seed
	else:
		gate_ok = (
			not started
			and session.match_mode == before_mode
			and session.course_seed == before_seed
			and not session.practice_daily
			and session.games_played == before_games
		)
	var course: Dictionary = DailyTestModeScript.practice_course({
		"challenge_id": "daily:2026-10-14:cv1:pv1",
		"course_seed": 5,
		"attempt_id": "6f1e8c2a-9b34-4d5e-8f70-123456789abc",
		"server_confirmed": true,
	})
	var stripped: bool = (
		not course.has("attempt_id")
		and not bool(course.get("server_confirmed", true))
		and bool(course.get("practice", false))
		and int(course.get("course_seed", 0)) == 5
		and str(course.get("challenge_id", "")) == "daily:2026-10-14:cv1:pv1"
	)
	session.practice_daily = true
	session.record_run(before_last + 50, 1, 1)
	var ignored: bool = session.last_score == before_last and session.best_score == before_best and session.coins == before_coins
	session.practice_daily = false
	var label: String = DailyTestModeScript.status_label()
	var label_ok: bool = (label == "active") == active and label != "blocked_not_editor"
	var ok: bool = gate_ok and stripped and ignored and label_ok and backend != null
	print("[daily-test] ok=%s active=%s label=%s gate=%s stripped=%s ignored=%s" % [ok, active, label, gate_ok, stripped, ignored])
	quit(0 if ok else 1)
