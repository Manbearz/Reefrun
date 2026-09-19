extends SceneTree

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")
const GhostMatchScript := preload("res://scripts/ghost_match.gd")
const CourseBuilderScript := preload("res://scripts/course_builder.gd")


func _init() -> void:
	var configured := ConfigScript.is_configured()
	var built: Dictionary = CourseBuilderScript.generate(12)
	var filler = GhostMatchScript.new()
	var runs: Array = filler.fill_competitors(12, built["layout"], "local_test")
	var ok := runs.size() == RR.GHOST_COUNT
	print("[supabase] configured=%s fill=%d ok=%s" % [configured, runs.size(), ok])
	quit(0 if ok else 1)
