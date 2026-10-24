extends SceneTree

const RulesScript := preload("res://scripts/share/referral_rules.gd")
const LinksScript := preload("res://scripts/share/referral_links.gd")
const RepoScript := preload("res://scripts/backend/share_reward_repository.gd")


func _initialize() -> void:
	ProjectSettings.set_setting("network/http_proxy/host", "127.0.0.1")
	ProjectSettings.set_setting("network/http_proxy/port", 9)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _check("three_friends", _test_three_friends()) and ok
	ok = _check("duplicate", _test_duplicate()) and ok
	ok = _check("self", _test_self()) and ok
	ok = _check("already_played", _test_already_played()) and ok
	ok = _check("cancel_and_offline", _test_cancel_and_offline()) and ok
	ok = _check("retry_grant", _test_retry_grant()) and ok
	ok = _check("device_switch", _test_device_switch()) and ok
	ok = _check("client_count_ignored", _test_client_count_ignored()) and ok
	ok = _check("links", _test_links()) and ok
	ok = _check("rpc_urls", _test_rpc_urls()) and ok
	ok = _check("wired", _test_wired()) and ok
	print("[share-reward] ok=%s" % ok)
	quit(0 if ok else 1)


func _check(name: String, passed: bool) -> bool:
	print("[share-reward] %s=%s" % [name, passed])
	return passed


func _test_three_friends() -> bool:
	var store := RulesScript.fresh_store()
	var code: String = RulesScript.ensure_code(store, "referrer")
	var again: String = RulesScript.ensure_code(store, "referrer")
	if code == "" or code != again:
		return false
	var players := ["n1", "n2", "n3"]
	for i in players.size():
		var attached: Dictionary = RulesScript.sync(store, players[i], code, false)
		if str(attached.get("attach", "")) != "attached":
			return false
		var done: Dictionary = RulesScript.sync(store, players[i], "", true)
		if not bool(done.get("first_run", false)):
			return false
		var board: Dictionary = RulesScript.status_of(store, "referrer")
		if int(board.get("qualified", 0)) != i + 1:
			return false
	var final: Dictionary = RulesScript.status_of(store, "referrer")
	var profile: Dictionary = store["profiles"]["referrer"]
	return (
		int(final.get("granted_coins", 0)) == 100
		and int(profile.get("coins", 0)) == 100
		and int(final.get("qualified", 0)) == 3
		and RulesScript.progress_label(int(final.get("qualified", 0))) == "FRIENDS 3/3"
		and RulesScript.share_url(code) == "https://lunarent.gg/?ref=" + code
	)


func _test_duplicate() -> bool:
	var store := RulesScript.fresh_store()
	var code: String = RulesScript.ensure_code(store, "referrer")
	var other: String = RulesScript.ensure_code(store, "other")
	var first: Dictionary = RulesScript.sync(store, "newbie", code, false)
	var second: Dictionary = RulesScript.sync(store, "newbie", code, false)
	var swapped: Dictionary = RulesScript.sync(store, "newbie", other, false)
	RulesScript.sync(store, "newbie", "", true)
	var board: Dictionary = RulesScript.status_of(store, "referrer")
	return (
		str(first.get("attach", "")) == "attached"
		and str(second.get("attach", "")) == "already_attached"
		and str(swapped.get("attach", "")) == "already_attached"
		and int(board.get("qualified", 0)) == 1
		and int(board.get("granted_coins", 0)) == 0
	)


func _test_self() -> bool:
	var store := RulesScript.fresh_store()
	var code: String = RulesScript.ensure_code(store, "referrer")
	var got: Dictionary = RulesScript.sync(store, "referrer", code, false)
	var board: Dictionary = RulesScript.status_of(store, "referrer")
	return str(got.get("attach", "")) == "self" and int(board.get("qualified", 0)) == 0 and int(board.get("granted_coins", 0)) == 0


func _test_already_played() -> bool:
	var store := RulesScript.fresh_store()
	var code: String = RulesScript.ensure_code(store, "referrer")
	var played: Dictionary = RulesScript.sync(store, "old", "", true)
	var denied: Dictionary = RulesScript.sync(store, "old", code, false)
	var board: Dictionary = RulesScript.status_of(store, "referrer")
	return bool(played.get("first_run", false)) and str(denied.get("attach", "")) == "already_played" and int(board.get("qualified", 0)) == 0


func _test_cancel_and_offline() -> bool:
	var store := RulesScript.fresh_store()
	var code: String = RulesScript.ensure_code(store, "referrer")
	var before := store.duplicate(true)
	var cancel_changes := RulesScript.rewards_change_on_share("cancel")
	var ok_changes := RulesScript.rewards_change_on_share("ok")
	var kept := not RulesScript.clear_pending_code(0, "attached")
	var kept_busy := not RulesScript.clear_pending_code(503, "attached")
	var cleared := RulesScript.clear_pending_code(200, "attached")
	var status_keeps := not RulesScript.clear_pending_code(200, "skipped")
	return (
		not cancel_changes
		and not ok_changes
		and kept
		and kept_busy
		and cleared
		and status_keeps
		and code != ""
		and store.hash() == before.hash()
	)


func _test_retry_grant() -> bool:
	var store := RulesScript.fresh_store()
	var code: String = RulesScript.ensure_code(store, "referrer")
	for name in ["a", "b", "c"]:
		RulesScript.sync(store, name, code, true)
	var once: Dictionary = RulesScript.status_of(store, "referrer")
	RulesScript.sync(store, "a", code, true)
	RulesScript.sync(store, "d", code, true)
	var twice: Dictionary = RulesScript.status_of(store, "referrer")
	var profile: Dictionary = store["profiles"]["referrer"]
	return int(once.get("granted_coins", 0)) == 100 and int(twice.get("granted_coins", 0)) == 100 and int(profile.get("coins", 0)) == 100 and int(twice.get("qualified", 0)) == 4


func _test_device_switch() -> bool:
	var first := RulesScript.coin_delta(0, 100)
	var restart := RulesScript.coin_delta(first, 100)
	var other_device := RulesScript.coin_delta(0, 100)
	var retry := RulesScript.coin_delta(other_device, 100)
	var inflated := RulesScript.coin_delta(0, 250)
	return first == 100 and restart == 0 and other_device == 100 and retry == 0 and inflated == 100


func _test_client_count_ignored() -> bool:
	var store := RulesScript.fresh_store()
	var lied: Dictionary = RulesScript.sync(store, "solo", "", false, 99)
	var parsed := RulesScript.parse_status({
		"qualified": 9,
		"granted_coins": 500,
		"coins": 9999,
		"code": "ab12cd34",
	})
	var body: Dictionary = RulesScript.sync_body("ab12cd34", true)
	return (
		int(lied.get("qualified", -1)) == 0
		and int(lied.get("granted_coins", -1)) == 0
		and int(parsed.get("qualified", -1)) == 3
		and int(parsed.get("granted_coins", -1)) == 100
		and not parsed.has("coins")
		and body.has("p_code")
		and body.has("p_run_completed")
		and body.size() == 2
		and str(body["p_code"]) == "AB12CD34"
		and bool(body["p_run_completed"])
	)


func _test_links() -> bool:
	var from_query := RulesScript.parse_ref("https://lunarent.gg/?ref=ab12cd34&utm=1")
	var from_hash := LinksScript.ingest("reefrun://ref/ZZ99YY88")
	var from_arg := RulesScript.from_arg("--ref=qwer1234")
	var ignored := RulesScript.from_arg("C:/Games/Reefrun")
	var message := RulesScript.share_message(from_query)
	return (
		from_query == "AB12CD34"
		and from_hash == "ZZ99YY88"
		and from_arg == "QWER1234"
		and ignored == ""
		and message == "Swim with me in ReefRun! https://lunarent.gg/?ref=AB12CD34"
		and RulesScript.progress_label(0) == "FRIENDS 0/3"
	)


func _test_rpc_urls() -> bool:
	var repo = RepoScript.new()
	return (
		str(repo.status_url()).ends_with("/rest/v1/rpc/get_share_reward_status")
		and str(repo.sync_url()).ends_with("/rest/v1/rpc/sync_share_progress")
	)


func _test_wired() -> bool:
	var backend = get_root().get_node_or_null("Backend")
	var session = get_root().get_node_or_null("GameSession")
	return (
		backend != null
		and session != null
		and backend.has_method("refresh_share_rewards")
		and backend.has_method("note_referral_link")
		and session.has_method("remember_referral_code")
		and session.has_method("apply_share_result")
	)
