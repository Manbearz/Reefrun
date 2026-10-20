class_name DeepDiveConfig
extends RefCounted

# Unlimited-mode schedule. A harpoon stage is one existing 3-shot volley,
# not a five-pipe sequence. Daily Challenge keeps RR.HARPOON_EVERY.
const HARPOON_FIRST_PIPE := 15
const HARPOON_PIPE_STRIDE := 30
const DIVE_FIRST_PIPE := 30
const DIVE_PIPE_STRIDE := 30

const DURATION := 20.0
const TRANSITION_IN := 2.0
const COUNTDOWN_STEP := 0.75
const TRANSITION_OUT := 1.45
const RESUME_SECS := 0.5
const HARPOON_CLEANUP := 0.35

const FISH_Y := 300.0
const SIDE_MARGIN := 46.0
# Five lanes. Lane 3 is the center. One tap moves exactly one lane.
const LANE_COUNT := 5
const CENTER_LANE := 3
const LANE_GAP := 100.0
const LANE_SLIDE := 0.12
# Half-width of a one-lane opening. Wider than the fish, so a lane is safe
# without shrinking the fish sprite.
const LANE_CLEAR := 42.0

const MIN_GAP := 80.0
const MIN_REACTION_TRAVEL := 780.0
# One falling speed for every dive. Obstacles and the surrounding water
# scroll upward at this rate while the fish stays on screen.
const DEEP_DIVE_SPEED := 786.0
# Matches the speed so the time between openings stays the same on every dive.
const DEEP_DIVE_SPACING := 733.0


static func harpoon_pipe(index: int) -> int:
	return HARPOON_FIRST_PIPE + HARPOON_PIPE_STRIDE * index


static func dive_pipe(index: int) -> int:
	return DIVE_FIRST_PIPE + DIVE_PIPE_STRIDE * index


static func intro_total() -> float:
	return TRANSITION_IN + COUNTDOWN_STEP * 3.0


static func lane_center(lane: int) -> float:
	var clamped := clampi(lane, 1, LANE_COUNT)
	return RR.VIEW_W * 0.5 + float(clamped - CENTER_LANE) * LANE_GAP


static func one_lane_gap() -> float:
	return LANE_CLEAR * 2.0


# How many lane changes fit in the seconds between obstacles, leaving a
# short beat so the fish is not required to leave before the last opening.
static func lanes_reachable(seconds: float) -> int:
	var usable := maxf(seconds - 0.30, LANE_SLIDE)
	return maxi(1, int(floor(usable / LANE_SLIDE)))


static func profile(dive_number: int) -> Dictionary:
	var n := maxi(1, dive_number)
	var kinds := PackedStringArray(["net", "pillar"])
	if n == 2:
		kinds = PackedStringArray(["net", "pillar", "mine"])
	elif n == 3:
		kinds = PackedStringArray(["net", "pillar", "mine", "jelly"])
	elif n >= 4:
		kinds = PackedStringArray(["net", "pillar", "mine", "jelly", "wreck"])
	var lead := RR.screen_bottom() - FISH_Y + 220.0
	return {
		"scroll": DEEP_DIVE_SPEED,
		"min_gap": one_lane_gap(),
		"spacing": DEEP_DIVE_SPACING,
		"kinds": kinds,
		"duration": DURATION,
		"first_travel": maxf(MIN_REACTION_TRAVEL, lead),
	}
