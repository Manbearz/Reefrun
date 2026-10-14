-- Move the daily challenge reset from midnight UTC to midnight America/New_York.
-- Supabase Dashboard → SQL Editor → New query → paste this file → Run.
-- Safe to run more than once. Does not drop tables or delete rows.
-- Weekly and monthly boards stay on UTC.
--
-- reefrun_publish_today chooses the course and the "resets at" timestamp.
-- get_daily_challenge, get_daily_attempt_status, and claim_daily_attempt
-- all read that row. get_leaderboard shows the daily board for the same date.

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

grant execute on function public.get_daily_challenge() to authenticated;

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
