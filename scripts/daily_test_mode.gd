class_name DailyTestMode
extends RefCounted

# Editor-only practice switch. Leave this false.
# Exported games never enable it: export templates are not editor builds.
const DAILY_CHALLENGE_TEST_MODE := false


static func enabled() -> bool:
	return DAILY_CHALLENGE_TEST_MODE and OS.has_feature("editor")


static func status_label() -> String:
	if not DAILY_CHALLENGE_TEST_MODE:
		return "off"
	if not OS.has_feature("editor"):
		return "blocked_not_editor"
	return "active"


static func practice_course(challenge: Dictionary) -> Dictionary:
	var course := challenge.duplicate(true)
	course.erase("attempt_id")
	course["server_confirmed"] = false
	course["practice"] = true
	return course
