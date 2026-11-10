extends Node

var textures: Dictionary = {}
var _boot_ids: PackedStringArray = PackedStringArray()
var _gameplay_ids: PackedStringArray = PackedStringArray()
var _gameplay_left: PackedStringArray = PackedStringArray()
var _gameplay_started := false

# Files that stay on disk for the art pipeline, but nothing in the game draws them.
# Leaving them out of boot keeps them out of texture memory.
const _UNUSED := {
	"alpha_dash": true,
	"btn_settings": true,
	"btn_trophy": true,
	"chest": true,
	"coral_cluster": true,
	"coral_orange": true,
	"coral_pink": true,
	"coral_purple": true,
	"crown_bronze": true,
	"daily_missions_card": true,
	"dolphin": true,
	"flag_alert": true,
	"flag_stop": true,
	"flag_warn": true,
	"highscore_overlay": true,
	"main_daily_missions": true,
	"pearl": true,
	"pipe_blue_body": true,
	"pipe_coral": true,
	"pipe_coral_body": true,
	"pipe_moss": true,
	"pipe_moss_body": true,
	"pipe_wood_body": true,
	"power_bubble": true,
	"power_fish": true,
	"power_magnet": true,
	"power_shield": true,
	"puffer": true,
	"school_a": true,
	"shark": true,
	"shell_blue": true,
	"shell_conch": true,
	"shell_mystery": true,
	"shell_pink": true,
	"skull": true,
	"spear_long": true,
	"spear_mid": true,
	"spear_short": true,
	"splash_a": true,
	"splash_c": true,
	"weed_a": true,
	"weed_b": true,
	"weed_c": true,
	"weed_d": true,
}

# Needed before the first pipe, pause, or death, but not to draw the menu.
const _GAMEPLAY := {
	"bubbles_small": true,
	"btn_close": true,
	"btn_main_menu": true,
	"btn_play": true,
	"btn_share_small": true,
	"coin_ad_overlay": true,
	"death_overlay": true,
	"harpoon_00": true,
	"harpoon_01": true,
	"harpoon_02": true,
	"harpoon_03": true,
	"harpoon_04": true,
	"harpoon_05": true,
	"harpoon_06": true,
	"harpoon_07": true,
	"harpoon_08": true,
	"harpoon_09": true,
	"harpoon_10": true,
	"jump_overlay": true,
	"pipe_blue": true,
	"pipe_kelp": true,
	"pipe_metal": true,
	"pipe_purple": true,
	"pipe_sand": true,
	"pipe_wood": true,
	"shark_far": true,
	"share_overlay": true,
}


func _ready() -> void:
	# Names only. The startup screen decodes the menu pictures across frames.
	# Gameplay pictures start after the menu is up, one import per frame.
	_boot_ids = _scan_sprite_ids()
	set_process(false)


func boot_ids() -> PackedStringArray:
	return _boot_ids


func gameplay_ids() -> PackedStringArray:
	return _gameplay_ids


func start_gameplay() -> void:
	if _gameplay_started:
		return
	_gameplay_started = true
	for id in _gameplay_ids:
		if textures.has(id):
			continue
		var path := sprite_path(id)
		if not ResourceLoader.exists(path):
			push_warning("[sprites] missing gameplay texture %s" % path)
			continue
		var err := ResourceLoader.load_threaded_request(path, "", false)
		if err == OK or err == ERR_ALREADY_EXISTS or err == ERR_BUSY:
			_gameplay_left.append(id)
		else:
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
				_gameplay_left.append(id)
			else:
				_ensure_tex(id)
	set_process(not _gameplay_left.is_empty())


func gameplay_ready() -> bool:
	return _gameplay_started and _gameplay_left.is_empty()


func await_gameplay() -> void:
	start_gameplay()
	var frames := 0
	while not _gameplay_left.is_empty() and frames < 600:
		frames += 1
		if get_tree() == null:
			break
		await get_tree().process_frame
	if _gameplay_left.is_empty():
		return
	for id in _gameplay_left:
		_ensure_tex(id)
	_gameplay_left = PackedStringArray()
	set_process(false)


func _process(_delta: float) -> void:
	_pump_gameplay(1)


func _pump_gameplay(budget: int) -> void:
	if _gameplay_left.is_empty():
		set_process(false)
		return
	var still := PackedStringArray()
	var taken := 0
	for id in _gameplay_left:
		if taken >= budget:
			still.append(id)
			continue
		var path := sprite_path(id)
		var status := ResourceLoader.load_threaded_get_status(path)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				var resource := ResourceLoader.load_threaded_get(path)
				if resource is Texture2D:
					textures[id] = resource
				else:
					_ensure_tex(id)
				taken += 1
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_ensure_tex(id)
				taken += 1
			_:
				still.append(id)
	_gameplay_left = still
	if _gameplay_left.is_empty():
		set_process(false)


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
			if seen.has(id) or _UNUSED.has(id):
				file = dir.get_next()
				continue
			seen[id] = true
			if _GAMEPLAY.has(id):
				_gameplay_ids.append(id)
			else:
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
