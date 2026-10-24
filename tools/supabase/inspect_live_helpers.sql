-- READ ONLY. Paste into the Supabase SQL Editor and run.
-- Do not add INSERT, UPDATE, DELETE, ALTER, DROP, GRANT, or a function call
-- that writes a challenge, attempt, score, mission, or claim.
-- pg_get_functiondef only reads the stored function source.

select
	p.proname as function_name,
	pg_get_function_identity_arguments(p.oid) as identity_args,
	pg_get_functiondef(p.oid) as definition
from pg_proc as p
join pg_namespace as n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname in (
		'claim_daily_attempt',
		'start_daily_attempt',
		'get_daily_attempt_status',
		'get_daily_challenge',
		'submit_leaderboard_score',
		'reefrun_ensure_daily_mission_set',
		'reefrun_mission_snapshot',
		'reefrun_publish_today',
		'finalize_daily_attempt',
		'get_leaderboard',
		'record_unlimited_mission_run'
	)
order by p.proname, pg_get_function_identity_arguments(p.oid);
