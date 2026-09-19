class_name RR
extends Object

const VIEW_W := 540.0
const VIEW_H := 960.0
const SURFACE_H := 48.0
const GROUND_H := 157.0
const PLAY_TOP := 53.0
const PLAY_BOTTOM := 803.0
const PLAYER_X := 108.0
const COUNTDOWN := 3.0
const LOBBY_SECS := 5.0

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
const PIPE_COUNT := 80
const PHYSICS_VERSION := 1
const COURSE_VERSION := 1
# VIEW_W+lead(80) + cull(120) + PLAYER_X + pipe width, divided by spacing (PIPE_SPEED*INTERVAL=300), plus spare.
const PIPE_POOL_SIZE := 12
const HARPOON_EVERY := 20
const HARPOON_WARN := 2.0
const HARPOON_SHOTS := 3
const HARPOON_PER_LANE := 3
const HARPOON_SCALE_X := 0.62
const HARPOON_SCALE_Y := 0.32
const HARPOON_FRAME := 0.02
const HARPOON_HOLD := 0.5

const FISH_IDS: PackedStringArray = [
	"fish_blue", "fish_clown", "fish_yellow", "fish_green", "fish_pink", "fish_purple"
]
const FISH_NAMES: PackedStringArray = [
	"Blue Tang", "Clown", "Goldie", "Kelp", "Pinkfin", "Violet"
]
const HAT_COUNT := 40
const HAT_PRICE := 50
const HAT_SCALE := 0.185
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


static func hat_id(index: int) -> String:
	return "hat_%02d" % index


static func hat_anchor(skin: String) -> Vector2:
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
		_:
			return Vector2(16.0, -25.0)


static func hat_local_scale(fish_sprite_scale: float) -> float:
	return HAT_SCALE / maxf(fish_sprite_scale, 0.001)


static func hat_brim_offset(hat_tex: Texture2D) -> Vector2:
	if hat_tex == null:
		return Vector2.ZERO
	return Vector2(1.5, -hat_tex.get_height() * HAT_BRIM)
