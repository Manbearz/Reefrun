class_name AttAuthorization
extends RefCounted

# Apple's ATTrackingManagerAuthorizationStatus values, plus UNAVAILABLE when
# this process cannot read a native decision. A missing response is never
# treated as authorization.
enum Status {
	NOT_DETERMINED = 0,
	RESTRICTED = 1,
	DENIED = 2,
	AUTHORIZED = 3,
	UNAVAILABLE = 4,
}


static func should_present_ump_form(form_available: bool, already_presented: bool) -> bool:
	return form_available and not already_presented


static func ads_allowed(consent_allows: bool, _tracking_status: int) -> bool:
	# A tracking denial still allows a non-tracking ad request when UMP permits one.
	return consent_allows


static func idfa_allowed(tracking_status: int) -> bool:
	return tracking_status == Status.AUTHORIZED


static func next_step(form_available: bool, already_presented: bool, consent_allows: bool, tracking_status: int) -> String:
	if should_present_ump_form(form_available, already_presented):
		return "present_form"
	if ads_allowed(consent_allows, tracking_status):
		return "request_ad"
	return "hold_ads"


static func status_name(tracking_status: int) -> String:
	match tracking_status:
		Status.NOT_DETERMINED:
			return "not_determined"
		Status.RESTRICTED:
			return "restricted"
		Status.DENIED:
			return "denied"
		Status.AUTHORIZED:
			return "authorized"
		_:
			return "unavailable"
