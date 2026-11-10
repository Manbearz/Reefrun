-- ReefRun: three Daily Challenge attempts, best score kept.
-- Do not run this until it has been reviewed. It does not delete rows.
--
-- WHAT CHANGES
-- A player may start three separate runs on the same Eastern-day seed.
-- Starting a run sets started_at and consumes one attempt. Dying, leaving,
-- or retrying the same attempt does not consume another. The fourth start
-- is rejected. finalize_daily_attempt still writes one daily leaderboard
-- row and keeps the higher score.
--
-- EXISTING ROWS
-- A player who already has one started row for today keeps that row.
-- attempts_used counts rows with started_at set, so they have two starts
-- left today. An unstarted row is not consumed. A new claim reuses it.
-- No score is rewritten by this script.
--
-- OLDER TESTFLIGHT BUILDS
-- Those builds lock the day when get_daily_attempt_status returns
-- attempted = true. This script still sets attempted after the first
-- start, so an old build stops at one run. It cannot start a second.
-- The new columns are extra JSON fields. Old builds ignore them.
-- Ship this SQL before the Godot client that reads attempts_remaining.
-- Until this SQL is applied, that client treats a missing
-- attempts_remaining as the old one-attempt rule.
--
-- A RUN THAT CROSSES MIDNIGHT
-- The attempt stores the challenge it was claimed on. Finalize writes the
-- daily board for that challenge date, not for now(). The swim is not
-- aborted. The new Eastern day is a new challenge with three fresh starts.
--
-- ROLLBACK
-- Safe only before any player has two rows for the same challenge.
-- 1. Stop the new client.
-- 2. Re-create the functions from tools/supabase/daily_attempt.sql.
-- 3. Restore unique (player_id, challenge_id) only when this returns zero:
--      select player_id, challenge_id, count(*)
--      from public.daily_attempts
--      group by 1, 2
--      having count(*) > 1;
-- Do not delete attempt rows or leaderboard rows to force that constraint.
-- If any player already has two rows, leave these functions in place.

begin;

create or replace function public.reefrun_limit_daily_attempts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
	v_count integer;
begin
	select count(*)
	into v_count
	from public.daily_attempts
	where player_id = new.player_id
		and challenge_id = new.challenge_id
		and id is distinct from new.id;
	if v_count >= 3 then
		raise exception 'daily attempt limit';
	end if;
	return new;
end;
$$;

drop trigger if exists daily_attempts_limit on public.daily_attempts;
create trigger daily_attempts_limit
	before insert on public.daily_attempts
	for each row
	execute function public.reefrun_limit_daily_attempts();

do $$
begin
	if exists (
		select 1
		from pg_catalog.pg_constraint
		where conname = 'daily_attempts_player_challenge'
			and conrelid = 'public.daily_attempts'::regclass
	) then
		alter table public.daily_attempts
			drop constraint daily_attempts_player_challenge;
	end if;
	if not exists (
		select 1
		from pg_catalog.pg_constraint
		where conname = 'daily_attempts_player_key'
			and conrelid = 'public.daily_attempts'::regclass
	) then
		alter table public.daily_attempts
			add constraint daily_attempts_player_key
			unique (player_id, challenge_id, idempotency_key);
	end if;
end $$;

drop function if exists public.get_daily_attempt_status(uuid);
create function public.get_daily_attempt_status(p_idempotency_key uuid default null)
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
	recoverable boolean,
	attempts_used integer,
	attempts_remaining integer,
	best_score integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
	uid uuid := auth.uid();
	v_challenge_id text;
	v_day date;
	v_used integer := 0;
	v_recoverable boolean := false;
	v_best integer := 0;
begin
	if uid is null then
		raise exception 'not authenticated';
	end if;
	select p.challenge_id, p.challenge_date
	into v_challenge_id, v_day
	from public.reefrun_publish_today() as p
	limit 1;
	select count(*)
	into v_used
	from public.daily_attempts as a
	where a.player_id = uid
		and a.challenge_id = v_challenge_id
		and a.started_at is not null;
	v_recoverable := p_idempotency_key is not null and exists (
		select 1
		from public.daily_attempts as a
		where a.player_id = uid
			and a.challenge_id = v_challenge_id
			and a.idempotency_key = p_idempotency_key
			and a.started_at is null
			and a.finalized_at is null
	);
	select coalesce(max(s.score), 0)
	into v_best
	from public.leaderboard_scores as s
	where s.player_id = uid
		and s.period = 'daily'
		and s.period_key = pg_catalog.to_char(v_day, 'YYYY-MM-DD')
		and s.challenge_id is not null;
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
		v_used >= 1 and not v_recoverable,
		v_recoverable,
		v_used,
		greatest(0, 3 - v_used),
		v_best
	from public.reefrun_publish_today() as p
	limit 1;
end;
$$;

drop function if exists public.claim_daily_attempt(uuid);
create function public.claim_daily_attempt(p_idempotency_key uuid)
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
	finalized boolean,
	attempts_used integer,
	attempts_remaining integer,
	best_score integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
	uid uuid := auth.uid();
	v_challenge_id text;
	v_day date;
	v_new_id uuid;
	v_existing_id uuid;
	v_finalized boolean := false;
	v_started boolean := false;
	v_owned boolean := false;
	v_replay boolean := false;
	v_used integer := 0;
	v_pending uuid;
	v_best integer := 0;
begin
	if uid is null then
		raise exception 'not authenticated';
	end if;
	if p_idempotency_key is null then
		raise exception 'missing idempotency key';
	end if;
	select p.challenge_id, p.challenge_date
	into v_challenge_id, v_day
	from public.reefrun_publish_today() as p
	limit 1;
	if v_challenge_id is null then
		raise exception 'challenge unavailable';
	end if;

	perform pg_catalog.pg_advisory_xact_lock(
		pg_catalog.hashtext(uid::text),
		pg_catalog.hashtext(v_challenge_id)
	);

	insert into public.profiles (id, display_name)
	values (uid, 'YOU')
	on conflict (id) do nothing;

	select a.id, a.finalized_at is not null, a.started_at is not null
	into v_existing_id, v_finalized, v_started
	from public.daily_attempts as a
	where a.player_id = uid
		and a.challenge_id = v_challenge_id
		and a.idempotency_key = p_idempotency_key
	for update;

	select count(*)
	into v_used
	from public.daily_attempts as a
	where a.player_id = uid
		and a.challenge_id = v_challenge_id
		and a.started_at is not null;

	if v_existing_id is not null then
		v_replay := true;
		v_owned := not v_started and not v_finalized;
		v_new_id := v_existing_id;
	elsif v_used >= 3 then
		v_owned := false;
	else
		select a.id
		into v_pending
		from public.daily_attempts as a
		where a.player_id = uid
			and a.challenge_id = v_challenge_id
			and a.started_at is null
			and a.finalized_at is null
		for update;
		if v_pending is not null then
			update public.daily_attempts
			set idempotency_key = p_idempotency_key
			where id = v_pending
				and player_id = uid
				and started_at is null
				and finalized_at is null;
			v_new_id := v_pending;
			v_owned := true;
		else
			insert into public.daily_attempts as d (player_id, challenge_id, idempotency_key)
			values (uid, v_challenge_id, p_idempotency_key)
			returning id into v_new_id;
			v_owned := v_new_id is not null;
		end if;
	end if;

	select coalesce(max(s.score), 0)
	into v_best
	from public.leaderboard_scores as s
	where s.player_id = uid
		and s.period = 'daily'
		and s.period_key = pg_catalog.to_char(v_day, 'YYYY-MM-DD')
		and s.challenge_id is not null;

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
		v_finalized,
		v_used,
		greatest(0, 3 - v_used),
		v_best
	from public.reefrun_publish_today() as p
	limit 1;
end;
$$;

drop function if exists public.start_daily_attempt(uuid);
create function public.start_daily_attempt(p_attempt_id uuid)
returns table (
	attempt_id uuid,
	started boolean,
	already_started boolean,
	attempts_used integer,
	attempts_remaining integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
	uid uuid := auth.uid();
	v_started timestamptz;
	v_finalized timestamptz;
	v_challenge_id text;
	v_used integer := 0;
begin
	if uid is null then
		raise exception 'not authenticated';
	end if;
	if p_attempt_id is null then
		raise exception 'missing attempt';
	end if;

	select a.started_at, a.finalized_at, a.challenge_id
	into v_started, v_finalized, v_challenge_id
	from public.daily_attempts as a
	where a.id = p_attempt_id
		and a.player_id = uid
	for update;

	if not found then
		raise exception 'attempt not found';
	end if;

	perform pg_catalog.pg_advisory_xact_lock(
		pg_catalog.hashtext(uid::text),
		pg_catalog.hashtext(v_challenge_id)
	);

	select count(*)
	into v_used
	from public.daily_attempts as a
	where a.player_id = uid
		and a.challenge_id = v_challenge_id
		and a.started_at is not null;

	if v_started is not null or v_finalized is not null then
		return query
		select p_attempt_id, false, true, v_used, greatest(0, 3 - v_used);
		return;
	end if;

	if v_used >= 3 then
		return query
		select p_attempt_id, false, false, v_used, 0;
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
		select p_attempt_id, false, true, v_used, greatest(0, 3 - v_used);
		return;
	end if;

	v_used := v_used + 1;
	return query
	select p_attempt_id, true, false, v_used, greatest(0, 3 - v_used);
end;
$$;

drop function if exists public.finalize_daily_attempt(uuid, integer, text);
create function public.finalize_daily_attempt(
	p_attempt_id uuid,
	p_score integer,
	p_display_name text
)
returns table (
	attempt_id uuid,
	score integer,
	accepted boolean,
	duplicate boolean,
	best_score integer
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
	v_best integer := 0;
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

	day_key := pg_catalog.to_char(v_day, 'YYYY-MM-DD');

	if v_finalized is not null then
		select coalesce(max(s.score), 0)
		into v_best
		from public.leaderboard_scores as s
		where s.player_id = uid
			and s.period = 'daily'
			and s.period_key = day_key
			and s.challenge_id is not null;
		return query
		select p_attempt_id, coalesce(v_existing_score, 0), false, true, v_best;
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
		select coalesce(max(s.score), 0)
		into v_best
		from public.leaderboard_scores as s
		where s.player_id = uid
			and s.period = 'daily'
			and s.period_key = day_key
			and s.challenge_id is not null;
		return query
		select p_attempt_id, coalesce(v_existing_score, 0), false, true, v_best;
		return;
	end if;

	if p_score <= 0 then
		select coalesce(max(s.score), 0)
		into v_best
		from public.leaderboard_scores as s
		where s.player_id = uid
			and s.period = 'daily'
			and s.period_key = day_key
			and s.challenge_id is not null;
		return query
		select p_attempt_id, p_score, true, false, v_best;
		return;
	end if;

	insert into public.profiles (id, display_name)
	values (uid, 'YOU')
	on conflict (id) do nothing;

	clean_name := pg_catalog.left(pg_catalog.btrim(coalesce(p_display_name, '')), 7);
	if clean_name = '' then
		clean_name := 'YOU';
	end if;

	insert into public.leaderboard_scores (player_id, display_name, score, period, period_key, challenge_id)
	values (uid, clean_name, p_score, 'daily', day_key, v_challenge_id)
	on conflict (player_id, period, period_key) where challenge_id is not null
	do update set
		display_name = excluded.display_name,
		challenge_id = excluded.challenge_id,
		score = greatest(public.leaderboard_scores.score, excluded.score)
	where excluded.score > public.leaderboard_scores.score;

	select coalesce(max(s.score), 0)
	into v_best
	from public.leaderboard_scores as s
	where s.player_id = uid
		and s.period = 'daily'
		and s.period_key = day_key
		and s.challenge_id is not null;

	return query
	select p_attempt_id, p_score, true, false, v_best;
end;
$$;

revoke all on function public.get_daily_attempt_status(uuid) from public, anon;
revoke all on function public.claim_daily_attempt(uuid) from public, anon;
revoke all on function public.start_daily_attempt(uuid) from public, anon;
revoke all on function public.finalize_daily_attempt(uuid, integer, text) from public, anon;
grant execute on function public.get_daily_attempt_status(uuid) to authenticated;
grant execute on function public.claim_daily_attempt(uuid) to authenticated;
grant execute on function public.start_daily_attempt(uuid) to authenticated;
grant execute on function public.finalize_daily_attempt(uuid, integer, text) to authenticated;

notify pgrst, 'reload schema';

commit;
