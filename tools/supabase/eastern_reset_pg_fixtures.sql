-- Rows that already exist before the Eastern migration. Dates are the UTC day,
-- which is what the live functions write today.

insert into public.profiles (id, display_name, mission_reward_coins)
values
	('11111111-1111-1111-1111-111111111111', 'USED', 0),
	('22222222-2222-2222-2222-222222222222', 'STARTED', 0),
	('33333333-3333-3333-3333-333333333333', 'PROGRESS', 0),
	('44444444-4444-4444-4444-444444444444', 'CLAIMED', 60);

insert into public.daily_challenges (challenge_id, challenge_date, course_seed, course_version, physics_version)
select
	'daily:' || to_char(v_day, 'YYYY-MM-DD') || ':cv1:pv1',
	v_day,
	public.reefrun_daily_seed(to_char(v_day, 'YYYY-MM-DD'), 1),
	1,
	1
from (select (pg_catalog.timezone('utc', pg_catalog.now()))::date as v_day) as day;

insert into public.daily_attempts (player_id, challenge_id, idempotency_key, score, finalized_at, started_at)
select
	'11111111-1111-1111-1111-111111111111',
	challenge_id,
	'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
	42,
	pg_catalog.now(),
	pg_catalog.now()
from public.daily_challenges
where challenge_date = (pg_catalog.timezone('utc', pg_catalog.now()))::date;

insert into public.daily_attempts (player_id, challenge_id, idempotency_key, started_at)
select
	'22222222-2222-2222-2222-222222222222',
	challenge_id,
	'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
	pg_catalog.now()
from public.daily_challenges
where challenge_date = (pg_catalog.timezone('utc', pg_catalog.now()))::date;

insert into public.leaderboard_scores (player_id, display_name, score, period, period_key, challenge_id)
select
	'11111111-1111-1111-1111-111111111111',
	'USED',
	42,
	'daily',
	to_char(challenge_date, 'YYYY-MM-DD'),
	challenge_id
from public.daily_challenges
where challenge_date = (pg_catalog.timezone('utc', pg_catalog.now()))::date;

insert into public.leaderboard_scores (player_id, display_name, score, period, period_key, challenge_id)
values
	('11111111-1111-1111-1111-111111111111', 'USED', 7, 'weekly',
		to_char(pg_catalog.date_trunc('week', pg_catalog.timezone('utc', pg_catalog.now())), 'YYYY-MM-DD'),
		null),
	('11111111-1111-1111-1111-111111111111', 'USED', 9, 'monthly',
		to_char(pg_catalog.timezone('utc', pg_catalog.now()), 'YYYY-MM'),
		null),
	('11111111-1111-1111-1111-111111111111', 'OLD', 99, 'daily', '1999-01-01', 'daily:1999-01-01:cv1:pv1');

insert into public.daily_challenges (challenge_id, challenge_date, course_seed, course_version, physics_version)
values ('daily:1999-01-01:cv1:pv1', date '1999-01-01', 1, 1, 1);

insert into public.daily_mission_sets (mission_date, easy_id, medium_id, hard_id)
select (pg_catalog.timezone('utc', pg_catalog.now()))::date, 1, 16, 31;

insert into public.daily_mission_progress (
	player_id, mission_date, pipes_total, runs_completed, best_pipes, best_seconds,
	gameplay_coins, coin_runs, run_pipes
)
select
	'33333333-3333-3333-3333-333333333333'::uuid,
	(pg_catalog.timezone('utc', pg_catalog.now()))::date,
	12, 1, 12, 20, 2, 1, array[12]
union all
select
	'44444444-4444-4444-4444-444444444444'::uuid,
	(pg_catalog.timezone('utc', pg_catalog.now()))::date,
	200, 3, 80, 180, 40, 3, array[80, 80, 40];

insert into public.daily_mission_claims (player_id, mission_date, slot, coins, mission_id)
select
	player_id,
	(pg_catalog.timezone('utc', pg_catalog.now()))::date,
	slot,
	coins,
	mission_id
from (values
	('44444444-4444-4444-4444-444444444444'::uuid, 'easy', 5, 1),
	('44444444-4444-4444-4444-444444444444'::uuid, 'medium', 10, 16),
	('44444444-4444-4444-4444-444444444444'::uuid, 'hard', 20, 31),
	('44444444-4444-4444-4444-444444444444'::uuid, 'bonus', 25, null::integer)
) as claim(player_id, slot, coins, mission_id);

-- The pre-migration check still rejects a long run. This insert must fail.
do $pre$
begin
	insert into public.daily_mission_run_log (player_id, run_id, mission_date, pipes, seconds, gameplay_coins)
	values (
		'33333333-3333-3333-3333-333333333333',
		'toolong01',
		(pg_catalog.timezone('utc', pg_catalog.now()))::date,
		81,
		120,
		0
	);
	raise exception 'pre-migration check accepted 81 pipes';
exception
	when check_violation then
		null;
end
$pre$;
