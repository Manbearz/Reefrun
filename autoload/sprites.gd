extends Node

var textures: Dictionary = {}


func _ready() -> void:
	_load_from_dir()
	_load_known()


func _load_from_dir() -> void:
	var dir := DirAccess.open("res://assets/sprites")
	if dir == null:
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		var name := file.replace(".remap", "")
		if name.ends_with(".png"):
			var id := name.get_basename()
			var tex := load("res://assets/sprites/%s.png" % id) as Texture2D
			if tex:
				textures[id] = tex
		file = dir.get_next()
	dir.list_dir_end()


func _load_known() -> void:
	const IDS: PackedStringArray = [
		"background", "ground",
		"btn_play", "btn_close", "btn_settings", "btn_trophy",
		"fish_blue", "fish_clown", "fish_yellow", "fish_green", "fish_pink", "fish_purple",
		"pipe_kelp", "pipe_blue", "pipe_wood", "pipe_metal", "pipe_sand", "pipe_purple",
		"crown_gold", "crown_silver", "crown_bronze",
		"splash_a", "splash_b", "splash_c", "bubbles_small",
		"shark_far",
		"spear_long", "spear_mid", "spear_short",
		"harpoon_00", "harpoon_01", "harpoon_02", "harpoon_03", "harpoon_04",
		"harpoon_05", "harpoon_06", "harpoon_07", "harpoon_08", "harpoon_09",
		"harpoon_10",
		"death_overlay", "main_menu_overlay", "highscore_overlay", "btn_main_menu", "coin_ad_overlay",
		"share_overlay", "btn_share_small",
		"coin",
	]
	for id in IDS:
		_ensure_tex(id)
	for i in 40:
		_ensure_tex("hat_%02d" % i)
	for d in 10:
		_ensure_tex("num_gold_%d" % d)
		_ensure_tex("num_white_%d" % d)
	for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
		_ensure_tex("alpha_%s" % ch)
	for id in [
		"alpha_excl", "alpha_at", "alpha_hash", "alpha_dollar", "alpha_pct",
		"alpha_caret", "alpha_amp", "alpha_star", "alpha_lparen", "alpha_rparen",
		"alpha_quest", "alpha_colon", "alpha_semi", "alpha_tilde", "alpha_slash",
		"alpha_bslash", "alpha_comma", "alpha_hyphen", "alpha_dash", "alpha_plus",
		"alpha_eq",
	]:
		_ensure_tex(id)


const GLYPH_IDS := {
	"!": "alpha_excl",
	"@": "alpha_at",
	"#": "alpha_hash",
	"$": "alpha_dollar",
	"%": "alpha_pct",
	"^": "alpha_caret",
	"&": "alpha_amp",
	"*": "alpha_star",
	"(": "alpha_lparen",
	")": "alpha_rparen",
	"?": "alpha_quest",
	":": "alpha_colon",
	";": "alpha_semi",
	"~": "alpha_tilde",
	"/": "alpha_slash",
	"\\": "alpha_bslash",
	",": "alpha_comma",
	"-": "alpha_hyphen",
	"+": "alpha_plus",
	"=": "alpha_eq",
}


func glyph(ch: String) -> Texture2D:
	if ch.length() != 1:
		return null
	var upper := ch.to_upper()
	if upper >= "A" and upper <= "Z":
		return tex("alpha_%s" % upper)
	if ch >= "0" and ch <= "9":
		return tex("num_white_%s" % ch)
	var id: String = GLYPH_IDS.get(ch, "")
	if id.is_empty():
		return null
	return tex(id)


func digit(ch: String) -> Texture2D:
	if ch.length() != 1 or ch < "0" or ch > "9":
		return glyph(ch)
	return tex("num_gold_%s" % ch)


func _ensure_tex(id: String) -> void:
	if textures.has(id):
		return
	var tex := load("res://assets/sprites/%s.png" % id) as Texture2D
	if tex:
		textures[id] = tex


func tex(id: String) -> Texture2D:
	return textures.get(id) as Texture2D
