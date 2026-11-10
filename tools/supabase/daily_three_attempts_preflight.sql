-- Read-only checks before daily_three_attempts.sql. Do not change data.

select version();

select
	c.conname,
	pg_catalog.pg_get_constraintdef(c.oid) as definition
from pg_catalog.pg_constraint as c
where c.conrelid = 'public.daily_attempts'::regclass
order by c.conname;

select
	p.proname,
	pg_catalog.pg_get_function_identity_arguments(p.oid) as args
from pg_catalog.pg_proc as p
join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname in (
		'claim_daily_attempt',
		'start_daily_attempt',
		'finalize_daily_attempt',
		'get_daily_attempt_status',
		'get_daily_challenge',
		'submit_leaderboard_score',
		'get_leaderboard'
	)
order by p.proname;

select player_id, challenge_id, count(*) as rows
from public.daily_attempts
group by player_id, challenge_id
having count(*) > 1;

select count(*) as attempt_rows from public.daily_attempts;
select count(*) as daily_score_rows
from public.leaderboard_scores
where period = 'daily';
