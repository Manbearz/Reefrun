-- Assertions for the isolated database after eastern_daily_reset.sql.
-- Simulated rows and function calls. No production connection.

do $time$
declare
	eastern date;
	utc_day date;
	resets timestamptz;
begin
	eastern := (pg_catalog.timezone('America/New_York', timestamptz '2026-07-16 03:59:59+00'))::date;
	if eastern <> date '2026-07-15' then
		raise exception '11:59 PM EDT was %', eastern;
	end if;
	eastern := (pg_catalog.timezone('America/New_York', timestamptz '2026-07-16 04:00:00+00'))::date;
	if eastern <> date '2026-07-16' then
		raise exception '12:00 AM EDT was %', eastern;
	end if;
	resets := (date '2026-07-15' + 1)::timestamp at time zone 'America/New_York';
	if resets <> timestamptz '2026-07-16 04:00:00+00' then
		raise exception 'EDT reset instant was %', resets;
	end if;

	utc_day := (pg_catalog.timezone('utc', timestamptz '2026-07-15 23:59:00+00'))::date;
	eastern := (pg_catalog.timezone('America/New_York', timestamptz '2026-07-15 23:59:00+00'))::date;
	if utc_day <> date '2026-07-15' or eastern <> date '2026-07-15' then
		raise exception '7:59 PM EDT dates utc=% eastern=%', utc_day, eastern;
	end if;
	utc_day := (pg_catalog.timezone('utc', timestamptz '2026-07-16 00:00:00+00'))::date;
	eastern := (pg_catalog.timezone('America/New_York', timestamptz '2026-07-16 00:00:00+00'))::date;
	if utc_day <> date '2026-07-16' or eastern <> date '2026-07-15' then
		raise exception '8:00 PM EDT dates utc=% eastern=%', utc_day, eastern;
	end if;

	utc_day := (pg_catalog.timezone('utc', timestamptz '2026-01-15 23:59:00+00'))::date;
	eastern := (pg_catalog.timezone('America/New_York', timestamptz '2026-01-15 23:59:00+00'))::date;
	if utc_day <> date '2026-01-15' or eastern <> date '2026-01-15' then
		raise exception '6:59 PM EST dates utc=% eastern=%', utc_day, eastern;
	end if;
	utc_day := (pg_catalog.timezone('utc', timestamptz '2026-01-16 00:00:00+00'))::date;
	eastern := (pg_catalog.timezone('America/New_York', timestamptz '2026-01-16 00:00:00+00'))::date;
	if utc_day <> date '2026-01-16' or eastern <> date '2026-01-15' then
		raise exception '7:00 PM EST dates utc=% eastern=%', utc_day, eastern;
	end if;
	resets := (date '2026-01-15' + 1)::timestamp at time zone 'America/New_York';
	if resets <> timestamptz '2026-01-16 05:00:00+00' then
		raise exception 'EST reset instant was %', resets;
	end if;

	eastern := (pg_catalog.timezone('America/New_York', timestamptz '2026-03-08 06:30:00+00'))::date;
	if eastern <> date '2026-03-08' then
		raise exception 'spring-forward before the jump was %', eastern;
	end if;
	eastern := (pg_catalog.timezone('America/New_York', timestamptz '2026-03-08 07:30:00+00'))::date;
	if eastern <> date '2026-03-08' then
		raise exception 'spring-forward after the jump was %', eastern;
	end if;
	resets := (date '2026-03-08' + 1)::timestamp at time zone 'America/New_York';
	if resets <> timestamptz '2026-03-09 04:00:00+00' then
		raise exception 'spring-forward next midnight was %', resets;
	end if;

	eastern := (pg_catalog.timezone('America/New_York', timestamptz '2026-11-01 05:30:00+00'))::date;
	if eastern <> date '2026-11-01' then
		raise exception 'fall-back first 1:30 AM was %', eastern;
	end if;
	eastern := (pg_catalog.timezone('America/New_York', timestamptz '2026-11-01 06:30:00+00'))::date;
	if eastern <> date '2026-11-01' then
		raise exception 'fall-back second 1:30 AM was %', eastern;
	end if;
	resets := (date '2026-11-01' + 1)::timestamp at time zone 'America/New_York';
	if resets <> timestamptz '2026-11-02 05:00:00+00' then
		raise exception 'fall-back next midnight was %', resets;
	end if;

	if to_char(date_trunc('week', timezone('utc', timestamptz '2026-07-20 00:00:00+00')), 'YYYY-MM-DD')
		<> '2026-07-20' then
		raise exception 'weekly UTC boundary moved';
	end if;
	if (timezone('America/New_York', timestamptz '2026-07-20 00:00:00+00'))::date <> date '2026-07-19' then
		raise exception 'Sunday 8 PM EDT was not still Sunday';
	end if;
	if to_char(timezone('utc', timestamptz '2026-07-20 00:00:00+00'), 'YYYY-MM') <> '2026-07' then
		raise exception 'monthly UTC key changed at 8 PM EDT';
	end if;
	raise notice 'timezone boundaries passed';
end
$time$;

do $wire$
declare
	v_day date;
	v_resets timestamptz;
	v_id text;
	v_count integer;
	v_score integer;
	v_week text;
	v_month text;
	v_coins integer;
	v_pipes integer;
	v_dives integer;
	v_reason text;
	v_accepted boolean;
	v_board jsonb;
begin
	select challenge_date, resets_at, challenge_id
	into v_day, v_resets, v_id
	from public.reefrun_publish_today();
	if v_day is distinct from (pg_catalog.timezone('America/New_York', pg_catalog.now()))::date then
		raise exception 'publish day % is not Eastern today', v_day;
	end if;
	if v_resets is distinct from ((v_day + 1)::timestamp at time zone 'America/New_York') then
		raise exception 'publish reset % is not the next Eastern midnight', v_resets;
	end if;
	if v_id is distinct from 'daily:' || to_char(v_day, 'YYYY-MM-DD') || ':cv1:pv1' then
		raise exception 'publish id %', v_id;
	end if;
	select count(*) into v_count
	from public.daily_challenges
	where challenge_date = v_day;
	if v_count <> 1 then
		raise exception 'publish created an extra challenge for % (% rows)', v_day, v_count;
	end if;

	select count(*) into v_count from public.get_leaderboard('daily') where score = 99;
	if v_count <> 0 then
		raise exception 'old daily score appeared on today''s board';
	end if;
	select score into v_score from public.get_leaderboard('daily') where display_name = 'USED';
	if v_score is distinct from 42 then
		raise exception 'finalized daily score missing, got %', v_score;
	end if;
	v_week := to_char(date_trunc('week', timezone('utc', now())), 'YYYY-MM-DD');
	select score into v_score from public.get_leaderboard('weekly') where display_name = 'USED';
	if v_score is distinct from 7 then
		raise exception 'weekly UTC score missing, got %', v_score;
	end if;
	v_month := to_char(timezone('utc', now()), 'YYYY-MM');
	select score into v_score from public.get_leaderboard('monthly') where display_name = 'USED';
	if v_score is distinct from 9 then
		raise exception 'monthly UTC score missing, got %', v_score;
	end if;

	begin
		insert into public.daily_attempts (player_id, challenge_id, idempotency_key)
		values (
			'11111111-1111-1111-1111-111111111111',
			v_id,
			'cccccccc-cccc-cccc-cccc-cccccccccccc'
		);
		raise exception 'second daily attempt was inserted';
	exception
		when unique_violation then
			null;
	end;
	select count(*) into v_count
	from public.daily_attempts
	where player_id = '22222222-2222-2222-2222-222222222222';
	if v_count <> 1 then
		raise exception 'started attempt count became %', v_count;
	end if;

	perform set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', false);
	v_board := public.claim_daily_mission('bonus');
	if (v_board ->> 'granted_now')::integer is distinct from 0
		or coalesce(v_board ->> 'reason', '') not in ('already', 'cap') then
		raise exception 'claimed bonus became claimable: %', v_board;
	end if;
	select mission_reward_coins into v_coins
	from public.profiles
	where id = '44444444-4444-4444-4444-444444444444';
	if v_coins is distinct from 60 then
		raise exception 'claimed wallet changed to %', v_coins;
	end if;

	select pipes_total, best_pipes into v_pipes, v_count
	from public.daily_mission_progress
	where player_id = '33333333-3333-3333-3333-333333333333'
		and mission_date = v_day;
	if v_pipes is distinct from 12 or v_count is distinct from 12 then
		raise exception 'existing progress rewritten to % / %', v_pipes, v_count;
	end if;

	perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
	v_board := public.record_unlimited_mission_run('longrun5000', 5000, 12000, 1000, 166, 166, 3320, 0, 0, 0, 0, 0);
	if v_board ->> 'reason' is distinct from 'recorded' or (v_board ->> 'accepted')::boolean is distinct from true then
		raise exception '5000-pipe run rejected: %', v_board ->> 'reason';
	end if;
	v_board := public.record_unlimited_mission_run('longrun5000', 5000, 12000, 1000, 166, 166, 3320, 0, 0, 0, 0, 0);
	if v_board ->> 'reason' is distinct from 'duplicate' then
		raise exception 'duplicate 5000-pipe run was %', v_board ->> 'reason';
	end if;
	select pipes_total, dives_entered into v_pipes, v_dives
	from public.daily_mission_progress
	where player_id = '33333333-3333-3333-3333-333333333333'
		and mission_date = v_day;
	if v_pipes is distinct from 5012 or v_dives is distinct from 166 then
		raise exception 'long-run progress pipes=% dives=%', v_pipes, v_dives;
	end if;

	v_board := public.record_unlimited_mission_run('plainrun1', 10, 20, 2);
	if v_board ->> 'reason' is distinct from 'recorded' then
		raise exception '4-arg run was %', v_board ->> 'reason';
	end if;
	v_board := public.record_unlimited_mission_run('toofast01', 5000, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0);
	if v_board ->> 'reason' is distinct from 'rejected' then
		raise exception 'too-fast run was %', v_board ->> 'reason';
	end if;
	v_board := public.record_unlimited_mission_run('tooslow01', 40, 200, 0);
	if v_board ->> 'reason' is distinct from 'rejected' then
		raise exception 'slow short run was %', v_board ->> 'reason';
	end if;
	v_board := public.record_unlimited_mission_run('full80run', 80, 500, 16);
	if v_board ->> 'reason' is distinct from 'recorded' then
		raise exception '80-pipe run was %', v_board ->> 'reason';
	end if;
	select count(*) into v_count
	from pg_proc
	where proname = 'record_unlimited_mission_run';
	if v_count <> 2 then
		raise exception 'recorder overload count %', v_count;
	end if;
	raise notice 'function wiring passed';
end
$wire$;

do $grant$
begin
	if not has_function_privilege('authenticated', 'public.get_daily_missions()', 'execute') then
		raise exception 'authenticated lost get_daily_missions';
	end if;
	if not has_function_privilege(
		'authenticated',
		'public.record_unlimited_mission_run(text,integer,integer,integer)',
		'execute'
	) then
		raise exception 'authenticated lost the 4-arg recorder';
	end if;
	if not has_function_privilege(
		'authenticated',
		'public.record_unlimited_mission_run(text,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer)',
		'execute'
	) then
		raise exception 'authenticated cannot call the 12-arg recorder';
	end if;
	if has_function_privilege('anon', 'public.claim_daily_mission(text)', 'execute') then
		raise exception 'anon can claim missions';
	end if;
	if has_function_privilege('authenticated', 'public.reefrun_daily_mission_board(uuid)', 'execute') then
		raise exception 'mission board is directly callable';
	end if;
	raise notice 'privileges passed';
end
$grant$;

do $mismatch$
declare
	utc_day date := (timezone('utc', timestamptz '2026-10-21 00:12:00+00'))::date;
	east_day date := (timezone('America/New_York', timestamptz '2026-10-21 00:12:00+00'))::date;
	utc_id text;
	east_id text;
	v_count integer;
begin
	if utc_day = east_day then
		raise exception 'mismatch sample did not split dates';
	end if;
	if (timezone('utc', timestamptz '2026-10-21 16:00:00+00'))::date
		is distinct from (timezone('America/New_York', timestamptz '2026-10-21 16:00:00+00'))::date then
		raise exception 'noon EDT was treated as a split day';
	end if;
	utc_id := 'daily:' || to_char(utc_day, 'YYYY-MM-DD') || ':cv1:pv1';
	east_id := 'daily:' || to_char(east_day, 'YYYY-MM-DD') || ':cv1:pv1';
	insert into public.profiles (id, display_name)
	values ('55555555-5555-5555-5555-555555555555', 'SPLIT')
	on conflict (id) do nothing;
	insert into public.daily_challenges (challenge_id, challenge_date, course_seed, course_version, physics_version)
	values (utc_id, utc_day, 1, 1, 1)
	on conflict (challenge_id) do nothing;
	insert into public.daily_attempts (player_id, challenge_id, idempotency_key, finalized_at, score)
	values ('55555555-5555-5555-5555-555555555555', utc_id, 'dddddddd-dddd-dddd-dddd-dddddddddddd', now(), 10);
	insert into public.daily_challenges (challenge_id, challenge_date, course_seed, course_version, physics_version)
	values (east_id, east_day, 1, 1, 1);
	insert into public.daily_attempts (player_id, challenge_id, idempotency_key)
	values ('55555555-5555-5555-5555-555555555555', east_id, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee');
	select count(*) into v_count
	from public.daily_attempts
	where player_id = '55555555-5555-5555-5555-555555555555';
	if v_count <> 2 then
		raise exception 'mismatch model did not show a second attempt';
	end if;
	raise notice 'unsafe-window model passed';
end
$mismatch$;

select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
set role authenticated;
do $as_player$
declare
	board jsonb;
begin
	board := public.get_daily_missions();
	if board ->> 'ok' is distinct from 'true' then
		raise exception 'authenticated board failed: %', board;
	end if;
	raise notice 'authenticated board passed';
end
$as_player$;
reset role;

