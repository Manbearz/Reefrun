extends SceneTree

const Rules := preload("res://scripts/rr.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _check(Rules.FISH_RARITY.size() == Rules.FISH_COUNT, "fish rarity count") and ok
	ok = _check(Rules.HAT_RARITY.size() == Rules.HAT_COUNT, "hat rarity count") and ok
	var fish_counts := [0, 0, 0]
	var hat_counts := [0, 0, 0]
	for i in Rules.FISH_COUNT:
		var price := Rules.fish_price(i)
		if i < Rules.FREE_FISH:
			ok = _check(price == 0, "free fish %d" % i) and ok
		else:
			var rarity := Rules.FISH_RARITY[i]
			fish_counts[rarity] += 1
			var expected: int = [500, 1000, 2000][rarity]
			ok = _check(price == expected, "fish %d price" % i) and ok
	for i in Rules.HAT_COUNT:
		var rarity := Rules.HAT_RARITY[i]
		hat_counts[rarity] += 1
		var expected: int = [250, 500, 1000][rarity]
		ok = _check(Rules.hat_price(i) == expected, "hat %d price" % i) and ok
	print("[shop] fish common=%d rare=%d legendary=%d" % [fish_counts[0], fish_counts[1], fish_counts[2]])
	print("[shop] hats common=%d rare=%d legendary=%d" % [hat_counts[0], hat_counts[1], hat_counts[2]])
	print("[shop] ok=%s" % ok)
	quit(0 if ok else 1)


func _check(passed: bool, label: String) -> bool:
	if not passed:
		print("[shop] FAIL %s" % label)
	return passed
