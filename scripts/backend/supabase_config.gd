extends RefCounted

# STAGE 1 — client config only.
# Paste values from the Supabase dashboard. Leave empty to play fully offline.
#
# Project URL:
#   Dashboard → Project Settings (gear) → API → Project URL
#   Example shape: https://YOUR_PROJECT_REF.supabase.co
#
# anon / publishable public key:
#   Dashboard → Project Settings → API → Project API keys → anon / public
#   NEVER paste the service_role / secret key here.

const URL := "https://colawgtkeudrkwffvzyn.supabase.co"
const ANON_KEY := "sb_publishable_y4-q0T_18rFu4CFKiv-1QA_GmRgWbzw"

const SESSION_PATH := "user://supabase_session.cfg"


static func is_configured() -> bool:
	return not URL.strip_edges().is_empty() and not ANON_KEY.strip_edges().is_empty()


static func project_url() -> String:
	return URL.strip_edges().trim_suffix("/")


static func anon_key() -> String:
	return ANON_KEY.strip_edges()
