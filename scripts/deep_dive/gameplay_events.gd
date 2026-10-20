class_name GameplayEvents
extends RefCounted

signal state_changed(previous: int, current: int)

# One special event at a time. Unlimited mode only.
enum State {
	NORMAL,
	HARPOON_PENDING,
	HARPOON_WARNING,
	HARPOON_ACTIVE,
	HARPOON_CLEANUP,
	DIVE_PENDING,
	DIVE_TRANSITION_IN,
	DEEP_DIVE,
	DIVE_TRANSITION_OUT,
	RESUME_SWIMMING,
	GAME_OVER,
}

var state: int = State.NORMAL
var pipes_passed := 0
var next_harpoon_pipe := DeepDiveConfig.HARPOON_FIRST_PIPE
var next_dive_pipe := DeepDiveConfig.DIVE_FIRST_PIPE
var dive_number := 0
var dives_survived := 0
var dive_obstacles_dodged := 0
var dive_survival_time := 0.0
var active_dive_time := 0.0
var phase_time := 0.0
var paused := false
var token := 0
var fired_log: PackedStringArray = PackedStringArray()

var _queue: PackedStringArray = PackedStringArray()
var _consumed: Dictionary = {}
var _corridor := false


static func applies_to(mode: String, practice: bool) -> bool:
	return mode == "unlimited" and not practice


func reset() -> void:
	var prev := state
	state = State.NORMAL
	pipes_passed = 0
	next_harpoon_pipe = DeepDiveConfig.HARPOON_FIRST_PIPE
	next_dive_pipe = DeepDiveConfig.DIVE_FIRST_PIPE
	dive_number = 0
	dives_survived = 0
	dive_obstacles_dodged = 0
	dive_survival_time = 0.0
	active_dive_time = 0.0
	phase_time = 0.0
	paused = false
	token = 0
	fired_log = PackedStringArray()
	_queue = PackedStringArray()
	_consumed = {}
	_corridor = false
	if prev != State.NORMAL:
		state_changed.emit(prev, state)


func note_pipes_passed(count: int) -> void:
	if state == State.GAME_OVER or count <= pipes_passed:
		return
	while pipes_passed < count:
		pipes_passed += 1
		if pipes_passed == next_harpoon_pipe:
			_enqueue("harpoon", pipes_passed)
			next_harpoon_pipe += DeepDiveConfig.HARPOON_PIPE_STRIDE
		if pipes_passed == next_dive_pipe:
			_enqueue("dive", pipes_passed)
			next_dive_pipe += DeepDiveConfig.DIVE_PIPE_STRIDE


func set_paused(value: bool) -> void:
	paused = value


func set_corridor_clear(clear: bool) -> void:
	_corridor = clear


func notify_harpoon_phase(phase: int) -> void:
	if state == State.GAME_OVER:
		return
	if phase != State.HARPOON_WARNING and phase != State.HARPOON_ACTIVE:
		return
	if (
		state != State.HARPOON_PENDING
		and state != State.HARPOON_WARNING
		and state != State.HARPOON_ACTIVE
	):
		return
	_enter_state(phase)


func notify_harpoon_finished() -> void:
	if state != State.HARPOON_WARNING and state != State.HARPOON_ACTIVE:
		return
	phase_time = 0.0
	_enter_state(State.HARPOON_CLEANUP)


func notify_death() -> void:
	_queue = PackedStringArray()
	phase_time = 0.0
	active_dive_time = 0.0
	_enter_state(State.GAME_OVER)


func note_obstacles_dodged(count: int) -> void:
	if count <= 0 or state != State.DEEP_DIVE:
		return
	dive_obstacles_dodged += count


func tick(delta: float) -> void:
	if paused or state == State.GAME_OVER:
		return
	var guard := 0
	var step := maxf(delta, 0.0)
	while guard < 6:
		guard += 1
		var before := state
		_advance(step)
		if state == before:
			return
		step = 0.0


func pipes_allowed() -> bool:
	return state == State.NORMAL or state == State.RESUME_SWIMMING


func suppresses_flap() -> bool:
	return (
		state == State.DIVE_TRANSITION_IN
		or state == State.DEEP_DIVE
		or state == State.DIVE_TRANSITION_OUT
	)


func blocks_swim() -> bool:
	return suppresses_flap()


func ghosts_frozen() -> bool:
	return blocks_swim()


func scoring_allowed() -> bool:
	return not blocks_swim() and state != State.GAME_OVER


func steer_active() -> bool:
	return state == State.DEEP_DIVE


func queued_count() -> int:
	return _queue.size()


func intro_title_visible() -> bool:
	return state == State.DIVE_TRANSITION_IN and phase_time < DeepDiveConfig.TRANSITION_IN


func intro_count() -> int:
	if state != State.DIVE_TRANSITION_IN or phase_time < DeepDiveConfig.TRANSITION_IN:
		return 0
	var local := phase_time - DeepDiveConfig.TRANSITION_IN
	var step := int(local / DeepDiveConfig.COUNTDOWN_STEP)
	if step >= 3:
		return 0
	return 3 - step


func survived_visible() -> bool:
	return state == State.DIVE_TRANSITION_OUT


func seconds_left() -> int:
	var remain := DeepDiveConfig.DURATION - active_dive_time
	if remain <= 0.0001:
		return 0
	return ceili(remain - 0.0001)


func turn_amount() -> float:
	if state == State.DEEP_DIVE:
		return 1.0
	if state == State.DIVE_TRANSITION_IN:
		return clampf(phase_time / DeepDiveConfig.TRANSITION_IN, 0.0, 1.0)
	if state == State.DIVE_TRANSITION_OUT:
		return 1.0 - clampf(phase_time / DeepDiveConfig.TRANSITION_OUT, 0.0, 1.0)
	return 0.0


func depth_blend() -> float:
	if state == State.DEEP_DIVE:
		return 1.0
	if state == State.DIVE_TRANSITION_IN:
		return clampf(phase_time / DeepDiveConfig.TRANSITION_IN, 0.0, 1.0)
	if state == State.DIVE_TRANSITION_OUT:
		return 1.0 - clampf(phase_time / DeepDiveConfig.TRANSITION_OUT, 0.0, 1.0)
	if state == State.RESUME_SWIMMING:
		return 0.0
	return 0.0


func debug_queue_dive() -> void:
	if state == State.GAME_OVER or blocks_swim():
		return
	if state != State.NORMAL and state != State.HARPOON_CLEANUP and state != State.DIVE_PENDING:
		return
	_queue.insert(0, "dive")
	fired_log.append("dive:debug")


func debug_force_state(next: int) -> void:
	phase_time = 0.0
	if next == State.DEEP_DIVE:
		active_dive_time = 0.0
		if dive_number < 1:
			dive_number = 1
	_enter_state(next)


func _enqueue(kind: String, pipe: int) -> void:
	var key := "%s:%d" % [kind, pipe]
	if _consumed.has(key):
		return
	_consumed[key] = true
	_queue.append(kind)
	fired_log.append(key)


func _try_start_queued() -> void:
	if state != State.NORMAL or _queue.is_empty():
		return
	var kind := _queue[0]
	_queue.remove_at(0)
	if kind == "harpoon":
		_enter_state(State.HARPOON_PENDING)
	elif kind == "dive":
		dive_number += 1
		phase_time = 0.0
		_enter_state(State.DIVE_PENDING)


func _advance(delta: float) -> void:
	match state:
		State.NORMAL:
			_try_start_queued()
		State.HARPOON_PENDING:
			if _corridor:
				_enter_state(State.HARPOON_WARNING)
		State.HARPOON_WARNING, State.HARPOON_ACTIVE:
			pass
		State.HARPOON_CLEANUP:
			phase_time += delta
			if phase_time >= DeepDiveConfig.HARPOON_CLEANUP:
				phase_time = 0.0
				_enter_state(State.NORMAL)
		State.DIVE_PENDING:
			if _corridor:
				phase_time = 0.0
				active_dive_time = 0.0
				_enter_state(State.DIVE_TRANSITION_IN)
		State.DIVE_TRANSITION_IN:
			phase_time += delta
			if phase_time >= DeepDiveConfig.intro_total():
				phase_time = 0.0
				active_dive_time = 0.0
				_enter_state(State.DEEP_DIVE)
		State.DEEP_DIVE:
			var room := DeepDiveConfig.DURATION - active_dive_time
			var used := minf(delta, maxf(room, 0.0))
			active_dive_time += used
			dive_survival_time += used
			if active_dive_time >= DeepDiveConfig.DURATION - 0.002:
				active_dive_time = DeepDiveConfig.DURATION
				phase_time = 0.0
				_enter_state(State.DIVE_TRANSITION_OUT)
		State.DIVE_TRANSITION_OUT:
			phase_time += delta
			if phase_time >= DeepDiveConfig.TRANSITION_OUT:
				dives_survived += 1
				phase_time = 0.0
				_enter_state(State.RESUME_SWIMMING)
		State.RESUME_SWIMMING:
			phase_time += delta
			if phase_time >= DeepDiveConfig.RESUME_SECS:
				phase_time = 0.0
				_enter_state(State.NORMAL)
		_:
			pass


func _enter_state(next: int) -> void:
	if state == next:
		return
	var prev := state
	state = next
	token += 1
	state_changed.emit(prev, next)
