-- Reefrun daily challenge. Run in Supabase → SQL Editor → New query → Run.
-- Safe to run more than once. Does not drop tables or delete leaderboard rows.
-- Requires the existing Reefrun tables (profiles, ghost_runs, leaderboard_scores).
-- Client keeps using the anon key only. Do not put the service_role key in Godot.
-- reefrun_daily_seed('2026-10-12', 1) must return 750528330. That pins the
-- FNV-1a function to the Godot client.
--
-- HISTORICAL WEEKLY / MONTHLY ROWS
-- Existing leaderboard_scores rows are left in place. Their period_key format
-- does not change:
--   daily   YYYY-MM-DD
--   weekly  Monday of that ISO week, YYYY-MM-DD (same as date_trunc('week'))
--   monthly YYYY-MM
-- Those rows still mean "best score already stored for that bucket". Nothing
-- is rekeyed, recomputed, or deleted.
--
-- NEW SUBMISSIONS
-- submit_leaderboard_score(integer, text) is unchanged and still buckets by
-- the server clock at insert time. The game calls submit_challenge_score
-- instead. That RPC buckets by the challenge's Eastern date, which the server
-- checks against now(). A run that is still inside the 20-minute grace after
-- midnight Eastern stays on its original day, week, and month. A normal same-day
-- submit lands in the same buckets the old RPC would have used, and greatest()
-- keeps the better score. A shared course seed is not treated as anti-cheat.

create extension if not exists "pgcrypto";

create table if not exists public.daily_challenges (
	challenge_id text primary key,
	challenge_date date not null,
	course_seed bigint not null,
	course_version integer not null,
	physics_version integer not null,
	created_at timestamptz not null default now()
);

alter table public.ghost_runs
	add column if not exists challenge_id text;

alter table public.leaderboard_scores
	add column if not exists challenge_id text;

create index if not exists ghost_runs_challenge_lookup
	on public.ghost_runs (challenge_id, course_version, physics_version, created_at desc);

create unique index if not exists leaderboard_scores_player_period
	on public.leaderboard_scores (player_id, period, period_key);

-- 32-bit FNV-1a, masked to a positive 31-bit seed. Must match DailyChallenge.derive_seed.
create or replace function public.reefrun_daily_seed(p_date text, p_course_version integer)
returns bigint
language plpgsql
immutable
set search_path = ''
as $$
declare
	payload text := 'reefrun.daily.v1|' || p_date || '|cv' || p_course_version::text;
	raw bytea := pg_catalog.convert_to(payload, 'UTF8');
	h bigint := 2166136261;
	i integer;
	b integer;
begin
	for i in 0..pg_catalog.octet_length(raw) - 1 loop
		b := pg_catalog.get_byte(raw, i);
		h := (h # b) & 4294967295;
		h := (h * 16777619) & 4294967295;
	end loop;
	h := h & 2147483647;
	if h = 0 then
		h := 1;
	end if;
	return h;
end;
$$;

revoke all on function public.reefrun_daily_seed(text, integer) from public, anon, authenticated;

create or replace function public.get_daily_challenge()
returns table (
	challenge_id text,
	challenge_date date,
	course_seed bigint,
	course_version integer,
	physics_version integer,
	as_of timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
	-- Keep these equal to RR.COURSE_VERSION and RR.PHYSICS_VERSION.
	v_cv integer := 1;
	v_pv integer := 1;
	v_day date := (pg_catalog.timezone('America/New_York', pg_catalog.now()))::date;
	v_date text;
	v_id text;
	v_seed bigint;
begin
	if auth.uid() is null then
		raise exception 'not authenticated';
	end if;
	v_date := pg_catalog.to_char(v_day, 'YYYY-MM-DD');
	v_id := 'daily:' || v_date || ':cv' || v_cv::text || ':pv' || v_pv::text;
	v_seed := public.reefrun_daily_seed(v_date, v_cv);
	insert into public.daily_challenges as c (challenge_id, challenge_date, course_seed, course_version, physics_version)
	values (v_id, v_day, v_seed, v_cv, v_pv)
	on conflict on constraint daily_challenges_pkey do nothing;
	return query
	select c.challenge_id, c.challenge_date, c.course_seed, c.course_version, c.physics_version, pg_catalog.now()
	from public.daily_challenges as c
	where c.challenge_id = v_id;
end;
$$;

create or replace function public.submit_challenge_score(p_challenge_id text, p_score integer, p_display_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	uid uuid := auth.uid();
	v_cv integer := 1;
	v_pv integer := 1;
	v_match text[];
	v_date text;
	v_day date;
	v_id text;
	v_seed bigint;
	clean_name text;
	day_key text;
	week_key text;
	month_key text;
	starts_at timestamptz;
begin
	if uid is null then
		raise exception 'not authenticated';
	end if;
	if p_score is null or p_score <= 0 or p_challenge_id is null then
		return;
	end if;
	v_match := pg_catalog.regexp_match(p_challenge_id, '^daily:([0-9]{4}-[0-9]{2}-[0-9]{2}):cv([0-9]+):pv([0-9]+)$');
	if v_match is null then
		return;
	end if;
	v_date := v_match[1];
	begin
		v_day := v_date::date;
	exception
		when others then
			return;
	end;
	if pg_catalog.to_char(v_day, 'YYYY-MM-DD') <> v_date then
		return;
	end if;
	if v_match[2]::integer <> v_cv or v_match[3]::integer <> v_pv then
		return;
	end if;
	v_id := 'daily:' || v_date || ':cv' || v_cv::text || ':pv' || v_pv::text;
	if p_challenge_id <> v_id then
		return;
	end if;
	v_seed := public.reefrun_daily_seed(v_date, v_cv);
	starts_at := v_day::timestamp at time zone 'America/New_York';
	-- Original challenge day, plus 20 minutes after the next Eastern midnight.
	-- Server now() is the authority. The client clock is ignored.
	if pg_catalog.now() < starts_at or pg_catalog.now() >= ((v_day + 1)::timestamp at time zone 'America/New_York') + interval '20 minutes' then
		return;
	end if;

	insert into public.profiles (id, display_name)
	values (uid, 'YOU')
	on conflict (id) do nothing;

	clean_name := pg_catalog.left(pg_catalog.btrim(pg_catalog.coalesce(p_display_name, '')), 14);
	if clean_name = '' then
		clean_name := 'YOU';
	end if;

	day_key := pg_catalog.to_char(v_day, 'YYYY-MM-DD');
	week_key := pg_catalog.to_char(pg_catalog.date_trunc('week', v_day::timestamp), 'YYYY-MM-DD');
	month_key := pg_catalog.to_char(v_day, 'YYYY-MM');

	insert into public.daily_challenges as c (challenge_id, challenge_date, course_seed, course_version, physics_version)
	values (v_id, v_day, v_seed, v_cv, v_pv)
	on conflict (challenge_id) do nothing;

	insert into public.leaderboard_scores (player_id, display_name, score, period, period_key, challenge_id)
	values (uid, clean_name, p_score, 'daily', day_key, v_id)
	on conflict (player_id, period, period_key)
	do update set
		display_name = excluded.display_name,
		challenge_id = case
			when excluded.score > public.leaderboard_scores.score then excluded.challenge_id
			else public.leaderboard_scores.challenge_id
		end,
		score = pg_catalog.greatest(public.leaderboard_scores.score, excluded.score);

	insert into public.leaderboard_scores (player_id, display_name, score, period, period_key, challenge_id)
	values (uid, clean_name, p_score, 'weekly', week_key, v_id)
	on conflict (player_id, period, period_key)
	do update set
		display_name = excluded.display_name,
		challenge_id = case
			when excluded.score > public.leaderboard_scores.score then excluded.challenge_id
			else public.leaderboard_scores.challenge_id
		end,
		score = pg_catalog.greatest(public.leaderboard_scores.score, excluded.score);

	insert into public.leaderboard_scores (player_id, display_name, score, period, period_key, challenge_id)
	values (uid, clean_name, p_score, 'monthly', month_key, v_id)
	on conflict (player_id, period, period_key)
	do update set
		display_name = excluded.display_name,
		challenge_id = case
			when excluded.score > public.leaderboard_scores.score then excluded.challenge_id
			else public.leaderboard_scores.challenge_id
		end,
		score = pg_catalog.greatest(public.leaderboard_scores.score, excluded.score);
end;
$$;

-- Visible boards stay "best score in the bucket that contains server today".
-- Reaffirmed here so a database that ran leaderboard_name_fix.sql still returns daily.
create or replace function public.get_leaderboard(p_period text)
returns table (display_name text, score integer)
language sql
stable
security definer
set search_path = ''
as $$
	select ls.display_name::text as display_name, ls.score::integer as score
	from public.leaderboard_scores as ls
	where ls.period = p_period
		and ls.period_key = case
			when p_period = 'daily' then pg_catalog.to_char(pg_catalog.timezone('America/New_York', pg_catalog.now()), 'YYYY-MM-DD')
			when p_period = 'weekly' then pg_catalog.to_char(pg_catalog.date_trunc('week', pg_catalog.timezone('utc', pg_catalog.now())), 'YYYY-MM-DD')
			when p_period = 'monthly' then pg_catalog.to_char(pg_catalog.timezone('utc', pg_catalog.now()), 'YYYY-MM')
			else ''
		end
	order by ls.score desc, ls.created_at asc
	limit 10;
$$;

alter table public.daily_challenges enable row level security;

drop policy if exists daily_challenges_select on public.daily_challenges;
create policy daily_challenges_select on public.daily_challenges
	for select to authenticated using (true);

revoke all on table public.daily_challenges from public, anon, authenticated;
grant select on table public.daily_challenges to authenticated;

revoke all on function public.get_daily_challenge() from public, anon, authenticated;
revoke all on function public.submit_challenge_score(text, integer, text) from public, anon, authenticated;
revoke all on function public.get_leaderboard(text) from public, anon, authenticated;
grant execute on function public.get_daily_challenge() to authenticated;
grant execute on function public.submit_challenge_score(text, integer, text) to authenticated;
grant execute on function public.get_leaderboard(text) to authenticated;

notify pgrst, 'reload schema';
