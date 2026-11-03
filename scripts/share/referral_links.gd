class_name ReferralLinks
extends RefCounted

const RulesScript := preload("res://scripts/share/referral_rules.gd")

# Web reads https://lunarent.gg/?ref=CODE from the page URL and from
# localStorage key reefrun_ref (see tools/web/referral.js).
#
# Outgoing share sheets are opened by scripts/share/native_share_provider.gd.
# This file only reads an incoming referral code. The export presets still do
# not register a URL scheme or an intent filter, so a store install from a
# referral link does not attribute. ingest() is the hook for that later work.


static func capture() -> String:
	for arg in OS.get_cmdline_user_args():
		var code := RulesScript.from_arg(str(arg))
		if code != "":
			return code
	for arg in OS.get_cmdline_args():
		var code := RulesScript.from_arg(str(arg))
		if code != "":
			return code
	if OS.has_feature("web"):
		return _from_web()
	return ""


static func ingest(url: String) -> String:
	return RulesScript.parse_ref(url)


static func _from_web() -> String:
	if not Engine.has_singleton("JavaScriptBridge"):
		return ""
	var js = Engine.get_singleton("JavaScriptBridge")
	var raw = js.eval(_WEB_JS, true)
	return RulesScript.parse_ref(str(raw))


const _WEB_JS := """
(function(){
	try {
		var params = new URLSearchParams(window.location.search);
		var ref = params.get('ref') || '';
		if (!ref) {
			var hash = window.location.hash || '';
			var match = hash.match(/[?&]ref=([^&#]+)/);
			if (match) ref = decodeURIComponent(match[1]);
		}
		if (!ref) {
			try { ref = localStorage.getItem('reefrun_ref') || ''; } catch (e) { ref = ''; }
		} else {
			try { localStorage.setItem('reefrun_ref', ref); } catch (e) {}
		}
		return ref ? String(ref) : '';
	} catch (e) {
		return '';
	}
})()
"""
