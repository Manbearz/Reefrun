-- Eastern daily reset, mission RPC compatibility, and long-run recording.
-- DO NOT RUN until this file is approved. It was not executed against production.
--
-- Prepared from the live definitions in
-- "Supabase Snippet Untitled query.csv" (exported function source), not from
-- an assumption that an older local file is what the database is running.
--
-- What this changes
--   Daily calendar day becomes America/New_York for:
--     reefrun_publish_today, get_leaderboard's daily branch,
--     reefrun_daily_mission_board, claim_daily_mission,
--     record_unlimited_mission_run.
--   Postgres applies US daylight saving time for that zone. Midnight is
--   04:00 UTC during EDT and 05:00 UTC during EST.
--   Weekly and monthly leaderboard keys stay on UTC.
--   record_unlimited_mission_run gains the eight Deep Dive arguments the
--   Godot client already sends. The four-argument function remains and
--   forwards to it with those arguments at 0.
--   A run may record up to 20,000 pipes. Runs of 80 pipes or fewer keep the
--   live acceptance rules. Longer runs use the same survival formula.
--   reefrun_mission_snapshot gains an overload that can score Deep Dive
--   rules. The existing pipe, survival, coin, and run-count overload stays.
--   This file does not insert mission ids 46-90 and does not enable them.
--
-- What this does not change
--   No historical row is updated, deleted, or moved to a different date.
--   Challenge ids, attempt rows, leaderboard period keys, mission dates,
--   claims, and coin balances stay as they were written.
--   Claim uniqueness stays (player_id, mission_date, slot).
--   Attempt uniqueness is untouched. This file does not replace
--   claim_daily_attempt, start_daily_attempt, or get_daily_attempt_status;
--   those bodies were not in the export. The local daily_start_fix.sql
--   claim calls reefrun_publish_today(), so a matching live claim follows
--   the new date. Confirm that with pg_get_functiondef before running.
--   Rewards stay 5 / 10 / 20 and the 25 bonus. The 60-coin cap stays.
--   finalize_daily_attempt already stores period_key from the challenge row's
--   challenge_date. New challenges publish an Eastern date, so new daily
--   scores use that same date. This file does not edit finalize.
--
-- Deploy window
--   Run only while the UTC date and the New York date are the same calendar
--   day: from Eastern midnight until 00:00 UTC (20:00 EDT, 19:00 EST).
--   In that window today's existing keys already match the new day, so a
--   player does not receive a second attempt and claimed missions stay claimed.
--   After 00:00 UTC the UTC date is already tomorrow. Deploying then would
--   look up yesterday's Eastern rows while this evening's rows sit on the
--   UTC date. Do not "fix" that by rewriting keys. Wait for the next Eastern
--   midnight, when the dates match again.
--
-- Apply
--   Supabase SQL Editor → New query → paste this whole file → Run once.
--   Run it as one script. A failure then rolls the script back.
--   Do not run the statements one at a time.
--   The NOTIFY at the bottom reloads the API schema.
--   Running the file again in a later safe window is safe: columns, checks,
--   and functions replace in place and no player row is rewritten.
--   Outside the safe window the guard below stops the script before any change.

do $guard$
begin
	if (pg_catalog.timezone('utc', pg_catalog.now()))::date
		is distinct from (pg_catalog.timezone('America/New_York', pg_catalog.now()))::date
	then
		raise exception
			'Refusing Eastern daily reset while the UTC date (%) and the America/New_York date (%) differ. Wait until Eastern midnight so existing attempt and claim keys stay on today.',
			(pg_catalog.timezone('utc', pg_catalog.now()))::date,
			(pg_catalog.timezone('America/New_York', pg_catalog.now()))::date;
	end if;
end
$guard$;

-- Dive columns. Existing progress and run rows keep their pipe, survival,
-- and coin values. New columns default to 0. This is not a date migration.
alter table public.daily_mission_progress
	add column if not exists dives_entered integer not null default 0,
	add column if not exists dives_completed integer not null default 0,
	add column if not exists best_dives integer not null default 0,
	add column if not exists dive_seconds integer not null default 0,
	add column if not exists lane_changes integer not null default 0,
	add column if not exists lanes_left integer not null default 0,
	add column if not exists lanes_right integer not null default 0,
	add column if not exists obstacles_dodged integer not null default 0,
	add column if not exists best_obstacles integer not null default 0,
	add column if not exists mines_passed integer not null default 0;

alter table public.daily_mission_run_log
	add column if not exists dives_entered integer not null default 0,
	add column if not exists dives_completed integer not null default 0,
	add column if not exists dive_seconds integer not null default 0,
	add column if not exists lane_changes integer not null default 0,
	add column if not exists lanes_left integer not null default 0,
	add column if not exists lanes_right integer not null default 0,
	add column if not exists obstacles integer not null default 0,
	add column if not exists mines integer not null default 0;

-- The live checks cap a run at 80 pipes and 1,800 seconds. Postgres stores
-- "between 0 and 80" as ">= 0 and <= 80", so match that stored form.
-- Rows already stored are inside the new range, so nothing is rewritten.
do $widen$
declare
	r record;
begin
	for r in
		select con.conrelid::regclass as table_name, con.conname
		from pg_constraint as con
		where con.conrelid in (
			'public.daily_mission_progress'::regclass,
			'public.daily_mission_run_log'::regclass
		)
			and con.contype = 'c'
			and (
				pg_get_constraintdef(con.oid) ~ '<= 80\)'
				or pg_get_constraintdef(con.oid) ~ '<= 1800\)'
				or pg_get_constraintdef(con.oid) ~* 'between 0 and 80'
				or pg_get_constraintdef(con.oid) ~* 'between 0 and 1800'
			)
	loop
		execute format('alter table %s drop constraint %I', r.table_name, r.conname);
	end loop;
end
$widen$;

alter table public.daily_mission_run_log
	drop constraint if exists daily_mission_run_log_pipes_cap,
	drop constraint if exists daily_mission_run_log_seconds_cap;
alter table public.daily_mission_run_log
	add constraint daily_mission_run_log_pipes_cap check (pipes between 0 and 20000),
	add constraint daily_mission_run_log_seconds_cap check (seconds between 0 and 86400);

alter table public.daily_mission_progress
	drop constraint if exists daily_mission_progress_best_pipes_cap,
	drop constraint if exists daily_mission_progress_best_seconds_cap;
alter table public.daily_mission_progress
	add constraint daily_mission_progress_best_pipes_cap check (best_pipes between 0 and 20000),
	add constraint daily_mission_progress_best_seconds_cap check (best_seconds between 0 and 86400);

create or replace function public.reefrun_publish_today()
returns table (
	challenge_id text,
	challenge_date date,
	course_seed bigint,
	course_version integer,
	physics_version integer,
	as_of timestamptz,
	as_of_unix bigint,
	resets_at timestamptz,
	resets_unix bigint
)
language plpgsql
security definer
set search_path = ''
as $fn$
declare
	v_cv integer := 1;
	v_pv integer := 1;
	v_day date := (pg_catalog.timezone('America/New_York', pg_catalog.now()))::date;
	v_date text;
	v_id text;
	v_seed bigint;
	v_resets timestamptz;
begin
	v_date := pg_catalog.to_char(v_day, 'YYYY-MM-DD');
	v_id := 'daily:' || v_date || ':cv' || v_cv::text || ':pv' || v_pv::text;
	v_seed := public.reefrun_daily_seed(v_date, v_cv);
	v_resets := (v_day + 1)::timestamp at time zone 'America/New_York';
	insert into public.daily_challenges as c (challenge_id, challenge_date, course_seed, course_version, physics_version)
	values (v_id, v_day, v_seed, v_cv, v_pv)
	on conflict on constraint daily_challenges_pkey do nothing;
	return query
	select
		c.challenge_id,
		c.challenge_date,
		c.course_seed,
		c.course_version,
		c.physics_version,
		pg_catalog.now(),
		extract(epoch from pg_catalog.now())::bigint,
		v_resets,
		extract(epoch from v_resets)::bigint
	from public.daily_challenges as c
	where c.challenge_id = v_id;
end;
$fn$;

revoke all on function public.reefrun_publish_today() from public, anon;

create or replace function public.get_leaderboard(p_period text)
returns table (display_name text, score integer)
language sql
stable
security definer
set search_path = ''
as $fn$
	select pg_catalog.left(pg_catalog.btrim(ls.display_name), 7)::text as display_name,
		ls.score::integer as score
	from public.leaderboard_scores as ls
	where ls.period = p_period
		and (
			(p_period = 'daily' and ls.challenge_id is not null)
			or (p_period in ('weekly', 'monthly') and ls.challenge_id is null)
		)
		and ls.period_key = case
			when p_period = 'daily' then pg_catalog.to_char(pg_catalog.timezone('America/New_York', pg_catalog.now()), 'YYYY-MM-DD')
			when p_period = 'weekly' then pg_catalog.to_char(pg_catalog.date_trunc('week', pg_catalog.timezone('utc', pg_catalog.now())), 'YYYY-MM-DD')
			when p_period = 'monthly' then pg_catalog.to_char(pg_catalog.timezone('utc', pg_catalog.now()), 'YYYY-MM')
			else ''
		end
	order by ls.score desc, ls.created_at asc
	limit 10;
$fn$;

revoke all on function public.get_leaderboard(text) from public, anon;
grant execute on function public.get_leaderboard(text) to authenticated;

-- Extra overload. The live 10-argument snapshot stays in place and still
-- scores only pipe, survival, coin, and run-count rules. Callers that pass
-- the dive arguments use this one. Unknown rules still return progress 0.
create or replace function public.reefrun_mission_snapshot(
	p_rule text,
	p_goal integer,
	p_goal_b integer,
	p_pipes_total integer,
	p_runs integer,
	p_best_pipes integer,
	p_best_seconds integer,
	p_coins integer,
	p_coin_runs integer,
	p_dives_entered integer,
	p_dives_completed integer,
	p_best_dives integer,
	p_dive_seconds integer,
	p_lane_changes integer,
	p_lanes_left integer,
	p_lanes_right integer,
	p_obstacles integer,
	p_best_obstacles integer,
	p_mines integer,
	p_run_pipes integer[]
) returns jsonb
language plpgsql
immutable
set search_path = public
as $fn$
declare
	progress integer := 0;
	target integer := p_goal;
begin
	case p_rule
		when 'pipes_total' then progress := coalesce(p_pipes_total, 0);
		when 'pipes_best' then progress := coalesce(p_best_pipes, 0);
		when 'runs' then progress := coalesce(p_runs, 0);
		when 'survive_best' then progress := coalesce(p_best_seconds, 0);
		when 'coins_total' then progress := coalesce(p_coins, 0);
		when 'coin_runs' then progress := coalesce(p_coin_runs, 0);
		when 'runs_at_least' then
			progress := public.reefrun_count_at_least(p_run_pipes, p_goal);
			target := p_goal_b;
		when 'window_sum' then
			progress := public.reefrun_window_sum(p_run_pipes, p_goal_b);
			target := p_goal;
		when 'dives_entered' then progress := coalesce(p_dives_entered, 0);
		when 'dives_completed' then progress := coalesce(p_dives_completed, 0);
		when 'dives_best' then progress := coalesce(p_best_dives, 0);
		when 'dive_seconds' then progress := coalesce(p_dive_seconds, 0);
		when 'lanes_total' then progress := coalesce(p_lane_changes, 0);
		when 'lanes_left' then progress := coalesce(p_lanes_left, 0);
		when 'lanes_right' then progress := coalesce(p_lanes_right, 0);
		when 'obstacles_total' then progress := coalesce(p_obstacles, 0);
		when 'obstacles_best' then progress := coalesce(p_best_obstacles, 0);
		when 'mines_total' then progress := coalesce(p_mines, 0);
		else progress := 0;
	end case;
	return pg_catalog.jsonb_build_object(
		'progress', progress,
		'goal', target,
		'complete', target > 0 and progress >= target
	);
end;
$fn$;

create or replace function public.reefrun_daily_mission_board(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
	today date := (pg_catalog.timezone('America/New_York', pg_catalog.now()))::date;
	set_row public.daily_mission_sets;
	pipes_total integer := 0;
	runs_completed integer := 0;
	best_pipes integer := 0;
	best_seconds integer := 0;
	gameplay_coins integer := 0;
	coin_runs integer := 0;
	run_pipes integer[] := '{}';
	dives_entered integer := 0;
	dives_completed integer := 0;
	best_dives integer := 0;
	dive_seconds integer := 0;
	lane_changes integer := 0;
	lanes_left integer := 0;
	lanes_right integer := 0;
	obstacles_dodged integer := 0;
	best_obstacles integer := 0;
	mines_passed integer := 0;
	slots jsonb := '[]'::jsonb;
	slot_name text;
	mid integer;
	def public.mission_definitions;
	snap jsonb;
	was_claimed boolean;
	claimed_slots integer := 0;
	bonus_claimed boolean := false;
	reward_total integer := 0;
begin
	if p_uid is null or p_uid is distinct from auth.uid() then
		return pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
	end if;
	insert into public.profiles (id, display_name)
	values (p_uid, 'YOU')
	on conflict (id) do nothing;
	set_row := public.reefrun_ensure_daily_mission_set(today);
	select p.pipes_total, p.runs_completed, p.best_pipes, p.best_seconds,
		p.gameplay_coins, p.coin_runs, p.run_pipes,
		p.dives_entered, p.dives_completed, p.best_dives, p.dive_seconds,
		p.lane_changes, p.lanes_left, p.lanes_right,
		p.obstacles_dodged, p.best_obstacles, p.mines_passed
	into pipes_total, runs_completed, best_pipes, best_seconds,
		gameplay_coins, coin_runs, run_pipes,
		dives_entered, dives_completed, best_dives, dive_seconds,
		lane_changes, lanes_left, lanes_right,
		obstacles_dodged, best_obstacles, mines_passed
	from public.daily_mission_progress as p
	where p.player_id = p_uid and p.mission_date = today;
	if not found then
		pipes_total := 0;
		runs_completed := 0;
		best_pipes := 0;
		best_seconds := 0;
		gameplay_coins := 0;
		coin_runs := 0;
		run_pipes := '{}';
		dives_entered := 0;
		dives_completed := 0;
		best_dives := 0;
		dive_seconds := 0;
		lane_changes := 0;
		lanes_left := 0;
		lanes_right := 0;
		obstacles_dodged := 0;
		best_obstacles := 0;
		mines_passed := 0;
	end if;

	foreach slot_name in array array['easy', 'medium', 'hard'] loop
		mid := case slot_name
			when 'easy' then set_row.easy_id
			when 'medium' then set_row.medium_id
			else set_row.hard_id
		end;
		select * into def from public.mission_definitions where id = mid;
		snap := public.reefrun_mission_snapshot(
			def.rule, def.goal, def.goal_b,
			pipes_total, runs_completed, best_pipes, best_seconds,
			gameplay_coins, coin_runs,
			dives_entered, dives_completed, best_dives, dive_seconds,
			lane_changes, lanes_left, lanes_right,
			obstacles_dodged, best_obstacles, mines_passed,
			run_pipes
		);
		select exists (
			select 1
			from public.daily_mission_claims as c
			where c.player_id = p_uid
				and c.mission_date = today
				and c.slot = slot_name
		) into was_claimed;
		if was_claimed then
			claimed_slots := claimed_slots + 1;
		end if;
		slots := slots || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
			'slot', slot_name,
			'mission_id', mid,
			'description', def.description,
			'reward', case slot_name when 'easy' then 5 when 'medium' then 10 else 20 end,
			'progress', snap -> 'progress',
			'goal', snap -> 'goal',
			'complete', snap -> 'complete',
			'claimed', was_claimed
		));
	end loop;

	select exists (
		select 1
		from public.daily_mission_claims as c
		where c.player_id = p_uid
			and c.mission_date = today
			and c.slot = 'bonus'
	) into bonus_claimed;
	select p.mission_reward_coins into reward_total
	from public.profiles as p
	where p.id = p_uid;

	return pg_catalog.jsonb_build_object(
		'ok', true,
		'mission_date', today,
		'server_now', extract(epoch from pg_catalog.now())::bigint,
		'resets_at', extract(epoch from ((today + 1)::timestamp at time zone 'America/New_York'))::bigint,
		'mission_reward_coins', coalesce(reward_total, 0),
		'granted_now', 0,
		'slots', slots,
		'bonus', pg_catalog.jsonb_build_object(
			'reward', 25,
			'progress', claimed_slots,
			'goal', 3,
			'unlocked', claimed_slots = 3,
			'complete', claimed_slots = 3 and not bonus_claimed,
			'claimed', bonus_claimed,
			'description', 'COMPLETE ALL 3'
		)
	);
end;
$fn$;

create or replace function public.claim_daily_mission(p_slot text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
	uid uuid := auth.uid();
	today date := (pg_catalog.timezone('America/New_York', pg_catalog.now()))::date;
	set_row public.daily_mission_sets;
	reward integer := 0;
	mid integer := null;
	complete boolean := false;
	existing_sum integer := 0;
	pipes_total integer := 0;
	runs_completed integer := 0;
	best_pipes integer := 0;
	best_seconds integer := 0;
	gameplay_coins integer := 0;
	coin_runs integer := 0;
	run_pipes integer[] := '{}';
	dives_entered integer := 0;
	dives_completed integer := 0;
	best_dives integer := 0;
	dive_seconds integer := 0;
	lane_changes integer := 0;
	lanes_left integer := 0;
	lanes_right integer := 0;
	obstacles_dodged integer := 0;
	best_obstacles integer := 0;
	mines_passed integer := 0;
	def public.mission_definitions;
	snap jsonb;
	board jsonb;
	wrote integer := 0;
begin
	if uid is null then
		return pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
	end if;
	if p_slot is null or p_slot not in ('easy', 'medium', 'hard', 'bonus') then
		return pg_catalog.jsonb_build_object('ok', false, 'reason', 'bad_slot');
	end if;

	perform pg_advisory_xact_lock(872342, hashtext(uid::text || today::text));
	insert into public.profiles (id, display_name) values (uid, 'YOU') on conflict (id) do nothing;
	perform 1 from public.profiles where id = uid for update;
	set_row := public.reefrun_ensure_daily_mission_set(today);

	select p.pipes_total, p.runs_completed, p.best_pipes, p.best_seconds,
		p.gameplay_coins, p.coin_runs, p.run_pipes,
		p.dives_entered, p.dives_completed, p.best_dives, p.dive_seconds,
		p.lane_changes, p.lanes_left, p.lanes_right,
		p.obstacles_dodged, p.best_obstacles, p.mines_passed
	into pipes_total, runs_completed, best_pipes, best_seconds,
		gameplay_coins, coin_runs, run_pipes,
		dives_entered, dives_completed, best_dives, dive_seconds,
		lane_changes, lanes_left, lanes_right,
		obstacles_dodged, best_obstacles, mines_passed
	from public.daily_mission_progress as p
	where p.player_id = uid and p.mission_date = today;

	if p_slot = 'bonus' then
		reward := 25;
		select count(*) = 3 into complete
		from public.daily_mission_claims as c
		where c.player_id = uid
			and c.mission_date = today
			and c.slot in ('easy', 'medium', 'hard');
	else
		reward := case p_slot when 'easy' then 5 when 'medium' then 10 else 20 end;
		mid := case p_slot
			when 'easy' then set_row.easy_id
			when 'medium' then set_row.medium_id
			else set_row.hard_id
		end;
		select * into def from public.mission_definitions where id = mid;
		snap := public.reefrun_mission_snapshot(
			def.rule, def.goal, def.goal_b,
			pipes_total, runs_completed, best_pipes, best_seconds,
			gameplay_coins, coin_runs,
			dives_entered, dives_completed, best_dives, dive_seconds,
			lane_changes, lanes_left, lanes_right,
			obstacles_dodged, best_obstacles, mines_passed,
			run_pipes
		);
		complete := coalesce((snap ->> 'complete')::boolean, false);
	end if;

	if not complete then
		board := public.reefrun_daily_mission_board(uid);
		return board || pg_catalog.jsonb_build_object(
			'ok', false, 'reason', 'incomplete', 'granted_now', 0
		);
	end if;

	select coalesce(sum(coins), 0) into existing_sum
	from public.daily_mission_claims
	where player_id = uid and mission_date = today;
	if existing_sum + reward > 60 then
		board := public.reefrun_daily_mission_board(uid);
		return board || pg_catalog.jsonb_build_object(
			'ok', false, 'reason', 'cap', 'granted_now', 0
		);
	end if;

	insert into public.daily_mission_claims (player_id, mission_date, slot, coins, mission_id)
	values (uid, today, p_slot, reward, mid)
	on conflict (player_id, mission_date, slot) do nothing;
	get diagnostics wrote = row_count;
	if wrote = 0 then
		board := public.reefrun_daily_mission_board(uid);
		return board || pg_catalog.jsonb_build_object('granted_now', 0, 'reason', 'already');
	end if;

	update public.profiles
	set mission_reward_coins = mission_reward_coins + reward
	where id = uid;
	get diagnostics wrote = row_count;
	if wrote <> 1 then
		raise exception 'daily mission reward was not credited';
	end if;

	board := public.reefrun_daily_mission_board(uid);
	return board || pg_catalog.jsonb_build_object('granted_now', reward, 'reason', 'claimed');
end;
$fn$;

-- Twelve-argument recorder. Created before the four-argument wrapper so the
-- wrapper can call it. The extra arguments have no defaults: a four-key
-- request stays on the four-argument function, and a twelve-key request
-- stays on this one. Defaults would make those two calls ambiguous.
-- Pipe totals, best pipes, best survival, and coins accumulate exactly as
-- the live function does.
create or replace function public.record_unlimited_mission_run(
	p_run_id text,
	p_pipes integer,
	p_seconds integer,
	p_gameplay_coins integer,
	p_dives_entered integer,
	p_dives_completed integer,
	p_dive_seconds integer,
	p_lane_changes integer,
	p_lanes_left integer,
	p_lanes_right integer,
	p_obstacles integer,
	p_mines integer
) returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
	uid uuid := auth.uid();
	today date := (pg_catalog.timezone('America/New_York', pg_catalog.now()))::date;
	board jsonb;
	wrote integer := 0;
	scheduled_dives integer := 0;
	short_limit integer := 0;
	long_limit integer := 0;
begin
	if uid is null then
		return pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
	end if;
	if p_pipes is not null and p_pipes >= 30 then
		scheduled_dives := 1 + (p_pipes - 30) / 30;
	end if;
	if p_pipes is not null and p_pipes < 80 then
		short_limit := floor(
			1.8::numeric + p_pipes * 1.5 + 12 + 12 * (p_pipes / 20)
		)::integer + 28 * coalesce(p_dives_entered, 0);
	end if;
	if p_pipes is not null and p_pipes > 80 then
		long_limit := floor(
			1.8::numeric + p_pipes * 1.5 + 12 + 12 * (p_pipes / 20)
		)::integer + 28 * coalesce(p_dives_entered, 0);
	end if;
	if p_run_id is null or p_run_id !~ '^[A-Za-z0-9_-]{8,80}$'
		or p_pipes is null or p_pipes < 0 or p_pipes > 20000
		or p_seconds is null or p_seconds < 0 or p_seconds > 86400
		or p_gameplay_coins is null or p_gameplay_coins < 0
		or p_gameplay_coins > p_pipes / 5
		or (p_pipes > 0 and p_seconds < (p_pipes - 1))
		or p_dives_entered is null or p_dives_completed is null
		or p_dive_seconds is null or p_lane_changes is null
		or p_lanes_left is null or p_lanes_right is null
		or p_obstacles is null or p_mines is null
		or p_dives_entered < 0 or p_dives_completed < 0
		or p_dive_seconds < 0 or p_lane_changes < 0
		or p_lanes_left < 0 or p_lanes_right < 0
		or p_obstacles < 0 or p_mines < 0
		or p_dives_completed > p_dives_entered
		or p_dive_seconds > p_dives_entered * 20
		or p_lanes_left + p_lanes_right <> p_lane_changes
		or p_mines > p_obstacles
		or p_dives_entered > scheduled_dives
		or p_obstacles > greatest(80, p_dives_entered * 30)
		or p_lane_changes > greatest(400, p_dives_entered * 160)
		or (p_dives_entered = 0 and (
			p_dives_completed > 0 or p_dive_seconds > 0
			or p_lane_changes > 0 or p_obstacles > 0
		))
		or (p_pipes < 80 and p_seconds > short_limit)
		or (p_pipes <= 80 and p_seconds > 1800)
		or (p_pipes > 80 and p_seconds > long_limit)
	then
		return pg_catalog.jsonb_build_object('ok', false, 'reason', 'rejected', 'accepted', false);
	end if;

	perform pg_advisory_xact_lock(872342, hashtext(uid::text || today::text));
	insert into public.profiles (id, display_name) values (uid, 'YOU') on conflict (id) do nothing;
	perform 1 from public.profiles where id = uid for update;

	insert into public.daily_mission_run_log (
		player_id, run_id, mission_date, pipes, seconds, gameplay_coins,
		dives_entered, dives_completed, dive_seconds,
		lane_changes, lanes_left, lanes_right, obstacles, mines
	) values (
		uid, p_run_id, today, p_pipes, p_seconds, p_gameplay_coins,
		p_dives_entered, p_dives_completed, p_dive_seconds,
		p_lane_changes, p_lanes_left, p_lanes_right, p_obstacles, p_mines
	)
	on conflict (player_id, run_id) do nothing;
	get diagnostics wrote = row_count;
	if wrote = 0 then
		board := public.reefrun_daily_mission_board(uid);
		return board || pg_catalog.jsonb_build_object('reason', 'duplicate', 'accepted', false);
	end if;

	insert into public.daily_mission_progress (
		player_id, mission_date, pipes_total, runs_completed, best_pipes,
		best_seconds, gameplay_coins, coin_runs, run_pipes,
		dives_entered, dives_completed, best_dives, dive_seconds,
		lane_changes, lanes_left, lanes_right,
		obstacles_dodged, best_obstacles, mines_passed
	) values (
		uid, today, p_pipes, 1, p_pipes, p_seconds, p_gameplay_coins,
		case when p_gameplay_coins > 0 then 1 else 0 end,
		array[p_pipes],
		p_dives_entered, p_dives_completed, p_dives_completed, p_dive_seconds,
		p_lane_changes, p_lanes_left, p_lanes_right,
		p_obstacles, p_obstacles, p_mines
	)
	on conflict (player_id, mission_date) do update set
		pipes_total = public.daily_mission_progress.pipes_total + excluded.pipes_total,
		runs_completed = public.daily_mission_progress.runs_completed + 1,
		best_pipes = greatest(public.daily_mission_progress.best_pipes, excluded.best_pipes),
		best_seconds = greatest(public.daily_mission_progress.best_seconds, excluded.best_seconds),
		gameplay_coins = public.daily_mission_progress.gameplay_coins + excluded.gameplay_coins,
		coin_runs = public.daily_mission_progress.coin_runs + excluded.coin_runs,
		run_pipes = case
			when coalesce(array_length(public.daily_mission_progress.run_pipes, 1), 0) >= 60
				then public.daily_mission_progress.run_pipes
			else public.daily_mission_progress.run_pipes || excluded.run_pipes
		end,
		dives_entered = public.daily_mission_progress.dives_entered + excluded.dives_entered,
		dives_completed = public.daily_mission_progress.dives_completed + excluded.dives_completed,
		best_dives = greatest(public.daily_mission_progress.best_dives, excluded.best_dives),
		dive_seconds = public.daily_mission_progress.dive_seconds + excluded.dive_seconds,
		lane_changes = public.daily_mission_progress.lane_changes + excluded.lane_changes,
		lanes_left = public.daily_mission_progress.lanes_left + excluded.lanes_left,
		lanes_right = public.daily_mission_progress.lanes_right + excluded.lanes_right,
		obstacles_dodged = public.daily_mission_progress.obstacles_dodged + excluded.obstacles_dodged,
		best_obstacles = greatest(public.daily_mission_progress.best_obstacles, excluded.best_obstacles),
		mines_passed = public.daily_mission_progress.mines_passed + excluded.mines_passed;

	board := public.reefrun_daily_mission_board(uid);
	return board || pg_catalog.jsonb_build_object('reason', 'recorded', 'accepted', true);
end;
$fn$;

create or replace function public.record_unlimited_mission_run(
	p_run_id text,
	p_pipes integer,
	p_seconds integer,
	p_gameplay_coins integer
) returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
begin
	return public.record_unlimited_mission_run(
		p_run_id, p_pipes, p_seconds, p_gameplay_coins,
		0, 0, 0, 0, 0, 0, 0, 0
	);
end;
$fn$;

revoke all on function public.reefrun_mission_snapshot(
	text, integer, integer,
	integer, integer, integer, integer,
	integer, integer,
	integer, integer, integer, integer,
	integer, integer, integer,
	integer, integer, integer,
	integer[]
) from public, anon, authenticated;
revoke all on function public.reefrun_daily_mission_board(uuid) from public, anon, authenticated;
revoke all on function public.claim_daily_mission(text) from public, anon, authenticated;
revoke all on function public.record_unlimited_mission_run(text, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.record_unlimited_mission_run(
	text, integer, integer, integer,
	integer, integer, integer,
	integer, integer, integer,
	integer, integer
) from public, anon, authenticated;

grant execute on function public.claim_daily_mission(text) to authenticated;
grant execute on function public.record_unlimited_mission_run(text, integer, integer, integer) to authenticated;
grant execute on function public.record_unlimited_mission_run(
	text, integer, integer, integer,
	integer, integer, integer,
	integer, integer, integer,
	integer, integer
) to authenticated;

notify pgrst, 'reload schema';
