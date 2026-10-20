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


static func tex(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id] as Texture2D
	var path := "res://assets/deep_dive/%s.png" % id
	var loaded: Texture2D = null
	if ResourceLoader.exists(path):
		loaded = load(path) as Texture2D
	_cache[id] = loaded
	return loaded


static func preload_all() -> void:
	for id in IDS:
		tex(id)


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
