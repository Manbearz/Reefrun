-- Daily Missions. Run this yourself in Supabase → SQL Editor → New query.
-- Do not run it from the game. The game keeps using the anon key only.
--
-- Daily Missions never reads or writes daily_challenges, daily_attempts,
-- leaderboard_scores, or ghost_runs. Daily Challenge attempts and the Daily
-- Challenge leaderboard stay on their existing functions. Unlimited weekly and
-- monthly scores stay on submit_leaderboard_score. A mission claim updates
-- profiles.mission_reward_coins only. The live profiles table has id,
-- display_name, and created_at. This script does not read or write a coins,
-- selected_fish, selected_hat, or share_reward_coins column.
-- This script does not drop tables, does not delete rows, and does not replace
-- Daily Challenge, leaderboard, profile, or share-reward functions.
-- It does not change existing profile grants.
--
-- Impact on existing data:
--   profiles gains mission_reward_coins integer default 0.
--   That column is a lifetime counter of mission coins already claimed.
--   The spendable wallet the player sees stays on the device.
--   The game adds only the difference between this counter and the local
--   applied_mission_reward_coins value. Restarting, reconnecting, or retrying
--   a claim does not add the same reward again.
--   Authenticated clients are not granted UPDATE on mission_reward_coins.
--   Existing profile rows, names, RLS policies, and cosmetics are left in place.
--
-- Rotation:
--   One easy, one medium, and one hard mission are inserted once per UTC date.
--   A transaction lock makes the first request of the day the only writer.
--   Later requests read that row. The row cannot be updated.
--   Selection uses the database clock, never a device clock.
--   Missions used on the previous 7 UTC days are skipped when another
--   enabled mission in that tier exists.
--   The three missions chosen for one day use different objective families
--   when another family is available.
--
-- Excluded from rotation until the course or the tracking changes:
--   6  Reach checkpoint 5. Same objective as mission 12.
--   13 Reach 10 pipes in one run. Same objective as mission 3.
--   23 Reach checkpoint 10. Same objective as mission 3.
--   35 Pass 100 pipes in one run. Unlimited course is 80 pipes.
--   36 Pass 125 pipes in one run. Unlimited course is 80 pipes.
--   37 Pass 150 pipes in one run. Unlimited course is 80 pipes.
-- Mission 39 stays enabled. "Checkpoint" is a scored pipe. ReefRun has no
-- separate checkpoint object; every passed pipe is the checkpoint event.
--
-- Anti-cheat, and what it does not prove:
--   The server recomputes completion from stored run facts.
--   It ignores any client completion flag or reward amount.
--   A run is rejected unless pipes are 0..80, seconds are 0..1800,
--   and gameplay coins are at most one per five pipes. A coin is placed
--   after every 5th spawned pipe, between that pipe and the next, so a
--   swim cannot pick up more than pipes / 5. The death-screen ad bonus is
--   not included. Survival time is the pipe schedule plus harpoon volleys:
--   every 20 pipes, spawning pauses for 3 shots and the next pipe is shifted
--   forward, while the score stays still. The same run id cannot be applied twice.
--   Claim rows are unique per player, UTC day, and slot.
--   A trigger rejects any day whose claim coins add up to more than 60.
--   There is no server replay of an Unlimited swim. A modified client can
--   still submit a plausible fake run inside those bounds. Daily Challenge
--   ghost checks are unchanged and are not used here.
--   A finished run uploaded after the next UTC midnight counts for the
--   server's current UTC day, because the device clock is not trusted.

alter table public.profiles
	add column if not exists mission_reward_coins integer not null default 0;

do $fn$
begin
	if not exists (
		select 1
		from pg_catalog.pg_constraint
		where conname = 'profiles_mission_reward_coins_check'
	) then
		alter table public.profiles
			add constraint profiles_mission_reward_coins_check
			check (mission_reward_coins >= 0);
	end if;
end
$fn$;

revoke update (mission_reward_coins) on table public.profiles from public, anon, authenticated;

create table if not exists public.mission_definitions (
	id integer primary key check (id between 1 and 45),
	tier text not null check (tier in ('easy', 'medium', 'hard')),
	family text not null,
	description text not null,
	reward integer not null,
	rule text not null check (rule in (
		'pipes_total', 'pipes_best', 'runs', 'survive_best',
		'coins_total', 'coin_runs', 'runs_at_least', 'window_sum'
	)),
	goal integer not null check (goal > 0),
	goal_b integer not null default 0 check (goal_b >= 0),
	enabled boolean not null default true,
	constraint mission_definitions_reward_tier check (
		(tier = 'easy' and reward = 5)
		or (tier = 'medium' and reward = 10)
		or (tier = 'hard' and reward = 20)
	)
);

create table if not exists public.daily_mission_sets (
	mission_date date primary key,
	easy_id integer not null references public.mission_definitions (id),
	medium_id integer not null references public.mission_definitions (id),
	hard_id integer not null references public.mission_definitions (id),
	selected_at timestamptz not null default pg_catalog.now(),
	constraint daily_mission_sets_distinct check (
		easy_id <> medium_id and medium_id <> hard_id and easy_id <> hard_id
	)
);

create table if not exists public.daily_mission_progress (
	player_id uuid not null references public.profiles (id) on delete cascade,
	mission_date date not null,
	pipes_total integer not null default 0 check (pipes_total >= 0),
	runs_completed integer not null default 0 check (runs_completed >= 0),
	best_pipes integer not null default 0 check (best_pipes between 0 and 80),
	best_seconds integer not null default 0 check (best_seconds between 0 and 1800),
	gameplay_coins integer not null default 0 check (gameplay_coins >= 0),
	coin_runs integer not null default 0 check (coin_runs >= 0),
	run_pipes integer[] not null default '{}',
	primary key (player_id, mission_date)
);

create table if not exists public.daily_mission_run_log (
	player_id uuid not null references public.profiles (id) on delete cascade,
	run_id text not null check (run_id ~ '^[A-Za-z0-9_-]{8,80}$'),
	mission_date date not null,
	pipes integer not null check (pipes between 0 and 80),
	seconds integer not null check (seconds between 0 and 1800),
	gameplay_coins integer not null check (gameplay_coins >= 0),
	created_at timestamptz not null default pg_catalog.now(),
	primary key (player_id, run_id)
);

create table if not exists public.daily_mission_claims (
	player_id uuid not null references public.profiles (id) on delete cascade,
	mission_date date not null,
	slot text not null check (slot in ('easy', 'medium', 'hard', 'bonus')),
	coins integer not null,
	mission_id integer,
	claimed_at timestamptz not null default pg_catalog.now(),
	primary key (player_id, mission_date, slot),
	constraint daily_mission_claims_amount check (
		(slot = 'easy' and coins = 5)
		or (slot = 'medium' and coins = 10)
		or (slot = 'hard' and coins = 20)
		or (slot = 'bonus' and coins = 25 and mission_id is null)
	)
);

create or replace function public.reefrun_daily_sets_immutable()
returns trigger
language plpgsql
as $fn$
begin
	raise exception 'daily mission sets are immutable';
end;
$fn$;

drop trigger if exists daily_mission_sets_no_update on public.daily_mission_sets;
create trigger daily_mission_sets_no_update
	before update on public.daily_mission_sets
	for each row execute function public.reefrun_daily_sets_immutable();

create or replace function public.reefrun_mission_claim_cap()
returns trigger
language plpgsql
as $fn$
declare
	total integer;
begin
	select coalesce(sum(coins), 0) into total
	from public.daily_mission_claims
	where player_id = new.player_id
		and mission_date = new.mission_date;
	if total > 60 then
		raise exception 'daily mission reward cap';
	end if;
	return new;
end;
$fn$;

drop trigger if exists daily_mission_claims_cap on public.daily_mission_claims;
create trigger daily_mission_claims_cap
	after insert on public.daily_mission_claims
	for each row execute function public.reefrun_mission_claim_cap();

alter table public.mission_definitions enable row level security;
alter table public.daily_mission_sets enable row level security;
alter table public.daily_mission_progress enable row level security;
alter table public.daily_mission_run_log enable row level security;
alter table public.daily_mission_claims enable row level security;

drop policy if exists mission_definitions_read on public.mission_definitions;
create policy mission_definitions_read on public.mission_definitions
	for select to authenticated using (true);

drop policy if exists daily_mission_sets_read on public.daily_mission_sets;
create policy daily_mission_sets_read on public.daily_mission_sets
	for select to authenticated using (true);

drop policy if exists daily_mission_progress_read on public.daily_mission_progress;
create policy daily_mission_progress_read on public.daily_mission_progress
	for select to authenticated using (player_id = auth.uid());

drop policy if exists daily_mission_claims_read on public.daily_mission_claims;
create policy daily_mission_claims_read on public.daily_mission_claims
	for select to authenticated using (player_id = auth.uid());

revoke all on public.mission_definitions from public, anon, authenticated;
revoke all on public.daily_mission_sets from public, anon, authenticated;
revoke all on public.daily_mission_progress from public, anon, authenticated;
revoke all on public.daily_mission_run_log from public, anon, authenticated;
revoke all on public.daily_mission_claims from public, anon, authenticated;

grant select on public.mission_definitions to authenticated;
grant select on public.daily_mission_sets to authenticated;
grant select on public.daily_mission_progress to authenticated;
grant select on public.daily_mission_claims to authenticated;

insert into public.mission_definitions (id, tier, family, description, reward, rule, goal, goal_b, enabled)
values
	(1, 'easy', 'total_pipes', 'Pass 10 pipes total.', 5, 'pipes_total', 10, 0, true),
	(2, 'easy', 'total_pipes', 'Pass 25 pipes total.', 5, 'pipes_total', 25, 0, true),
	(3, 'easy', 'one_run_pipes', 'Pass 10 pipes in one run.', 5, 'pipes_best', 10, 0, true),
	(4, 'easy', 'run_count', 'Complete 3 runs.', 5, 'runs', 3, 0, true),
	(5, 'easy', 'run_count', 'Complete 5 runs.', 5, 'runs', 5, 0, true),
	(6, 'easy', 'one_run_pipes', 'Reach checkpoint 5.', 5, 'pipes_best', 5, 0, false),
	(7, 'easy', 'survive', 'Survive 30 seconds in one run.', 5, 'survive_best', 30, 0, true),
	(8, 'easy', 'earn_coins', 'Earn 50 coins through normal gameplay.', 5, 'coins_total', 50, 0, true),
	(9, 'easy', 'earn_coins', 'Earn 100 coins through normal gameplay.', 5, 'coins_total', 100, 0, true),
	(10, 'easy', 'coin_runs', 'Collect coins in 3 separate runs.', 5, 'coin_runs', 3, 0, true),
	(11, 'easy', 'multi_threshold', 'Pass at least 5 pipes in 3 different runs.', 5, 'runs_at_least', 5, 3, true),
	(12, 'easy', 'one_run_pipes', 'Reach 5 pipes in one run.', 5, 'pipes_best', 5, 0, true),
	(13, 'easy', 'one_run_pipes', 'Reach 10 pipes in one run.', 5, 'pipes_best', 10, 0, false),
	(14, 'easy', 'total_pipes', 'Pass 15 pipes total.', 5, 'pipes_total', 15, 0, true),
	(15, 'easy', 'multi_threshold', 'Complete 2 runs with at least 5 pipes each.', 5, 'runs_at_least', 5, 2, true),
	(16, 'medium', 'total_pipes', 'Pass 50 pipes total.', 10, 'pipes_total', 50, 0, true),
	(17, 'medium', 'total_pipes', 'Pass 75 pipes total.', 10, 'pipes_total', 75, 0, true),
	(18, 'medium', 'total_pipes', 'Pass 100 pipes total.', 10, 'pipes_total', 100, 0, true),
	(19, 'medium', 'one_run_pipes', 'Pass 25 pipes in one run.', 10, 'pipes_best', 25, 0, true),
	(20, 'medium', 'one_run_pipes', 'Pass 40 pipes in one run.', 10, 'pipes_best', 40, 0, true),
	(21, 'medium', 'run_count', 'Complete 10 runs.', 10, 'runs', 10, 0, true),
	(22, 'medium', 'run_count', 'Complete 15 runs.', 10, 'runs', 15, 0, true),
	(23, 'medium', 'one_run_pipes', 'Reach checkpoint 10.', 10, 'pipes_best', 10, 0, false),
	(24, 'medium', 'survive', 'Survive 60 seconds in one run.', 10, 'survive_best', 60, 0, true),
	(25, 'medium', 'survive', 'Survive 90 seconds in one run.', 10, 'survive_best', 90, 0, true),
	(26, 'medium', 'earn_coins', 'Earn 250 coins through normal gameplay.', 10, 'coins_total', 250, 0, true),
	(27, 'medium', 'coin_runs', 'Collect coins in 5 separate runs.', 10, 'coin_runs', 5, 0, true),
	(28, 'medium', 'multi_threshold', 'Pass at least 10 pipes in 3 different runs.', 10, 'runs_at_least', 10, 3, true),
	(29, 'medium', 'multi_threshold', 'Reach 15 pipes in 2 different runs.', 10, 'runs_at_least', 15, 2, true),
	(30, 'medium', 'window_sum', 'Pass 50 pipes across no more than 3 runs.', 10, 'window_sum', 50, 3, true),
	(31, 'hard', 'total_pipes', 'Pass 150 pipes total.', 20, 'pipes_total', 150, 0, true),
	(32, 'hard', 'total_pipes', 'Pass 200 pipes total.', 20, 'pipes_total', 200, 0, true),
	(33, 'hard', 'one_run_pipes', 'Pass 50 pipes in one run.', 20, 'pipes_best', 50, 0, true),
	(34, 'hard', 'one_run_pipes', 'Pass 75 pipes in one run.', 20, 'pipes_best', 75, 0, true),
	(35, 'hard', 'one_run_pipes', 'Pass 100 pipes in one run.', 20, 'pipes_best', 100, 0, false),
	(36, 'hard', 'one_run_pipes', 'Pass 125 pipes in one run.', 20, 'pipes_best', 125, 0, false),
	(37, 'hard', 'one_run_pipes', 'Pass 150 pipes in one run.', 20, 'pipes_best', 150, 0, false),
	(38, 'hard', 'run_count', 'Complete 20 runs.', 20, 'runs', 20, 0, true),
	(39, 'hard', 'one_run_pipes', 'Reach checkpoint 20.', 20, 'pipes_best', 20, 0, true),
	(40, 'hard', 'survive', 'Survive 120 seconds in one run.', 20, 'survive_best', 120, 0, true),
	(41, 'hard', 'survive', 'Survive 180 seconds in one run.', 20, 'survive_best', 180, 0, true),
	(42, 'hard', 'earn_coins', 'Earn 500 coins through normal gameplay.', 20, 'coins_total', 500, 0, true),
	(43, 'hard', 'multi_threshold', 'Pass at least 20 pipes in 3 different runs.', 20, 'runs_at_least', 20, 3, true),
	(44, 'hard', 'multi_threshold', 'Reach 25 pipes in 2 different runs.', 20, 'runs_at_least', 25, 2, true),
	(45, 'hard', 'window_sum', 'Pass 100 pipes across no more than 5 runs.', 20, 'window_sum', 100, 5, true)
on conflict (id) do update set
	tier = excluded.tier,
	family = excluded.family,
	description = excluded.description,
	reward = excluded.reward,
	rule = excluded.rule,
	goal = excluded.goal,
	goal_b = excluded.goal_b,
	enabled = excluded.enabled;

create or replace function public.reefrun_mission_index(p_key text, p_count integer)
returns integer
language plpgsql
immutable
as $fn$
declare
	acc bigint := 0;
	i integer;
begin
	if p_count is null or p_count <= 0 then
		return 0;
	end if;
	for i in 1..char_length(p_key) loop
		acc := mod(acc * 33 + ascii(substr(p_key, i, 1)), 1000003);
	end loop;
	return mod(acc, p_count)::integer;
end;
$fn$;

create or replace function public.reefrun_count_at_least(samples integer[], threshold integer)
returns integer
language sql
immutable
as $fn$
	select count(*)::integer
	from unnest(coalesce(samples, '{}'::integer[])) as v
	where v >= threshold;
$fn$;

create or replace function public.reefrun_window_sum(samples integer[], max_len integer)
returns integer
language plpgsql
immutable
as $fn$
declare
	best integer := 0;
	n integer;
	width integer;
	start_at integer;
	total integer;
begin
	n := coalesce(array_length(samples, 1), 0);
	if n = 0 or max_len is null or max_len <= 0 then
		return 0;
	end if;
	for width in 1..least(max_len, n) loop
		for start_at in 1..(n - width + 1) loop
			select coalesce(sum(v), 0) into total
			from unnest(samples[start_at:start_at + width - 1]) as v;
			if total > best then
				best := total;
			end if;
		end loop;
	end loop;
	return best;
end;
$fn$;

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
		else
			progress := 0;
	end case;
	return pg_catalog.jsonb_build_object(
		'progress', progress,
		'goal', target,
		'complete', target > 0 and progress >= target
	);
end;
$fn$;

create or replace function public.reefrun_pick_mission(
	p_day date,
	p_tier text,
	p_recent integer[],
	p_used_families text[]
) returns integer
language plpgsql
stable
as $fn$
declare
	ids integer[];
	families text[];
	fresh_ids integer[] := '{}';
	fresh_families text[] := '{}';
	pool_ids integer[];
	pool_families text[];
	pref_ids integer[] := '{}';
	i integer;
	n integer;
	idx integer;
begin
	select coalesce(array_agg(id order by id), '{}'),
		coalesce(array_agg(family order by id), '{}')
	into ids, families
	from public.mission_definitions
	where tier = p_tier and enabled;

	n := coalesce(array_length(ids, 1), 0);
	if n = 0 then
		return null;
	end if;

	for i in 1..n loop
		if not (ids[i] = any (coalesce(p_recent, '{}'::integer[]))) then
			fresh_ids := fresh_ids || ids[i];
			fresh_families := fresh_families || families[i];
		end if;
	end loop;

	if coalesce(array_length(fresh_ids, 1), 0) > 0 then
		pool_ids := fresh_ids;
		pool_families := fresh_families;
	else
		pool_ids := ids;
		pool_families := families;
	end if;

	n := array_length(pool_ids, 1);
	for i in 1..n loop
		if not (pool_families[i] = any (coalesce(p_used_families, '{}'::text[]))) then
			pref_ids := pref_ids || pool_ids[i];
		end if;
	end loop;

	if coalesce(array_length(pref_ids, 1), 0) > 0 then
		pool_ids := pref_ids;
	end if;

	n := array_length(pool_ids, 1);
	idx := public.reefrun_mission_index(p_day::text || '|' || p_tier, n);
	return pool_ids[idx + 1];
end;
$fn$;

create or replace function public.reefrun_ensure_daily_mission_set(p_day date)
returns public.daily_mission_sets
language plpgsql
security definer
set search_path = public
as $fn$
declare
	existing public.daily_mission_sets;
	recent integer[];
	used text[] := '{}';
	picked_easy integer;
	picked_medium integer;
	picked_hard integer;
	easy_family text;
	medium_family text;
begin
	perform pg_advisory_xact_lock(872341, hashtext(p_day::text));
	select * into existing
	from public.daily_mission_sets
	where mission_date = p_day;
	if found then
		return existing;
	end if;

	select coalesce(array_agg(mission_id), '{}')
	into recent
	from (
		select easy_id as mission_id
		from public.daily_mission_sets
		where mission_date >= p_day - 7 and mission_date < p_day
		union
		select medium_id
		from public.daily_mission_sets
		where mission_date >= p_day - 7 and mission_date < p_day
		union
		select hard_id
		from public.daily_mission_sets
		where mission_date >= p_day - 7 and mission_date < p_day
	) as past;

	picked_easy := public.reefrun_pick_mission(p_day, 'easy', recent, used);
	select family into easy_family
	from public.mission_definitions
	where id = picked_easy;
	used := array[easy_family];

	picked_medium := public.reefrun_pick_mission(p_day, 'medium', recent, used);
	select family into medium_family
	from public.mission_definitions
	where id = picked_medium;
	used := used || medium_family;

	picked_hard := public.reefrun_pick_mission(p_day, 'hard', recent, used);

	insert into public.daily_mission_sets (mission_date, easy_id, medium_id, hard_id)
	values (p_day, picked_easy, picked_medium, picked_hard)
	on conflict (mission_date) do nothing;

	select * into existing
	from public.daily_mission_sets
	where mission_date = p_day;
	return existing;
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
		p.gameplay_coins, p.coin_runs, p.run_pipes
	into pipes_total, runs_completed, best_pipes, best_seconds,
		gameplay_coins, coin_runs, run_pipes
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
			gameplay_coins, coin_runs, run_pipes
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

create or replace function public.get_daily_missions()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
	uid uuid := auth.uid();
begin
	if uid is null then
		return pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
	end if;
	return public.reefrun_daily_mission_board(uid);
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
declare
	uid uuid := auth.uid();
	today date := (timezone('utc', pg_catalog.now()))::date;
	board jsonb;
	wrote integer := 0;
begin
	-- Unlimited facts only. No daily attempt id and no leaderboard write.
	if uid is null then
		return pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
	end if;
	if p_run_id is null or p_run_id !~ '^[A-Za-z0-9_-]{8,80}$'
		or p_pipes is null or p_pipes < 0 or p_pipes > 80
		or p_seconds is null or p_seconds < 0 or p_seconds > 1800
		or p_gameplay_coins is null or p_gameplay_coins < 0
		or p_gameplay_coins > p_pipes / 5
		or (p_pipes > 0 and p_seconds < (p_pipes - 1))
		or (
			p_pipes < 80
			and p_seconds > floor(
				1.8::numeric
				+ p_pipes * 1.5
				+ 12
				+ 12 * (p_pipes / 20)
			)::integer
		)
	then
		return pg_catalog.jsonb_build_object('ok', false, 'reason', 'rejected', 'accepted', false);
	end if;

	perform pg_advisory_xact_lock(872342, hashtext(uid::text || today::text));
	insert into public.profiles (id, display_name) values (uid, 'YOU') on conflict (id) do nothing;
	perform 1 from public.profiles where id = uid for update;

	insert into public.daily_mission_run_log (
		player_id, run_id, mission_date, pipes, seconds, gameplay_coins
	) values (
		uid, p_run_id, today, p_pipes, p_seconds, p_gameplay_coins
	)
	on conflict (player_id, run_id) do nothing;
	get diagnostics wrote = row_count;
	if wrote = 0 then
		board := public.reefrun_daily_mission_board(uid);
		return board || pg_catalog.jsonb_build_object('reason', 'duplicate', 'accepted', false);
	end if;

	insert into public.daily_mission_progress (
		player_id, mission_date, pipes_total, runs_completed, best_pipes,
		best_seconds, gameplay_coins, coin_runs, run_pipes
	) values (
		uid, today, p_pipes, 1, p_pipes, p_seconds, p_gameplay_coins,
		case when p_gameplay_coins > 0 then 1 else 0 end,
		array[p_pipes]
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
		end;

	board := public.reefrun_daily_mission_board(uid);
	return board || pg_catalog.jsonb_build_object('reason', 'recorded', 'accepted', true);
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
		p.gameplay_coins, p.coin_runs, p.run_pipes
	into pipes_total, runs_completed, best_pipes, best_seconds,
		gameplay_coins, coin_runs, run_pipes
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
			gameplay_coins, coin_runs, run_pipes
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

revoke all on function public.reefrun_mission_index(text, integer) from public, anon, authenticated;
revoke all on function public.reefrun_count_at_least(integer[], integer) from public, anon, authenticated;
revoke all on function public.reefrun_window_sum(integer[], integer) from public, anon, authenticated;
revoke all on function public.reefrun_mission_snapshot(text, integer, integer, integer, integer, integer, integer, integer, integer, integer[]) from public, anon, authenticated;
revoke all on function public.reefrun_pick_mission(date, text, integer[], text[]) from public, anon, authenticated;
revoke all on function public.reefrun_ensure_daily_mission_set(date) from public, anon, authenticated;
revoke all on function public.reefrun_daily_mission_board(uuid) from public, anon, authenticated;
revoke all on function public.reefrun_daily_sets_immutable() from public, anon, authenticated;
revoke all on function public.reefrun_mission_claim_cap() from public, anon, authenticated;

revoke all on function public.get_daily_missions() from public, anon, authenticated;
revoke all on function public.record_unlimited_mission_run(text, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.claim_daily_mission(text) from public, anon, authenticated;

grant execute on function public.get_daily_missions() to authenticated;
grant execute on function public.record_unlimited_mission_run(text, integer, integer, integer) to authenticated;
grant execute on function public.claim_daily_mission(text) to authenticated;

notify pgrst, 'reload schema';
