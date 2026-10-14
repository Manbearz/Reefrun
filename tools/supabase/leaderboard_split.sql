-- ReefRun leaderboard split.
-- Run this AFTER tools/supabase/daily_attempt.sql has already been applied.
-- Supabase Dashboard → SQL Editor → New query → paste this file → Run.
-- Replaces three functions. Does not drop tables, indexes, or policies.
-- Does not delete or rewrite leaderboard_scores or daily_attempts rows.
-- CREATE OR REPLACE keeps existing EXECUTE grants. authenticated is granted
-- again so an anonymous-auth session can still call the functions.
--
-- Daily board: challenge_id is not null, written only by finalize_daily_attempt.
-- Weekly and Monthly boards: challenge_id is null, written only by
-- submit_leaderboard_score. The daily board uses the America/New_York date.
-- Weekly and monthly keys stay UTC Monday and UTC month.

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

grant execute on function public.finalize_daily_attempt(uuid, integer, text) to authenticated;
grant execute on function public.submit_leaderboard_score(integer, text) to authenticated;
grant execute on function public.get_leaderboard(text) to authenticated;

notify pgrst, 'reload schema';

-- Read-only checks. These selects do not insert, update, or delete rows.
select section, item, detail
from (
	select 10 as sort_key, 'scores'::text as section, 'row_count'::text as item, count(*)::text as detail
	from public.leaderboard_scores

	union all
	select 20, 'attempts', 'row_count', count(*)::text
	from public.daily_attempts

	union all
	select 30, 'score_bucket',
		period || ' ' || period_key || ' ' || case when challenge_id is null then 'unlimited' else 'daily' end,
		count(*)::text
	from public.leaderboard_scores
	group by period, period_key, (challenge_id is null)

	union all
	select 40, 'index', ix.relname, pg_catalog.pg_get_indexdef(i.indexrelid)
	from pg_catalog.pg_index as i
	join pg_catalog.pg_class as t on t.oid = i.indrelid
	join pg_catalog.pg_class as ix on ix.oid = i.indexrelid
	join pg_catalog.pg_namespace as n on n.oid = t.relnamespace
	where n.nspname = 'public'
		and t.relname = 'leaderboard_scores'
		and ix.relname in ('leaderboard_scores_daily_period', 'leaderboard_scores_unlimited_period')

	union all
	select 50, 'function_check', p.proname,
		case p.proname
			when 'get_leaderboard' then
				case
					when pg_catalog.pg_get_functiondef(p.oid) ilike '%p_period = ''daily'' and ls.challenge_id is not null%'
						and pg_catalog.pg_get_functiondef(p.oid) ilike '%p_period in (''weekly'', ''monthly'') and ls.challenge_id is null%'
					then 'daily challenge, weekly and monthly unlimited'
					else 'UNEXPECTED'
				end
			when 'finalize_daily_attempt' then
				case
					when pg_catalog.pg_get_functiondef(p.oid) ilike '%''daily''%'
						and pg_catalog.pg_get_functiondef(p.oid) not ilike '%''weekly''%'
						and pg_catalog.pg_get_functiondef(p.oid) not ilike '%''monthly''%'
					then 'daily row only'
					else 'UNEXPECTED'
				end
			when 'submit_leaderboard_score' then
				case
					when pg_catalog.pg_get_functiondef(p.oid) ilike '%''weekly''%'
						and pg_catalog.pg_get_functiondef(p.oid) ilike '%''monthly''%'
						and pg_catalog.pg_get_functiondef(p.oid) not ilike '%''daily''%'
					then 'weekly and monthly only'
					else 'UNEXPECTED'
				end
			else 'UNEXPECTED'
		end
	from pg_catalog.pg_proc as p
	join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
	where n.nspname = 'public'
		and p.proname in ('get_leaderboard', 'finalize_daily_attempt', 'submit_leaderboard_score')
) as report
order by sort_key, section, item;
