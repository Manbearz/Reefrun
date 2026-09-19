extends RefCounted

const GhostBankScript := preload("res://scripts/ghost_bank.gd")
const LocalRepoScript := preload("res://scripts/local_ghost_repository.gd")
const SupaRepoScript := preload("res://scripts/backend/supabase_ghost_repository.gd")
const CompositeRepoScript := preload("res://scripts/composite_ghost_repository.gd")
const ConfigScript := preload("res://scripts/backend/supabase_config.gd")
const FallbackScript := preload("res://scripts/fallback_ghost_factory.gd")
const GhostRunScript := preload("res://scripts/ghost_run.gd")

var bank
var repo


func _init() -> void:
	bank = GhostBankScript.new()
	repo = _make_repo()


func _make_repo():
	var local = LocalRepoScript.new(bank)
	if not ConfigScript.is_configured():
		return local
	return CompositeRepoScript.new([SupaRepoScript.new(), local])


func fill_competitors(course_seed: int, layout: Array, local_player_id: String, local_run_id: String = "") -> Array:
	var picked: Array = []
	var seen := {}
	for run in repo.get_runs_for_seed(course_seed):
		if not _accept_real(run, course_seed, local_player_id, local_run_id, seen):
			continue
		if run.run_id != "":
			seen[run.run_id] = true
		picked.append(run)
		if picked.size() >= RR.GHOST_COUNT:
			break
	var slot := 0
	while picked.size() < RR.GHOST_COUNT:
		picked.append(FallbackScript.make(course_seed, slot, layout))
		slot += 1
	return picked


func save_local_run(run) -> void:
	if bank:
		bank.save_run(run)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var backend: Node = tree.root.get_node_or_null("/root/Backend")
	if backend and backend.has_method("upload_ghost_run"):
		backend.upload_ghost_run(run)


func _accept_real(run, course_seed: int, local_player_id: String, local_run_id: String, seen: Dictionary) -> bool:
	if run == null:
		return false
	if not run.is_valid():
		return false
	if run.course_seed != course_seed:
		return false
	if run.source == GhostRunScript.SOURCE_FALLBACK:
		return false
	if local_player_id != "" and run.player_id == local_player_id:
		return false
	if local_run_id != "" and run.run_id != "" and run.run_id == local_run_id:
		return false
	if run.run_id != "" and seen.has(run.run_id):
		return false
	return true
