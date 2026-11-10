class_name DiveAssets
extends RefCounted

const IDS: PackedStringArray = [
	"banner_deep_dive", "banner_seconds", "count_3", "count_2", "count_1",
	"net_a", "net_b", "net_c", "net_d",
	"mine_a", "mine_b", "mine_c", "mine_d", "mine_chain_a", "mine_chain_b",
	"rock_a", "rock_b", "rock_c", "rock_d", "rock_e", "rock_f", "rock_g", "rock_h", "arch",
	"jelly_purple", "jelly_blue", "jelly_orange", "jelly_small",
	"planks", "spears",
	"bubbles_a", "bubbles_b", "bubbles_c", "bubbles_d",
	"seaweed_a", "seaweed_b", "seaweed_c", "seaweed_d", "seaweed_e",
	"coral_a", "coral_b", "coral_c", "coral_d",
]

static var _cache: Dictionary = {}
static var _pending: Dictionary = {}


static func tex(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id] as Texture2D
	var path := "res://assets/deep_dive/%s.png" % id
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
		var spins := 0
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS and spins < 200:
			OS.delay_msec(1)
			spins += 1
			status = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_take(id, path)
			return _cache.get(id) as Texture2D
	var loaded: Texture2D = null
	if ResourceLoader.exists(path):
		loaded = load(path) as Texture2D
	_cache[id] = loaded
	_pending.erase(id)
	return loaded


static func begin_preload() -> void:
	for id in IDS:
		if _cache.has(id):
			continue
		var path := "res://assets/deep_dive/%s.png" % id
		if not ResourceLoader.exists(path):
			_cache[id] = null
			continue
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_take(id, path)
			continue
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			ResourceLoader.load_threaded_request(path, "", false)
		_pending[id] = path


static func pump(budget: int = 1) -> void:
	var taken := 0
	var finished: Array[String] = []
	for id in _pending.keys():
		if taken >= budget:
			break
		var path := str(_pending[id])
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_take(id, path)
			finished.append(id)
			taken += 1
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_cache[id] = load(path) as Texture2D
			finished.append(id)
			taken += 1
	for id in finished:
		_pending.erase(id)


static func idle() -> bool:
	return _pending.is_empty()


static func finish() -> void:
	var spins := 0
	while not _pending.is_empty() and spins < 200:
		pump(IDS.size())
		if _pending.is_empty():
			return
		OS.delay_msec(1)
		spins += 1
	if not _pending.is_empty():
		preload_all()


static func preload_all() -> void:
	for id in IDS:
		tex(id)


static func _take(id: String, path: String) -> void:
	if _cache.has(id):
		_pending.erase(id)
		return
	var resource := ResourceLoader.load_threaded_get(path)
	_cache[id] = resource as Texture2D
	_pending.erase(id)


static func net_id(variant: int) -> String:
	var names := ["net_a", "net_b", "net_c", "net_d"]
	return names[posmod(variant, names.size())]


static func rock_id(variant: int) -> String:
	var names := ["rock_a", "rock_b", "rock_c", "rock_d", "rock_e", "rock_f", "rock_g", "rock_h"]
	return names[posmod(variant, names.size())]


static func mine_id(variant: int) -> String:
	var names := ["mine_a", "mine_b", "mine_c", "mine_d", "mine_chain_a", "mine_chain_b"]
	return names[posmod(variant, names.size())]


static func jelly_id(variant: int) -> String:
	var names := ["jelly_purple", "jelly_blue", "jelly_orange", "jelly_small"]
	return names[posmod(variant, names.size())]


static func decor_id(variant: int) -> String:
	var names := ["seaweed_a", "seaweed_c", "seaweed_e", "coral_a", "coral_c", "bubbles_b", "bubbles_d", "coral_b"]
	return names[posmod(variant, names.size())]
