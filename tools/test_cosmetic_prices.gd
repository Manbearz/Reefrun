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
	ok = _check(_prices_rise(Rules.fish_shop_order(), Rules.fish_price), "fish shop price order") and ok
	var hats := Rules.hat_shop_order()
	ok = _check(hats.size() == Rules.HAT_COUNT + 1 and hats[0] == -1, "hat shop keeps off first") and ok
	ok = _check(_prices_rise(hats.slice(1), Rules.hat_price), "hat shop price order") and ok
	ok = _check(_unlocked_lead(), "unlocked cosmetics lead the row") and ok
	print("[shop] fish common=%d rare=%d legendary=%d" % [fish_counts[0], fish_counts[1], fish_counts[2]])
	print("[shop] hats common=%d rare=%d legendary=%d" % [hat_counts[0], hat_counts[1], hat_counts[2]])
	print("[shop] ok=%s" % ok)
	quit(0 if ok else 1)


func _unlocked_lead() -> bool:
	var legendary_hat := -1
	var cheap_hat := -1
	for i in Rules.HAT_COUNT:
		if legendary_hat < 0 and Rules.hat_price(i) == 1000:
			legendary_hat = i
		if cheap_hat < 0 and Rules.hat_price(i) == 250:
			cheap_hat = i
	if legendary_hat < 0 or cheap_hat < 0:
		return false
	var hats := Rules.hat_shop_order(PackedInt32Array([legendary_hat]))
	if hats.size() != Rules.HAT_COUNT + 1 or hats[0] != -1 or hats[1] != legendary_hat or hats[2] != cheap_hat:
		return false
	if not _prices_rise(hats.slice(2), Rules.hat_price):
		return false
	var legendary_fish := -1
	for i in range(Rules.FREE_FISH, Rules.FISH_COUNT):
		if Rules.fish_price(i) == 2000:
			legendary_fish = i
			break
	if legendary_fish < 0:
		return false
	var fish := Rules.fish_shop_order(PackedInt32Array([legendary_fish]))
	if fish.size() != Rules.FISH_COUNT or fish[Rules.FREE_FISH] != legendary_fish:
		return false
	for i in Rules.FREE_FISH:
		if fish[i] != i:
			return false
	if not _prices_rise(fish.slice(Rules.FREE_FISH + 1), Rules.fish_price):
		return false
	for id in fish.slice(Rules.FREE_FISH + 1):
		if int(id) == legendary_fish:
			return false
	return true


func _prices_rise(order: PackedInt32Array, price_of: Callable) -> bool:
	var prev := -1
	var prev_index := -1
	for id in order:
		var price := int(price_of.call(int(id)))
		if price < prev:
			return false
		if price == prev and int(id) < prev_index:
			return false
		prev = price
		prev_index = int(id)
	return true


func _check(passed: bool, label: String) -> bool:
	if not passed:
		print("[shop] FAIL %s" % label)
	return passed
