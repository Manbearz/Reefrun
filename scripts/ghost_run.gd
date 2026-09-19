class_name GhostRun
extends RefCounted

const VERSION := 1
const PHYSICS_VERSION := 1
const COURSE_VERSION := 1
const SOURCE_REAL := "REAL_PLAYER"
const SOURCE_FALLBACK := "FALLBACK"

var version: int = VERSION
var physics_version: int = PHYSICS_VERSION
var course_version: int = COURSE_VERSION
var course_seed: int = 0
var display_name: String = "YOU"
var player_name: String = "YOU"
var fish_id: String = "fish_blue"
var hat_id: int = -1
var flap_ticks: PackedInt32Array = PackedInt32Array()
var death_tick: int = -1
var score: int = 0
var source: String = SOURCE_REAL
var run_id: String = ""
var player_id: String = ""
var created_at: int = 0


func label() -> String:
	var name := display_name.strip_edges()
	if name.is_empty():
		name = player_name.strip_edges()
	if name.is_empty():
		return "YOU"
	return name


func is_compatible() -> bool:
	return (
		version == VERSION
		and physics_version == RR.PHYSICS_VERSION
		and course_version == RR.COURSE_VERSION
	)


func is_valid() -> bool:
	if not is_compatible():
		return false
	if score < 0:
		return false
	if death_tick < -1:
		return false
	for i in flap_ticks.size():
		if flap_ticks[i] < 0:
			return false
		if i > 0 and flap_ticks[i] < flap_ticks[i - 1]:
			return false
	return true
