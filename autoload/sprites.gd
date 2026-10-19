extends Node

var textures: Dictionary = {}
var _boot_ids: PackedStringArray = PackedStringArray()


func _ready() -> void:
	# Names only. The startup screen decodes the pictures across frames so the
	# first paint is not stuck behind the full sprite set.
	_boot_ids = _scan_sprite_ids()


func boot_ids() -> PackedStringArray:
	return _boot_ids


func sprite_path(id: String) -> String:
	return "res://assets/sprites/%s.png" % id


func remember(id: String, texture: Texture2D) -> void:
	if texture:
		textures[id] = texture


func peek(id: String) -> Texture2D:
	return textures.get(id) as Texture2D


func _scan_sprite_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	var seen := {}
	var dir := DirAccess.open("res://assets/sprites")
	if dir == null:
		return ids
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		var name := file.replace(".remap", "")
		if name.ends_with(".png"):
			var id := name.get_basename()
			if not seen.has(id):
				seen[id] = true
				ids.append(id)
		file = dir.get_next()
	dir.list_dir_end()
	return ids


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
	var found := peek(id)
	if found:
		return found
	# Direct scene play skips the startup screen, so load this one picture on demand.
	_ensure_tex(id)
	return peek(id)
