-- Fix Daily Challenge startup: Postgres 42702 ambiguous challenge_id.
-- Supabase Dashboard → SQL Editor → New query → paste this file → Run.
-- Review before running. This file has not been executed.
--
-- RETURNS TABLE output names are PL/pgSQL variables. ON CONFLICT (challenge_id)
-- is an unqualified column reference, so it matches both that variable and the
-- table column. These two functions name the unique constraint instead.
-- Table reads stay qualified (c.challenge_id, a.challenge_id, p.challenge_id).
-- The course id used inside the function is v_challenge_id, not challenge_id.
--
-- Signatures, return column names, and the one-attempt rule stay the same.
-- Does not delete rows, reset scores, or replace leaderboard functions.
-- The challenge date and reset match the daily leaderboard: UTC calendar day,
-- rolling at the next 00:00 UTC. Weekly and monthly boards are not changed.
-- A failed claim from this error rolled back, so it did not use today's attempt.

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
	v_day date := (pg_catalog.timezone('utc', pg_catalog.now()))::date;
	v_date text;
	v_id text;
	v_seed bigint;
	v_resets timestamptz;
begin
	v_date := pg_catalog.to_char(v_day, 'YYYY-MM-DD');
	v_id := 'daily:' || v_date || ':cv' || v_cv::text || ':pv' || v_pv::text;
	v_seed := public.reefrun_daily_seed(v_date, v_cv);
	v_resets := (v_day + 1)::timestamp at time zone 'utc';
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
