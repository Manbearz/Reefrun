extends RefCounted

const GhostBankScript := preload("res://scripts/ghost_bank.gd")
const LocalRepoScript := preload("res://scripts/local_ghost_repository.gd")
const SupaRepoScript := preload("res://scripts/backend/supabase_ghost_repository.gd")
const CompositeRepoScript := preload("res://scripts/composite_ghost_repository.gd")
const ConfigScript := preload("res://scripts/backend/supabase_config.gd")
const FallbackScript := preload("res://scripts/fallback_ghost_factory.gd")
const GhostRunScript := preload("res://scripts/ghost_run.gd")
const DailyChallengeScript := preload("res://scripts/daily_challenge.gd")

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


func fill_competitors(course_seed: int, layout: Array, local_player_id: String, local_run_id: String = "", challenge_id: String = "") -> Array:
	var picked := collect_reals(course_seed, local_player_id, local_run_id, challenge_id)
	var slot := 0
	while picked.size() < RR.GHOST_COUNT:
		picked.append(FallbackScript.make(course_seed, slot, layout, challenge_id))
		slot += 1
	return picked


func fill_spread(tree: SceneTree, course_seed: int, layout: Array, local_player_id: String, local_run_id: String = "", challenge_id: String = "") -> Array:
	var picked := collect_reals(course_seed, local_player_id, local_run_id, challenge_id)
	var slot := 0
	var made := 0
	while picked.size() < RR.GHOST_COUNT:
		picked.append(FallbackScript.make(course_seed, slot, layout, challenge_id))
		slot += 1
		made += 1
		if made % 8 == 0 and tree != null:
			await tree.process_frame
	return picked


func collect_reals(course_seed: int, local_player_id: String, local_run_id: String = "", challenge_id: String = "") -> Array:
	var picked: Array = []
	var seen := {}
	var challenge := {}
	if challenge_id != "":
		challenge = {"challenge_id": challenge_id, "course_seed": course_seed, "course_version": RR.COURSE_VERSION, "physics_version": RR.PHYSICS_VERSION}
	for run in _runs_from_repo(course_seed, challenge_id):
		if not _accept_real(run, course_seed, local_player_id, local_run_id, seen, challenge):
			continue
		if run.run_id != "":
			seen[run.run_id] = true
		picked.append(run)
		if picked.size() >= RR.GHOST_COUNT:
			break
	return picked


func save_local_run(run) -> void:
	if bank:
		bank.save_run(run)
	if run == null or str(run.challenge_id) == "":
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var backend: Node = tree.root.get_node_or_null("/root/Backend")
	if backend == null or not backend.has_method("upload_ghost_run"):
		return
	if backend.has_method("may_upload_ghost") and not backend.may_upload_ghost(run):
		return
	backend.upload_ghost_run(run)


func _runs_from_repo(course_seed: int, challenge_id: String) -> Array:
	var out: Array = []
	if repo == null:
		return out
	if challenge_id != "" and repo.has_method("get_runs_for_challenge"):
		for run in repo.get_runs_for_challenge(course_seed, challenge_id):
			out.append(run)
		return out
	if repo.has_method("get_runs_for_seed"):
		for run in repo.get_runs_for_seed(course_seed):
			out.append(run)
	return out


func _accept_real(run, course_seed: int, local_player_id: String, local_run_id: String, seen: Dictionary, challenge: Dictionary) -> bool:
	if run == null:
		return false
	if not run.is_valid():
		return false
	if run.course_seed != course_seed:
		return false
	if run.course_version != RR.COURSE_VERSION or run.physics_version != RR.PHYSICS_VERSION:
		return false
	if not challenge.is_empty() and not DailyChallengeScript.ghost_compatible(run, challenge):
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
