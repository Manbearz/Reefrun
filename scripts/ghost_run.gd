class_name GhostRun
extends RefCounted

const VERSION := 1
const PHYSICS_VERSION := 1
const COURSE_VERSION := 1

var version: int = VERSION
var physics_version: int = PHYSICS_VERSION
var course_version: int = COURSE_VERSION
var course_seed: int = 0
var player_name: String = "YOU"
var fish_id: String = "fish_blue"
var flap_ticks: PackedInt32Array = PackedInt32Array()
var death_tick: int = -1
var score: int = 0


func is_compatible() -> bool:
	return (
		version == VERSION
		and physics_version == RR.PHYSICS_VERSION
		and course_version == RR.COURSE_VERSION
	)
