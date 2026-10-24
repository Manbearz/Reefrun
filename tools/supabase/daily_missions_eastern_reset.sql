-- Move Daily Missions from midnight UTC to midnight America/New_York.
-- Supabase Dashboard → SQL Editor → New query → paste this file → Run.
-- Do not run until this reset change is approved.
--
-- The Daily Challenge and Daily leaderboard already use this boundary:
--   challenge date: (timezone('America/New_York', now()))::date
--   reset instant:  (that date + 1) at time zone 'America/New_York'
-- Postgres applies US daylight saving time for America/New_York, so midnight
-- is 04:00 UTC during EDT and 05:00 UTC during EST. It is not the player's
-- device timezone.
--
-- Replaces the mission board, claim, and record functions. get_daily_missions
-- reads the board function, so its day changes with this file.
-- Does not insert, update, or delete mission progress, claims, coin balances,
-- or mission sets. Existing mission_date rows stay on the date they were
-- written. A claim is still unique per player, date, and slot.
-- Rewards stay +5 / +10 / +20 and the +25 bonus. One Easy, Medium, and Hard
-- set per date. Daily Challenge attempts are not touched.

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

drop function if exists public.record_unlimited_mission_run(text, integer, integer, integer);

create or replace function public.record_unlimited_mission_run(
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
	today date := (pg_catalog.timezone('America/New_York', pg_catalog.now()))::date;
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
