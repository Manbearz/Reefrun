class_name RR
extends Object

const VIEW_W := 540.0
const VIEW_H := 960.0
const SURFACE_H := 48.0
const GROUND_H := 157.0
const PLAY_TOP := 53.0
const PLAY_BOTTOM := 803.0
# The ground sprite is drawn this far past the screen bottom so its edge stays cropped.
const GROUND_BLEED := 18.0
# Floor collision sits just below the death line, same offset the 960px layout used.
const FLOOR_DROP := 24.0
const FLOOR_THICK := 80.0
const PLAYER_X := 108.0
const COUNTDOWN := 3.0
const LOBBY_SECS := 5.0
const UNLIMITED_LOBBY_SECS := 8.0
const UNLIMITED_BOARD_SECS := 3.0

# Flappy Royale values scaled to this 960px playfield.
const GRAVITY := 1840.0
const FLAP := 573.0
const PIPE_SPEED := 200.0
const GAP := 211.0
const FIRST_PIPE := 1.8
const PIPE_INTERVAL := 1.5
const TERMINAL := 1040.0
const FISH_SCALE := 0.64
const FISH_HIT := 18.0
const FISH_BODY := 40.0
const GHOST_ALPHA := 0.16
const PIPE_SCALE := 0.427
const PIPE_JOIN := 0.085
const PIPE_HIT_WIDTH := 0.86
const PIPE_LIP_INSET := 0.0
const GHOST_COUNT := 99
const GHOST_DRAW := 24
# Opening seeded chunk. Both modes append further chunks, so a run is not capped here.
const PIPE_COUNT := 80
const PHYSICS_VERSION := 1
const COURSE_VERSION := 1
# VIEW_W+lead(80) + cull(120) + PLAYER_X + pipe width, divided by spacing (PIPE_SPEED*INTERVAL=300), plus spare.
const PIPE_POOL_SIZE := 12
# Daily Challenge still starts a volley every this many spawned pipes.
# Unlimited mode uses DeepDiveConfig for harpoons and Deep Dives.
const HARPOON_EVERY := 20
const HARPOON_WARN := 2.0
const HARPOON_SHOTS := 3
const HARPOON_LANES := 4
const HARPOON_PER_LANE := 3
const HARPOON_SCALE_X := 0.62
const HARPOON_SCALE_Y := 0.32
const HARPOON_FRAME := 0.02
const HARPOON_HOLD := 0.5

const FREE_FISH := 6
const FISH_COUNT := 70
const RARITY_COMMON := 0
const RARITY_RARE := 1
const RARITY_LEGENDARY := 2
const HAT_TIER_PRICE: PackedInt32Array = [250, 500, 1000]
const FISH_TIER_PRICE: PackedInt32Array = [500, 1000, 2000]
# Index matches FISH_IDS. The first FREE_FISH entries stay free regardless of tier.
const FISH_RARITY: PackedInt32Array = [
	0, 0, 0, 0, 0, 0, 0, 0, 1, 1,
	0, 0, 1, 0, 0, 0, 0, 0, 2, 0,
	0, 1, 2, 0, 1, 1, 0, 0, 0, 1,
	1, 1, 0, 1, 1, 1, 1, 0, 1, 0,
	1, 0, 2, 0, 0, 2, 0, 0, 1, 0,
	1, 0, 0, 0, 2, 1, 0, 0, 1, 1,
	2, 0, 2, 0, 2, 1, 1, 1, 1, 0,
]
# Index matches hat_00 .. hat_87.
const HAT_RARITY: PackedInt32Array = [
	2, 0, 1, 0, 1, 0, 0, 0, 1, 2,
	0, 0, 1, 0, 1, 1, 1, 0, 0, 1,
	1, 0, 0, 0, 1, 0, 0, 0, 0, 1,
	1, 0, 1, 1, 0, 1, 1, 0, 1, 2,
	2, 1, 1, 1, 1, 2, 2, 0, 0, 0,
	0, 1, 1, 1, 0, 0, 1, 1, 1, 2,
	1, 2, 0, 0, 0, 0, 2, 2, 0, 1,
	1, 1, 0, 1, 1, 0, 1, 1, 2, 1,
	1, 2, 2, 0, 2, 1, 1, 2,
]
const FISH_IDS: PackedStringArray = [
	"fish_blue", "fish_clown", "fish_yellow", "fish_green", "fish_pink", "fish_purple",
	"fish_06", "fish_07", "fish_08", "fish_09", "fish_10", "fish_11", "fish_12", "fish_13",
	"fish_14", "fish_15", "fish_16", "fish_17", "fish_18", "fish_19", "fish_20", "fish_21",
	"fish_22", "fish_23", "fish_24", "fish_25", "fish_26", "fish_27", "fish_28", "fish_29",
	"fish_30", "fish_31", "fish_32", "fish_33", "fish_34", "fish_35", "fish_36", "fish_37",
	"fish_38", "fish_39", "fish_40", "fish_41", "fish_42", "fish_43", "fish_44", "fish_45",
	"fish_46", "fish_47", "fish_48", "fish_49", "fish_50", "fish_51", "fish_52", "fish_53",
	"fish_54", "fish_55", "fish_56", "fish_57", "fish_58", "fish_59", "fish_60", "fish_61",
	"fish_62", "fish_63", "fish_64", "fish_65", "fish_66", "fish_67", "fish_68", "fish_69",
]
const FISH_NAMES: PackedStringArray = [
	"Blue Tang", "Clown", "Goldie", "Kelp", "Pinkfin", "Violet"
]
const HAT_COUNT := 88
const HAT_SCALE := 0.185
const GAME_HAT_SCALE := 0.24
const HAT_BRIM := 0.46
const COIN_EVERY := 5
const PIPE_IDS: PackedStringArray = [
	"pipe_kelp", "pipe_blue", "pipe_wood", "pipe_metal", "pipe_sand", "pipe_purple"
]
const GHOST_NAMES: PackedStringArray = [
	"Nori", "Bubbles", "Kelp", "Coral", "Finn", "Pearl", "Tide", "Mako",
	"Goby", "Waverly", "Splash", "Marlin", "Reef", "Anemone", "Sardine",
	"Pogo", "Drift", "Brine", "Nerissa", "Scooter", "Lumen", "Pebble",
	"Current", "Dory", "Skipper", "Mussel", "Lagoon", "Comet", "Barnacle",
	"Gill", "Nixie", "Triton", "Foam", "Cove", "Pike", "Sable"
]


# Vertical band the harpoon volley covers. Four lanes share it, and the
# lowest lane reaches the playable water above the ground and the home indicator.
static func harpoon_band() -> Vector2:
	var top := PLAY_TOP + 10.0
	var bottom := screen_bottom() - 108.0
	if bottom < top + 360.0:
		bottom = top + 360.0
	return Vector2(top, bottom)


static func harpoon_lane_height() -> float:
	var band := harpoon_band()
	return (band.y - band.x) / float(HARPOON_LANES)


static func harpoon_lane_center(lane: int) -> float:
	var band := harpoon_band()
	var index := clampi(lane, 0, HARPOON_LANES - 1)
	return band.x + harpoon_lane_height() * (float(index) + 0.5)


static func harpoon_lane_y(lane: int, slot: int) -> float:
	var band := harpoon_band()
	var height := harpoon_lane_height()
	var index := clampi(lane, 0, HARPOON_LANES - 1)
	var top := band.x + height * float(index)
	var along := (float(clampi(slot, 0, HARPOON_PER_LANE - 1)) + 0.5) / float(HARPOON_PER_LANE)
	# The lowest lane's bottom spear sits near the floor of that lane so the
	# old gap above the ground is part of the pattern, not a hiding spot.
	if index == HARPOON_LANES - 1:
		along = lerpf(0.18, 0.92, float(clampi(slot, 0, HARPOON_PER_LANE - 1)) / float(HARPOON_PER_LANE - 1))
	return top + height * along


static func harpoon_lane_of(y: float) -> int:
	var band := harpoon_band()
	return clampi(int((y - band.x) / harpoon_lane_height()), 0, HARPOON_LANES - 1)


static func screen_bottom() -> float:
	# KEEP_WIDTH on a tall phone grows the viewport past VIEW_H. Desktop KEEP
	# stays at 540x960, so this returns VIEW_H and the original layout is unchanged.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return VIEW_H
	var visible := tree.root.get_visible_rect().size
	if visible.x < VIEW_W * 0.5 or visible.x > VIEW_W * 1.5:
		return VIEW_H
	if visible.y < VIEW_H:
		return VIEW_H
	return visible.y


static func screen_size() -> Vector2:
	return Vector2(VIEW_W, screen_bottom())


# Portrait phones keep this width. 16:9 is exactly VIEW_H. A taller ratio
# adds visible water below the original layout instead of stretching it.
static func portrait_content_height(long_over_short: float) -> float:
	return VIEW_W * long_over_short


# Safe area in content-viewport pixels. Desktop and headless windows report
# no inset, so existing positions stay put. A bad reading cannot eat more
# than a fifth of the screen.
static func display_insets(screen: Vector2) -> Vector4:
	var window := DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0 or screen.x <= 0.0 or screen.y <= 0.0:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var sx := screen.x / float(window.x)
	var sy := screen.y / float(window.y)
	var right := float(window.x - safe.position.x - safe.size.x)
	var bottom := float(window.y - safe.position.y - safe.size.y)
	return Vector4(
		clampf(safe.position.x * sx, 0.0, screen.x * 0.2),
		clampf(safe.position.y * sy, 0.0, screen.y * 0.2),
		clampf(right * sx, 0.0, screen.x * 0.2),
		clampf(bottom * sy, 0.0, screen.y * 0.2)
	)


# One scale for both axes, centered in the space left after the safe area.
# The returned rect has the art's proportions and stays inside the screen.
static func uniform_fit(art: Vector2, screen: Vector2, margins: Vector4) -> Rect2:
	var avail_w := maxf(1.0, screen.x - margins.x - margins.z)
	var avail_h := maxf(1.0, screen.y - margins.y - margins.w)
	var scale := minf(avail_w / maxf(art.x, 1.0), avail_h / maxf(art.y, 1.0))
	var size := art * scale
	var origin := Vector2(margins.x, margins.y) + Vector2(avail_w - size.x, avail_h - size.y) * 0.5
	return Rect2(origin, size)


static func lobby_length(show_missions: bool) -> float:
	if show_missions:
		return UNLIMITED_LOBBY_SECS
	return LOBBY_SECS


static func lobby_fold_due(elapsed: float, show_missions: bool) -> bool:
	return show_missions and elapsed >= UNLIMITED_BOARD_SECS


static func lobby_finished(elapsed: float, length: float) -> bool:
	return elapsed >= length


static func fish_price(index: int) -> int:
	if index < FREE_FISH:
		return 0
	return _tier_price(FISH_TIER_PRICE, _rarity_at(FISH_RARITY, index))


static func hat_price(index: int) -> int:
	return _tier_price(HAT_TIER_PRICE, _rarity_at(HAT_RARITY, index))


# Shop rows: unlocked items sit first, then locked items. Each group is cheapest first.
# Equal prices keep the original index order. Hats reserve index -1 for Off.
static func fish_shop_order(owned: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	return _shop_order(FISH_IDS.size(), fish_price, func(index: int) -> bool:
		if index < FREE_FISH:
			return true
		return owned.has(index)
	)


static func hat_shop_order(owned: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	var order := _shop_order(HAT_COUNT, hat_price, func(index: int) -> bool:
		return owned.has(index)
	)
	order.insert(0, -1)
	return order


static func _shop_order(count: int, price_of: Callable, owns: Callable) -> PackedInt32Array:
	var ids: Array[int] = []
	ids.resize(count)
	for i in count:
		ids[i] = i
	ids.sort_custom(func(a: int, b: int) -> bool:
		var owned_a := bool(owns.call(a))
		var owned_b := bool(owns.call(b))
		if owned_a != owned_b:
			return owned_a
		var pa := int(price_of.call(a))
		var pb := int(price_of.call(b))
		if pa == pb:
			return a < b
		return pa < pb
	)
	var packed := PackedInt32Array()
	packed.resize(ids.size())
	for i in ids.size():
		packed[i] = ids[i]
	return packed


static func _rarity_at(table: PackedInt32Array, index: int) -> int:
	if index < 0 or index >= table.size():
		return RARITY_COMMON
	return clampi(table[index], RARITY_COMMON, RARITY_LEGENDARY)


static func _tier_price(table: PackedInt32Array, rarity: int) -> int:
	if rarity < 0 or rarity >= table.size():
		return table[0]
	return table[rarity]


static func hat_id(index: int) -> String:
	return "hat_%02d" % index


static func hat_anchor(skin: String, tex_size: Vector2 = Vector2.ZERO) -> Vector2:
	match skin:
		"fish_blue":
			return Vector2(21.0, -25.0)
		"fish_clown":
			return Vector2(18.0, -24.0)
		"fish_yellow":
			return Vector2(16.0, -25.0)
		"fish_green":
			return Vector2(13.0, -27.0)
		"fish_pink":
			return Vector2(17.0, -24.0)
		"fish_purple":
			return Vector2(16.0, -25.0)
		"fish_18":
			return Vector2(-12.0, -28.0)
		"fish_22":
			return Vector2(8.0, -18.0)
		_:
			var w := tex_size.x if tex_size.x > 1.0 else 150.0
			var h := tex_size.y if tex_size.y > 1.0 else 130.0
			return Vector2(w * 0.15, -h * 0.20)


static func hat_local_scale(fish_sprite_scale: float) -> float:
	return GAME_HAT_SCALE / maxf(fish_sprite_scale, 0.001)


static func hat_brim_offset(hat_tex: Texture2D) -> Vector2:
	if hat_tex == null:
		return Vector2.ZERO
	return Vector2(1.5, -hat_tex.get_height() * HAT_BRIM)
