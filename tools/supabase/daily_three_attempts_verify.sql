-- Read-only checks after daily_three_attempts.sql. Do not change data.

select pg_catalog.pg_get_constraintdef(c.oid) as player_key
from pg_catalog.pg_constraint as c
where c.conname = 'daily_attempts_player_key'
	and c.conrelid = 'public.daily_attempts'::regclass;

select count(*) as old_unique_still_present
from pg_catalog.pg_constraint
where conname = 'daily_attempts_player_challenge'
	and conrelid = 'public.daily_attempts'::regclass;

select
	p.proname,
	pg_catalog.pg_get_function_identity_arguments(p.oid) as args,
	has_function_privilege('authenticated', p.oid, 'execute') as authenticated_execute
from pg_catalog.pg_proc as p
join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname in (
		'claim_daily_attempt',
		'start_daily_attempt',
		'finalize_daily_attempt',
		'get_daily_attempt_status'
	)
order by p.proname;

select count(*) as players_over_three_rows
from (
	select player_id, challenge_id
	from public.daily_attempts
	group by player_id, challenge_id
	having count(*) > 3
) as over_limit;

select count(*) as daily_score_rows
from public.leaderboard_scores
where period = 'daily';
