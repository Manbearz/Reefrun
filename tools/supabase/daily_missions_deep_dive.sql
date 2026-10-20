-- Deep Dive daily missions. Run this yourself in Supabase → SQL Editor → New query.
-- Do not run it from the game, and do not run it more than once unless a
-- previous attempt failed and was rolled back. The script is safe to retry:
-- new columns use IF NOT EXISTS, and the mission rows update in place.
--
-- What this changes
--   Adds 15 Easy, 15 Medium, and 15 Hard Deep Dive missions (ids 46–90).
--   Existing missions 1–45 are not updated, disabled, or deleted.
--   The board still stores one easy id, one medium id, and one hard id.
--   Rewards stay +5, +10, +20, and the +25 bonus. The claim cap stays 60.
--   A UTC day whose row already exists in daily_mission_sets is left alone.
--   The new missions join the rotation on the next UTC date that does not
--   already have a set. Selection stays the existing deterministic picker.
--
-- What this does not change
--   Coins already claimed, mission progress already stored, profiles,
--   leaderboards, Daily Challenge, ghosts, cosmetics, and share rewards.
--   The old four-argument record call still works. The new arguments
--   default to 0, so a build from before this migration keeps recording
--   pipe runs. After you run this script, reload the API schema (the
--   NOTIFY at the bottom does that).
--
-- Apply
--   1. Open the Supabase project used by ReefRun.
--   2. SQL Editor → New query.
--   3. Paste this whole file and run it.
--   4. Confirm the last select returns 45 new rows and 90 definitions.

alter table public.mission_definitions drop constraint if exists mission_definitions_id_check;
alter table public.mission_definitions drop constraint if exists mission_definitions_rule_check;

do $bounds$
declare
	r record;
begin
	for r in
		select con.conname
		from pg_constraint as con
		where con.conrelid = 'public.mission_definitions'::regclass
			and con.contype = 'c'
			and (
				pg_get_constraintdef(con.oid) ilike '%id <= 45%'
				or pg_get_constraintdef(con.oid) ilike '%pipes_total%'
			)
	loop
		execute format('alter table public.mission_definitions drop constraint %I', r.conname);
	end loop;
end
$bounds$;

alter table public.mission_definitions
	add constraint mission_definitions_id_check check (id between 1 and 90);

alter table public.mission_definitions
	add constraint mission_definitions_rule_check check (rule in (
		'pipes_total', 'pipes_best', 'runs', 'survive_best',
		'coins_total', 'coin_runs', 'runs_at_least', 'window_sum',
		'dives_entered', 'dives_completed', 'dives_best', 'dive_seconds',
		'lanes_total', 'lanes_left', 'lanes_right',
		'obstacles_total', 'obstacles_best', 'mines_total'
	));

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

insert into public.mission_definitions (id, tier, family, description, reward, rule, goal, goal_b, enabled)
values
	(46, 'easy', 'dive_enter', 'Deep Diver: enter a dive.', 5, 'dives_entered', 1, 0, true),
	(47, 'easy', 'dive_lanes', 'First Splash: switch lanes 10 times.', 5, 'lanes_total', 10, 0, true),
	(48, 'easy', 'dive_time', 'Into the Abyss: spend 20 seconds diving.', 5, 'dive_seconds', 20, 0, true),
	(49, 'easy', 'dive_left', 'Side Stepper: move left 10 times.', 5, 'lanes_left', 10, 0, true),
	(50, 'easy', 'dive_enter', 'Deep Traveler: enter 2 dives.', 5, 'dives_entered', 2, 0, true),
	(51, 'easy', 'dive_dodge', 'Quick Fins: dodge 5 obstacles.', 5, 'obstacles_total', 5, 0, true),
	(52, 'easy', 'dive_right', 'Right Turn: move right 10 times.', 5, 'lanes_right', 10, 0, true),
	(53, 'easy', 'dive_time', 'Warm Up: spend 10 seconds diving.', 5, 'dive_seconds', 10, 0, true),
	(54, 'easy', 'dive_dodge', 'Light Dodge: dodge 3 obstacles.', 5, 'obstacles_total', 3, 0, true),
	(55, 'easy', 'dive_complete', 'Surface: finish a dive.', 5, 'dives_completed', 1, 0, true),
	(56, 'easy', 'dive_lanes', 'Little Nudge: switch lanes 5 times.', 5, 'lanes_total', 5, 0, true),
	(57, 'easy', 'dive_left', 'Port Side: move left 5 times.', 5, 'lanes_left', 5, 0, true),
	(58, 'easy', 'dive_right', 'Starboard: move right 5 times.', 5, 'lanes_right', 5, 0, true),
	(59, 'easy', 'dive_dodge', 'Clear Path: dodge 8 obstacles.', 5, 'obstacles_total', 8, 0, true),
	(60, 'easy', 'dive_time', 'Hold Breath: spend 15 seconds diving.', 5, 'dive_seconds', 15, 0, true),
	(61, 'medium', 'dive_dodge', 'Close Call: dodge 15 obstacles.', 10, 'obstacles_total', 15, 0, true),
	(62, 'medium', 'dive_enter', 'Deep Explorer: enter 3 dives.', 10, 'dives_entered', 3, 0, true),
	(63, 'medium', 'dive_dodge', 'Slippery Fish: dodge 30 obstacles.', 10, 'obstacles_total', 30, 0, true),
	(64, 'medium', 'dive_lanes', 'Ocean Navigator: switch lanes 30 times.', 10, 'lanes_total', 30, 0, true),
	(65, 'medium', 'dive_complete', 'Deep Survivor: finish 2 dives.', 10, 'dives_completed', 2, 0, true),
	(66, 'medium', 'dive_mines', 'Mine Dodger: pass 5 mines.', 10, 'mines_total', 5, 0, true),
	(67, 'medium', 'dive_time', 'Deep Breath: spend 40 seconds diving.', 10, 'dive_seconds', 40, 0, true),
	(68, 'medium', 'dive_left', 'Left Current: move left 20 times.', 10, 'lanes_left', 20, 0, true),
	(69, 'medium', 'dive_right', 'Right Current: move right 20 times.', 10, 'lanes_right', 20, 0, true),
	(70, 'medium', 'dive_enter', 'Return Trip: enter 4 dives.', 10, 'dives_entered', 4, 0, true),
	(71, 'medium', 'dive_dodge', 'Steady Weave: dodge 20 obstacles.', 10, 'obstacles_total', 20, 0, true),
	(72, 'medium', 'dive_mines', 'Mine Watch: pass 3 mines.', 10, 'mines_total', 3, 0, true),
	(73, 'medium', 'dive_lanes', 'Lane Hopper: switch lanes 20 times.', 10, 'lanes_total', 20, 0, true),
	(74, 'medium', 'dive_time', 'One Minute: spend 60 seconds diving.', 10, 'dive_seconds', 60, 0, true),
	(75, 'medium', 'dive_mines', 'Mine Line: pass 8 mines.', 10, 'mines_total', 8, 0, true),
	(76, 'hard', 'dive_complete', 'Survivor of the Deep: finish 3 dives.', 20, 'dives_completed', 3, 0, true),
	(77, 'hard', 'dive_complete', 'Depth Master: finish 4 dives.', 20, 'dives_completed', 4, 0, true),
	(78, 'hard', 'dive_one_run', 'Untouchable: finish 2 dives in one run.', 20, 'dives_best', 2, 0, true),
	(79, 'hard', 'dive_dodge', 'Danger Below: dodge 60 obstacles.', 20, 'obstacles_total', 60, 0, true),
	(80, 'hard', 'dive_lanes', 'Master Navigator: switch lanes 75 times.', 20, 'lanes_total', 75, 0, true),
	(81, 'hard', 'dive_mines', 'Minefield Expert: pass 15 mines.', 20, 'mines_total', 15, 0, true),
	(82, 'hard', 'dive_dodge', 'Wide Berth: dodge 45 obstacles.', 20, 'obstacles_total', 45, 0, true),
	(83, 'hard', 'dive_lanes', 'Swift Fins: switch lanes 50 times.', 20, 'lanes_total', 50, 0, true),
	(84, 'hard', 'dive_mines', 'Mine Course: pass 10 mines.', 20, 'mines_total', 10, 0, true),
	(85, 'hard', 'dive_time', 'Stay Down: spend 50 seconds diving.', 20, 'dive_seconds', 50, 0, true),
	(86, 'hard', 'dive_left', 'Port Master: move left 35 times.', 20, 'lanes_left', 35, 0, true),
	(87, 'hard', 'dive_right', 'Starboard Master: move right 35 times.', 20, 'lanes_right', 35, 0, true),
	(88, 'hard', 'dive_enter', 'Frequent Diver: enter 6 dives.', 20, 'dives_entered', 6, 0, true),
	(89, 'hard', 'dive_dodge', 'Full Course: dodge 18 obstacles in one run.', 20, 'obstacles_best', 18, 0, true),
	(90, 'hard', 'dive_enter', 'Five Down: enter 5 dives.', 20, 'dives_entered', 5, 0, true)
on conflict (id) do update set
	tier = excluded.tier,
	family = excluded.family,
	description = excluded.description,
	reward = excluded.reward,
	rule = excluded.rule,
	goal = excluded.goal,
	goal_b = excluded.goal_b,
	enabled = excluded.enabled
where public.mission_definitions.id >= 46;

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
	today date := (timezone('utc', pg_catalog.now()))::date;
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
		'resets_at', extract(epoch from ((today + 1)::timestamp at time zone 'utc'))::bigint,
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
	today date := (timezone('utc', pg_catalog.now()))::date;
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

drop function if exists public.record_unlimited_mission_run(text, integer, integer, integer);
drop function if exists public.record_unlimited_mission_run(
	text, integer, integer, integer,
	integer, integer, integer,
	integer, integer, integer,
	integer, integer
);

create function public.record_unlimited_mission_run(
	p_run_id text,
	p_pipes integer,
	p_seconds integer,
	p_gameplay_coins integer,
	p_dives_entered integer default 0,
	p_dives_completed integer default 0,
	p_dive_seconds integer default 0,
	p_lane_changes integer default 0,
	p_lanes_left integer default 0,
	p_lanes_right integer default 0,
	p_obstacles integer default 0,
	p_mines integer default 0
) returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
	uid uuid := auth.uid();
	today date := (timezone('utc', pg_catalog.now()))::date;
	board jsonb;
	wrote integer := 0;
begin
	if uid is null then
		return pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
	end if;
	if p_run_id is null or p_run_id !~ '^[A-Za-z0-9_-]{8,80}$'
		or p_pipes is null or p_pipes < 0 or p_pipes > 80
		or p_seconds is null or p_seconds < 0 or p_seconds > 1800
		or p_gameplay_coins is null or p_gameplay_coins < 0
		or p_gameplay_coins > p_pipes / 5
		or (p_pipes > 0 and p_seconds < (p_pipes - 1))
		or p_dives_entered is null or p_dives_entered < 0 or p_dives_entered > 2
		or p_dives_completed is null or p_dives_completed < 0 or p_dives_completed > p_dives_entered
		or p_dive_seconds is null or p_dive_seconds < 0 or p_dive_seconds > p_dives_entered * 20
		or p_lane_changes is null or p_lane_changes < 0 or p_lane_changes > 400
		or p_lanes_left is null or p_lanes_right is null
		or p_lanes_left < 0 or p_lanes_right < 0
		or p_lanes_left + p_lanes_right <> p_lane_changes
		or p_obstacles is null or p_obstacles < 0 or p_obstacles > 80
		or p_mines is null or p_mines < 0 or p_mines > p_obstacles
		or (p_pipes < 30 and p_dives_entered > 0)
		or (p_pipes < 60 and p_dives_entered > 1)
		or (
			p_dives_entered = 0
			and (
				p_dives_completed > 0 or p_dive_seconds > 0
				or p_lane_changes > 0 or p_obstacles > 0
			)
		)
		or (
			p_pipes < 80
			and p_seconds > floor(
				1.8::numeric
				+ p_pipes * 1.5
				+ 12
				+ 12 * (p_pipes / 20)
			)::integer + 28 * p_dives_entered
		)
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

drop function if exists public.reefrun_mission_snapshot(
	text, integer, integer, integer, integer, integer, integer, integer, integer, integer[]
);

revoke all on function public.reefrun_mission_snapshot(
	text, integer, integer, integer, integer, integer, integer, integer, integer,
	integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer[]
) from public, anon, authenticated;
revoke all on function public.reefrun_daily_mission_board(uuid) from public, anon, authenticated;
revoke all on function public.claim_daily_mission(text) from public, anon, authenticated;
revoke all on function public.record_unlimited_mission_run(
	text, integer, integer, integer,
	integer, integer, integer,
	integer, integer, integer,
	integer, integer
) from public, anon, authenticated;

grant execute on function public.get_daily_missions() to authenticated;
grant execute on function public.claim_daily_mission(text) to authenticated;
grant execute on function public.record_unlimited_mission_run(
	text, integer, integer, integer,
	integer, integer, integer,
	integer, integer, integer,
	integer, integer
) to authenticated;

notify pgrst, 'reload schema';

select
	count(*) filter (where id between 46 and 90) as deep_dive_missions,
	count(*) as definitions
from public.mission_definitions;
