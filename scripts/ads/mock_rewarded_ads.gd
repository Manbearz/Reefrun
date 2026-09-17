class_name MockRewardedAdProvider
extends RewardedAdProvider

enum Outcome {
	SUCCESS,
	CLOSED_NO_REWARD,
	FAILED,
	UNAVAILABLE,
}

var outcome: Outcome = Outcome.SUCCESS
var duplicate_reward_signal := false
var resolve_delay := 0.05
var show_calls := 0


func is_available() -> bool:
	return outcome != Outcome.UNAVAILABLE


func show() -> void:
	show_calls += 1
	if outcome == Outcome.UNAVAILABLE:
		ad_unavailable.emit()
		return
	if resolve_delay <= 0.0:
		call_deferred("_resolve")
		return
	get_tree().create_timer(resolve_delay).timeout.connect(_resolve)


func _resolve() -> void:
	match outcome:
		Outcome.SUCCESS:
			reward_earned.emit()
			if duplicate_reward_signal:
				reward_earned.emit()
			ad_closed.emit()
		Outcome.CLOSED_NO_REWARD:
			ad_closed.emit()
		Outcome.FAILED:
			ad_failed.emit("mock_failed")
		_:
			ad_unavailable.emit()
