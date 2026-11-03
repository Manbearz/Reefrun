extends SceneTree

const ProviderScript := preload("res://scripts/share/native_share_provider.gd")
const RulesScript := preload("res://scripts/share/referral_rules.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _check("desktop_save", _test_desktop_save()) and ok
	ok = _check("busy_gate", _test_busy_gate()) and ok
	ok = _check("wiring", _test_wiring()) and ok
	ok = _check("score_message", _test_score_message()) and ok
	print("[share-sheet] ok=%s" % ok)
	quit(0 if ok else 1)


func _check(name: String, passed: bool) -> bool:
	print("[share-sheet] %s=%s" % [name, passed])
	return passed


func _test_desktop_save() -> bool:
	if OS.has_feature("android") or OS.has_feature("ios"):
		push_error("[share-sheet] this check is for desktop or headless only")
		return false
	var provider := ProviderScript.new()
	root.add_child(provider)
	var statuses: PackedStringArray = PackedStringArray()
	provider.share_finished.connect(func(status: String) -> void: statuses.append(status))
	var first := provider.share_image(PackedByteArray([137, 80, 78, 71]), "I scored 42 in ReefRun! Can you beat me?")
	var second := provider.share_image(PackedByteArray([137, 80, 78, 71]), "I scored 9 in ReefRun! Can you beat me?")
	var empty := provider.share_image(PackedByteArray(), "unused")
	var busy_after := provider.is_busy()
	provider.queue_free()
	return (
		first == "saved"
		and second == "saved"
		and empty == "failed"
		and not busy_after
		and statuses == PackedStringArray(["saved", "saved", "failed"])
		and FileAccess.file_exists("user://reefrun-run.png")
	)


func _test_busy_gate() -> bool:
	var provider := ProviderScript.new()
	root.add_child(provider)
	var statuses: PackedStringArray = PackedStringArray()
	provider.share_finished.connect(func(status: String) -> void: statuses.append(status))
	provider.set("_busy", true)
	var status := provider.share_image(PackedByteArray([1]), "I scored 42 in ReefRun! Can you beat me?")
	var still_busy: bool = provider.is_busy()
	provider.queue_free()
	return status == "busy" and still_busy and statuses.is_empty()


func _test_wiring() -> bool:
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	var ios_at := preset.find("name=\"iOS\"")
	var web_at := preset.find("name=\"Web\"")
	var ios_block := preset.substr(ios_at, web_at - ios_at) if ios_at >= 0 and web_at > ios_at else ""
	var game := FileAccess.get_file_as_string("res://scenes/game/game.gd")
	var release_bin := "res://ios/plugins/SharePlugin.release.xcframework/ios-arm64/SharePlugin.a"
	var debug_bin := "res://ios/plugins/SharePlugin.debug.xcframework/ios-arm64/SharePlugin.a"
	var gdip := ConfigFile.new()
	var gdip_err := gdip.load("res://ios/plugins/SharePlugin.gdip")
	var flags: PackedStringArray = gdip.get_value("dependencies", "linker_flags", PackedStringArray())
	return (
		ios_block.contains("plugins/SharePlugin=true")
		and not preset.substr(web_at).contains("plugins/SharePlugin=true")
		and FileAccess.file_exists(release_bin)
		and FileAccess.file_exists(debug_bin)
		and gdip_err == OK
		and str(gdip.get_value("config", "name", "")) == "SharePlugin"
		and str(gdip.get_value("config", "initialization", "")) == "share_plugin_init"
		and str(gdip.get_value("config", "binary", "")) == "SharePlugin.xcframework"
		and flags.has("-ObjC")
		and game.contains("run_share_message(score, GameSession.referral_code)")
		and not game.contains("ReferralRulesScript.share_message(")
	)


func _test_score_message() -> bool:
	var message := RulesScript.run_share_message(42, "")
	return message == "I scored 42 in ReefRun! Can you beat me? 🐟" and "http" not in message.to_lower()
