class_name DiveMotion
extends RefCounted

var x := 270.0
var lane := DeepDiveConfig.CENTER_LANE
var velocity := 0.0
var min_x := 70.0
var max_x := 470.0

var _from := 270.0
var _to := 270.0
var _elapsed := 0.0
var _duration := DeepDiveConfig.LANE_SLIDE


func configure(view_w: float) -> void:
	var span := maxf(view_w, DeepDiveConfig.LANE_GAP * 2.0)
	var mid := span * 0.5
	min_x = mid + float(1 - DeepDiveConfig.CENTER_LANE) * DeepDiveConfig.LANE_GAP
	max_x = mid + float(DeepDiveConfig.LANE_COUNT - DeepDiveConfig.CENTER_LANE) * DeepDiveConfig.LANE_GAP
	reset(mid)


func reset(_origin: float = 0.0) -> void:
	lane = DeepDiveConfig.CENTER_LANE
	x = DeepDiveConfig.lane_center(lane)
	_from = x
	_to = x
	_elapsed = 0.0
	_duration = DeepDiveConfig.LANE_SLIDE
	velocity = 0.0


# direction < 0 is one lane left. direction > 0 is one lane right.
# Taps apply to the destination immediately, so a second tap is not dropped
# while the fish is still sliding.
func nudge(direction: float) -> void:
	if is_zero_approx(direction):
		return
	var step := -1 if direction < 0.0 else 1
	var next := clampi(lane + step, 1, DeepDiveConfig.LANE_COUNT)
	if next == lane:
		return
	lane = next
	_from = x
	_to = DeepDiveConfig.lane_center(lane)
	var lanes := absf(_to - _from) / DeepDiveConfig.LANE_GAP
	_duration = DeepDiveConfig.LANE_SLIDE * maxf(lanes, 0.001)
	_elapsed = 0.0


func tick(delta: float) -> void:
	var before := x
	if _elapsed >= _duration:
		x = _to
		velocity = 0.0
		return
	_elapsed = minf(_duration, _elapsed + maxf(delta, 0.0))
	var u := clampf(_elapsed / maxf(_duration, 0.0001), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	x = lerpf(_from, _to, u)
	x = clampf(x, min_x, max_x)
	if is_equal_approx(x, _to):
		x = _to
		velocity = 0.0
		return
	velocity = (x - before) / maxf(delta, 0.0001)
