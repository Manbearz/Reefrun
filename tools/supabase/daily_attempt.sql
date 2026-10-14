-- Reefrun daily attempt + score finalize.
-- Supabase Dashboard → SQL Editor → New query → paste this file → Run.
-- Rerun was reviewed statement by statement and was not executed on the live
-- database. Tables, columns, and the attempt unique constraint are created
-- only when missing. Functions use create or replace. The period check is
-- replaced only when its name is leaderboard_scores_period_check and it does
-- not already allow daily. A raised check aborts the script.
-- Does not drop tables or delete leaderboard rows.
-- submit_leaderboard_score keeps its signature. Its conflict target is moved
-- onto Unlimited rows so it cannot overwrite a Daily Challenge score.
-- Does not change leaderboard_scores grants or its select policy.
-- The Godot client uses the anon key only. Do not put the service_role key in the game.
-- coalesce, greatest, and extract are SQL syntax, not pg_catalog functions.
-- They are written without a schema prefix. Real pg_catalog functions stay qualified.
--
-- ANONYMOUS AUTH
-- Supabase anonymous sign-in returns a user JWT whose role is "authenticated".
-- The anon key is only the apikey header. PostgREST runs the request as
-- authenticated, so every RPC the game calls is granted to authenticated.
-- Existing EXECUTE grants on get_leaderboard are left in place. This script
-- only adds EXECUTE for authenticated if it is missing.
--
-- ONE ATTEMPT
-- claim_daily_attempt inserts one row per auth.uid() + today's Eastern challenge.
-- UNIQUE (player_id, challenge_id) makes a second insert from another tap,
-- retry, or device a no-op. The same idempotency key returns that row only
-- while started_at is null, so a lost claim response can be recovered before
-- gameplay. start_daily_attempt sets started_at once. After that, the same
-- key is already_used and does not open another swim. A crash after start
-- keeps the row until midnight America/New_York.
-- Opening the mode screen calls get_daily_attempt_status, which does not insert.
--
-- SCORES
-- finalize_daily_attempt writes the first score onto that attempt. A second
-- call returns the stored score and does not write again. A positive score is
-- upserted into the Daily leaderboard only. Weekly and Monthly are Unlimited
-- scores written by submit_leaderboard_score. Daily rows and Unlimited rows
-- use separate partial unique indexes. Display names are trimmed to 7
-- characters, matching GameSession.NAME_MAX_LEN.
-- finalize_daily_attempt rejects a row whose started_at is null.
-- The player id and the challenge date come from the stored attempt, not from
-- the client. Server now() chooses the challenge at claim time.
--
-- LEADERBOARD
-- get_leaderboard reads leaderboard_scores and returns the current UTC day,
-- week (Monday, same as date_trunc('week')), or month. Daily returns rows
-- with a challenge_id. Weekly and Monthly return rows without one.
-- Historical rows stay in the table.
--
-- SEED
-- reefrun_daily_seed uses the same FNV-1a 32-bit steps as
-- DailyChallenge.derive_seed. reefrun_daily_seed('2026-10-12', 1) = 750528330.
--
-- TODAY
-- This script does not insert a daily_attempts row, does not mark today's
-- challenge completed, and does not copy historical leaderboard_scores into
-- the daily period.

create extension if not exists "pgcrypto";

create table if not exists public.daily_challenges (
	challenge_id text primary key,
	challenge_date date not null,
	course_seed bigint not null,
	course_version integer not null,
	physics_version integer not null,
	created_at timestamptz not null default now()
);

alter table public.leaderboard_scores
	add column if not exists challenge_id text;

-- Separate Daily Challenge rows from Unlimited rows without deleting either.
-- The old unique index on (player_id, period, period_key) can hold only one
-- row, so a historical Unlimited score blocked a Daily score. That index is
-- dropped only when it has no WHERE clause and exactly those three columns.
-- Partial indexes then keep one Unlimited row and one Daily row per bucket.
-- Duplicate rows stop the script. No score row is deleted.
do $$
declare
	r record;
	v_cols text[];
begin
	if exists (
		select 1
		from public.leaderboard_scores
		where challenge_id is null
		group by player_id, period, period_key
		having count(*) > 1
	) or exists (
		select 1
		from public.leaderboard_scores
		where challenge_id is not null
		group by player_id, period, period_key
		having count(*) > 1
	) then
		raise exception 'leaderboard_scores has duplicate rows inside Daily or Unlimited buckets. No rows were deleted.';
	end if;

	for r in
		select
			ix.relname as index_name,
			ixn.nspname as index_schema,
			i.indrelid,
			i.indkey,
			con.conname as constraint_name
		from pg_catalog.pg_index as i
		join pg_catalog.pg_class as t on t.oid = i.indrelid
		join pg_catalog.pg_class as ix on ix.oid = i.indexrelid
		join pg_catalog.pg_namespace as n on n.oid = t.relnamespace
		join pg_catalog.pg_namespace as ixn on ixn.oid = ix.relnamespace
		left join pg_catalog.pg_constraint as con
			on con.conindid = i.indexrelid
			and con.contype = 'u'
		where n.nspname = 'public'
			and t.relname = 'leaderboard_scores'
			and i.indisunique
			and i.indisvalid
			and i.indpred is null
	loop
		select pg_catalog.array_agg(a.attname::text order by k.ord)
		into v_cols
		from pg_catalog.unnest(r.indkey::smallint[]) with ordinality as k(attnum, ord)
		join pg_catalog.pg_attribute as a
			on a.attrelid = r.indrelid
			and a.attnum = k.attnum
		where k.attnum > 0;

		if v_cols is null
			or pg_catalog.array_length(v_cols, 1) is distinct from 3
			or not (
				v_cols @> array['player_id', 'period', 'period_key']::text[]
				and array['player_id', 'period', 'period_key']::text[] @> v_cols
			) then
			continue;
		end if;

		if r.constraint_name is not null then
			execute format(
				'alter table public.leaderboard_scores drop constraint %I',
				r.constraint_name
			);
		else
			execute format('drop index %I.%I', r.index_schema, r.index_name);
		end if;
	end loop;
end $$;

create unique index if not exists leaderboard_scores_daily_period
	on public.leaderboard_scores (player_id, period, period_key)
	where challenge_id is not null;

create unique index if not exists leaderboard_scores_unlimited_period
	on public.leaderboard_scores (player_id, period, period_key)
	where challenge_id is null;

-- Same 32-bit FNV-1a as DailyChallenge._fnv1a32:
--   hash = 2166136261
--   for each UTF-8 byte: hash = (hash xor byte) mod 2^32
--                        hash = (hash * 16777619) mod 2^32
--   hash = hash mod 2^31; if hash = 0 then 1
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

do $$
begin
	if public.reefrun_daily_seed('2026-10-12', 1) <> 750528330 then
		raise exception 'reefrun_daily_seed does not match DailyChallenge.derive_seed for 2026-10-12 course version 1';
	end if;
end $$;

-- schema.sql and leaderboard.sql name this check leaderboard_scores_period_check
-- on column period. Replace that constraint only when it still lists weekly and
-- monthly without daily. Any other check is reported and left in place.
do $$
declare
	v_def text;
	v_cols text;
	v_others text;
begin
	select pg_catalog.pg_get_constraintdef(c.oid),
		(
			select pg_catalog.string_agg(a.attname, ',' order by a.attnum)
			from pg_catalog.pg_attribute as a
			where a.attrelid = c.conrelid
				and a.attnum = any (c.conkey)
		)
	into v_def, v_cols
	from pg_catalog.pg_constraint as c
	where c.conrelid = 'public.leaderboard_scores'::regclass
		and c.contype = 'c'
		and c.conname = 'leaderboard_scores_period_check';

	if v_def is null then
		select pg_catalog.string_agg(c.conname || ': ' || pg_catalog.pg_get_constraintdef(c.oid), '; ')
		into v_others
		from pg_catalog.pg_constraint as c
		where c.conrelid = 'public.leaderboard_scores'::regclass
			and c.contype = 'c'
			and pg_catalog.pg_get_constraintdef(c.oid) ilike '%period%';
		if v_others is not null then
			raise exception 'Refusing to drop an unnamed period check. Found: %', v_others;
		end if;
		alter table public.leaderboard_scores
			add constraint leaderboard_scores_period_check
			check (period in ('daily', 'weekly', 'monthly'));
		return;
	end if;

	if v_cols is distinct from 'period' then
		raise exception 'leaderboard_scores_period_check is not limited to column period (columns: %). It was not changed. Definition: %', v_cols, v_def;
	end if;

	if pg_catalog.strpos(v_def, 'daily') > 0
		and pg_catalog.strpos(v_def, 'weekly') > 0
		and pg_catalog.strpos(v_def, 'monthly') > 0 then
		return;
	end if;

	if pg_catalog.strpos(v_def, 'weekly') > 0
		and pg_catalog.strpos(v_def, 'monthly') > 0
		and pg_catalog.strpos(v_def, 'daily') = 0
		and pg_catalog.strpos(v_def, 'period') > 0 then
		alter table public.leaderboard_scores drop constraint leaderboard_scores_period_check;
		alter table public.leaderboard_scores
			add constraint leaderboard_scores_period_check
			check (period in ('daily', 'weekly', 'monthly'));
		return;
	end if;

	raise exception 'Refusing to change leaderboard_scores_period_check. Definition: %', v_def;
end $$;

create table if not exists public.daily_attempts (
	id uuid primary key default gen_random_uuid(),
	player_id uuid not null references public.profiles (id) on delete cascade,
	challenge_id text not null references public.daily_challenges (challenge_id),
	idempotency_key uuid not null,
	score integer,
	finalized_at timestamptz,
	started_at timestamptz,
	claimed_at timestamptz not null default now()
);

alter table public.daily_attempts
	add column if not exists started_at timestamptz;

do $$
begin
	if not exists (
		select 1
		from pg_catalog.pg_constraint
		where conname = 'daily_attempts_player_challenge'
			and conrelid = 'public.daily_attempts'::regclass
	) then
		alter table public.daily_attempts
			add constraint daily_attempts_player_challenge unique (player_id, challenge_id);
	end if;
end $$;

alter table public.daily_attempts enable row level security;
revoke all on table public.daily_attempts from public, anon, authenticated;

alter table public.daily_challenges enable row level security;
drop policy if exists daily_challenges_select on public.daily_challenges;
create policy daily_challenges_select on public.daily_challenges
	for select to authenticated using (true);
grant select on table public.daily_challenges to authenticated;

-- Publishes today's America/New_York challenge. Does not insert a player attempt.
-- The day rolls at midnight Eastern, including daylight saving.
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
as $$
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
$$;

revoke all on function public.reefrun_publish_today() from public, anon;

-- Godot posts {} to /rest/v1/rpc/get_daily_challenge. No arguments.
-- Publishes today's challenge row and does not insert a player attempt.
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
begin
	if auth.uid() is null then
		raise exception 'not authenticated';
	end if;
	return query
	select
		p.challenge_id,
		p.challenge_date,
		p.course_seed,
		p.course_version,
		p.physics_version,
		p.as_of
	from public.reefrun_publish_today() as p;
end;
$$;

create or replace function public.get_daily_attempt_status(p_idempotency_key uuid default null)
returns table (
	challenge_id text,
	challenge_date date,
	course_seed bigint,
	course_version integer,
	physics_version integer,
	as_of timestamptz,
	as_of_unix bigint,
	resets_at timestamptz,
	resets_unix bigint,
	attempted boolean,
	recoverable boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
	uid uuid := auth.uid();
	v_challenge_id text;
	v_exists boolean := false;
	v_recoverable boolean := false;
begin
	if uid is null then
		raise exception 'not authenticated';
	end if;
	select p.challenge_id
	into v_challenge_id
	from public.reefrun_publish_today() as p
	limit 1;
	v_exists := exists (
		select 1
		from public.daily_attempts as a
		where a.player_id = uid
			and a.challenge_id = v_challenge_id
	);
	-- Same key, swim not started and not finalized: the client may enter this claim.
	-- A started row, a finalized row, or a different key is a completed attempt.
	v_recoverable := p_idempotency_key is not null and exists (
		select 1
		from public.daily_attempts as a
		where a.player_id = uid
			and a.challenge_id = v_challenge_id
			and a.idempotency_key = p_idempotency_key
			and a.started_at is null
			and a.finalized_at is null
	);
	return query
	select
		p.challenge_id,
		p.challenge_date,
		p.course_seed,
		p.course_version,
		p.physics_version,
		p.as_of,
		p.as_of_unix,
		p.resets_at,
		p.resets_unix,
		v_exists and not v_recoverable,
		v_recoverable
	from public.reefrun_publish_today() as p
	limit 1;
end;
$$;

create or replace function public.claim_daily_attempt(p_idempotency_key uuid)
returns table (
	attempt_id uuid,
	challenge_id text,
	challenge_date date,
	course_seed bigint,
	course_version integer,
	physics_version integer,
	as_of timestamptz,
	as_of_unix bigint,
	resets_at timestamptz,
	resets_unix bigint,
	claimed boolean,
	already_used boolean,
	idempotent_replay boolean,
	finalized boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
	uid uuid := auth.uid();
	v_challenge_id text;
	v_new_id uuid;
	v_existing_id uuid;
	v_existing_key uuid;
	v_finalized boolean := false;
	v_started boolean := false;
	v_owned boolean := false;
	v_replay boolean := false;
begin
	if uid is null then
		raise exception 'not authenticated';
	end if;
	if p_idempotency_key is null then
		raise exception 'missing idempotency key';
	end if;
	select p.challenge_id
	into v_challenge_id
	from public.reefrun_publish_today() as p
	limit 1;
	if v_challenge_id is null then
		raise exception 'challenge unavailable';
	end if;

	insert into public.profiles (id, display_name)
	values (uid, 'YOU')
	on conflict (id) do nothing;

	with inserted as (
		insert into public.daily_attempts as d (player_id, challenge_id, idempotency_key)
		values (uid, v_challenge_id, p_idempotency_key)
		on conflict on constraint daily_attempts_player_challenge do nothing
		returning id
	)
	select inserted.id into v_new_id from inserted;

	if v_new_id is not null then
		v_owned := true;
	else
		select a.id, a.idempotency_key, a.finalized_at is not null, a.started_at is not null
		into v_existing_id, v_existing_key, v_finalized, v_started
		from public.daily_attempts as a
		where a.player_id = uid
			and a.challenge_id = v_challenge_id;
		if v_existing_id is null then
			raise exception 'attempt conflict';
		end if;
		v_replay := v_existing_key = p_idempotency_key;
		-- Recovery is only the unstarted claim. A started swim stays consumed.
		v_owned := v_replay and not v_started and not v_finalized;
		v_new_id := v_existing_id;
	end if;

	return query
	select
		case when v_owned then v_new_id else null end,
		p.challenge_id,
		p.challenge_date,
		p.course_seed,
		p.course_version,
		p.physics_version,
		p.as_of,
		p.as_of_unix,
		p.resets_at,
		p.resets_unix,
		v_owned,
		not v_owned,
		v_replay,
		v_finalized
	from public.reefrun_publish_today() as p
	limit 1;
end;
$$;

-- Marks the claimed row as started. The first call returns started = true.
-- A repeat returns already_started. Godot enters the run on that repeat only
-- when the previous request in the same call received no response. A later
-- call, after started_at is set, does not open a second run.
create or replace function public.start_daily_attempt(p_attempt_id uuid)
returns table (
	attempt_id uuid,
	started boolean,
	already_started boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
	uid uuid := auth.uid();
	v_started timestamptz;
	v_finalized timestamptz;
begin
	if uid is null then
		raise exception 'not authenticated';
	end if;
	if p_attempt_id is null then
		raise exception 'missing attempt';
	end if;

	select a.started_at, a.finalized_at
	into v_started, v_finalized
	from public.daily_attempts as a
	where a.id = p_attempt_id
		and a.player_id = uid
	for update;

	if not found then
		raise exception 'attempt not found';
	end if;

	if v_started is not null or v_finalized is not null then
		return query
		select p_attempt_id, false, true;
		return;
	end if;

	update public.daily_attempts
	set started_at = pg_catalog.now()
	where id = p_attempt_id
		and player_id = uid
		and started_at is null
		and finalized_at is null;

	if not found then
		return query
		select p_attempt_id, false, true;
		return;
	end if;

	return query
	select p_attempt_id, true, false;
end;
$$;

create or replace function public.finalize_daily_attempt(
	p_attempt_id uuid,
	p_score integer,
	p_display_name text
)
returns table (
	attempt_id uuid,
	score integer,
	accepted boolean,
	duplicate boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
	uid uuid := auth.uid();
	v_challenge_id text;
	v_day date;
	v_existing_score integer;
	v_finalized timestamptz;
	v_started timestamptz;
	clean_name text;
	day_key text;
begin
	if uid is null then
		raise exception 'not authenticated';
	end if;
	if p_attempt_id is null then
		raise exception 'missing attempt';
	end if;
	if p_score is null or p_score < 0 then
		raise exception 'invalid score';
	end if;

	select a.challenge_id, a.score, a.finalized_at, a.started_at
	into v_challenge_id, v_existing_score, v_finalized, v_started
	from public.daily_attempts as a
	where a.id = p_attempt_id
		and a.player_id = uid
	for update;

	if v_challenge_id is null then
		raise exception 'attempt not found';
	end if;

	if v_finalized is null and v_started is null then
		raise exception 'attempt not started';
	end if;

	select c.challenge_date
	into v_day
	from public.daily_challenges as c
	where c.challenge_id = v_challenge_id;

	if v_day is null then
		raise exception 'challenge missing';
	end if;

	if v_finalized is not null then
		return query
		select p_attempt_id, coalesce(v_existing_score, 0), false, true;
		return;
	end if;

	update public.daily_attempts
	set score = p_score,
		finalized_at = pg_catalog.now()
	where id = p_attempt_id
		and player_id = uid
		and started_at is not null
		and finalized_at is null;

	if not found then
		select a.score
		into v_existing_score
		from public.daily_attempts as a
		where a.id = p_attempt_id
			and a.player_id = uid;
		return query
		select p_attempt_id, coalesce(v_existing_score, 0), false, true;
		return;
	end if;

	if p_score <= 0 then
		return query
		select p_attempt_id, p_score, true, false;
		return;
	end if;

	insert into public.profiles (id, display_name)
	values (uid, 'YOU')
	on conflict (id) do nothing;

	clean_name := pg_catalog.left(pg_catalog.btrim(coalesce(p_display_name, '')), 7);
	if clean_name = '' then
		clean_name := 'YOU';
	end if;

	day_key := pg_catalog.to_char(v_day, 'YYYY-MM-DD');
	insert into public.leaderboard_scores (player_id, display_name, score, period, period_key, challenge_id)
	values (uid, clean_name, p_score, 'daily', day_key, v_challenge_id)
	on conflict (player_id, period, period_key) where challenge_id is not null
	do update set
		display_name = excluded.display_name,
		challenge_id = excluded.challenge_id,
		score = greatest(public.leaderboard_scores.score, excluded.score)
	where excluded.score > public.leaderboard_scores.score;

	return query
	select p_attempt_id, p_score, true, false;
end;
$$;

revoke all on function public.get_daily_challenge() from public, anon;
revoke all on function public.get_daily_attempt_status(uuid) from public, anon;
revoke all on function public.claim_daily_attempt(uuid) from public, anon;
revoke all on function public.start_daily_attempt(uuid) from public, anon;
revoke all on function public.finalize_daily_attempt(uuid, integer, text) from public, anon;
grant execute on function public.get_daily_challenge() to authenticated;
grant execute on function public.get_daily_attempt_status(uuid) to authenticated;
grant execute on function public.claim_daily_attempt(uuid) to authenticated;
grant execute on function public.start_daily_attempt(uuid) to authenticated;
grant execute on function public.finalize_daily_attempt(uuid, integer, text) to authenticated;

-- submit_leaderboard_score writes Unlimited Weekly and Monthly rows
-- (challenge_id null). It does not write the Daily board. Its conflict
-- target is the Unlimited partial index, so it cannot replace a Daily
-- Challenge row. CREATE OR REPLACE keeps its existing EXECUTE grants.
-- The signature stays (integer, text).
create or replace function public.submit_leaderboard_score(p_score integer, p_display_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	uid uuid := auth.uid();
	clean_name text;
	week_key text;
	month_key text;
begin
	if uid is null then
		raise exception 'not authenticated';
	end if;
	if p_score is null or p_score <= 0 then
		return;
	end if;

	insert into public.profiles (id, display_name)
	values (uid, 'YOU')
	on conflict (id) do nothing;

	clean_name := pg_catalog.left(pg_catalog.btrim(coalesce(p_display_name, '')), 7);
	if clean_name = '' then
		clean_name := 'YOU';
	end if;

	week_key := pg_catalog.to_char(pg_catalog.date_trunc('week', pg_catalog.timezone('utc', pg_catalog.now())), 'YYYY-MM-DD');
	month_key := pg_catalog.to_char(pg_catalog.timezone('utc', pg_catalog.now()), 'YYYY-MM');

	insert into public.leaderboard_scores (player_id, display_name, score, period, period_key)
	values (uid, clean_name, p_score, 'weekly', week_key)
	on conflict (player_id, period, period_key) where challenge_id is null
	do update set
		display_name = excluded.display_name,
		score = greatest(public.leaderboard_scores.score, excluded.score);
	insert into public.leaderboard_scores (player_id, display_name, score, period, period_key)
	values (uid, clean_name, p_score, 'monthly', month_key)
	on conflict (player_id, period, period_key) where challenge_id is null
	do update set
		display_name = excluded.display_name,
		score = greatest(public.leaderboard_scores.score, excluded.score);
end;
$$;

grant execute on function public.submit_leaderboard_score(integer, text) to authenticated;

-- CREATE OR REPLACE keeps the current EXECUTE grants on get_leaderboard.
-- authenticated is granted so an anonymous-auth session can read the board.
create or replace function public.get_leaderboard(p_period text)
returns table (display_name text, score integer)
language sql
stable
security definer
set search_path = ''
as $$
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
$$;

grant execute on function public.get_leaderboard(text) to authenticated;

notify pgrst, 'reload schema';
