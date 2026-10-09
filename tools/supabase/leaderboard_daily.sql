-- Add DAILY to the existing Reefrun leaderboard.
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to run more than once. Does not change authentication.

do $$
declare
	r record;
begin
	for r in (
		select c.conname
		from pg_constraint c
		where c.conrelid = 'public.leaderboard_scores'::regclass
			and c.contype = 'c'
			and pg_catalog.pg_get_constraintdef(c.oid) ilike '%period%'
	) loop
		execute format('alter table public.leaderboard_scores drop constraint %I', r.conname);
	end loop;
end $$;

alter table public.leaderboard_scores
	add constraint leaderboard_scores_period_check
	check (period in ('daily', 'weekly', 'monthly'));

drop function if exists public.submit_leaderboard_score(integer, text);
drop function if exists public.get_leaderboard(text);

create or replace function public.submit_leaderboard_score(p_score integer, p_display_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
	uid uuid := auth.uid();
	clean_name text;
	day_key text;
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

	clean_name := pg_catalog.left(pg_catalog.btrim(pg_catalog.coalesce(p_display_name, '')), 14);
	if clean_name = '' then
		clean_name := 'YOU';
	end if;

	day_key := pg_catalog.to_char(pg_catalog.timezone('utc', pg_catalog.now()), 'YYYY-MM-DD');
	week_key := pg_catalog.to_char(pg_catalog.date_trunc('week', pg_catalog.timezone('utc', pg_catalog.now())), 'YYYY-MM-DD');
	month_key := pg_catalog.to_char(pg_catalog.timezone('utc', pg_catalog.now()), 'YYYY-MM');

	insert into public.leaderboard_scores (player_id, display_name, score, period, period_key)
	values (uid, clean_name, p_score, 'daily', day_key)
	on conflict (player_id, period, period_key)
	do update set
		display_name = excluded.display_name,
		score = pg_catalog.greatest(public.leaderboard_scores.score, excluded.score);
	insert into public.leaderboard_scores (player_id, display_name, score, period, period_key)
	values (uid, clean_name, p_score, 'weekly', week_key)
	on conflict (player_id, period, period_key)
	do update set
		display_name = excluded.display_name,
		score = pg_catalog.greatest(public.leaderboard_scores.score, excluded.score);
	insert into public.leaderboard_scores (player_id, display_name, score, period, period_key)
	values (uid, clean_name, p_score, 'monthly', month_key)
	on conflict (player_id, period, period_key)
	do update set
		display_name = excluded.display_name,
		score = pg_catalog.greatest(public.leaderboard_scores.score, excluded.score);
end;
$$;

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
			when p_period = 'daily' then pg_catalog.to_char(pg_catalog.timezone('utc', pg_catalog.now()), 'YYYY-MM-DD')
			when p_period = 'weekly' then pg_catalog.to_char(pg_catalog.date_trunc('week', pg_catalog.timezone('utc', pg_catalog.now())), 'YYYY-MM-DD')
			when p_period = 'monthly' then pg_catalog.to_char(pg_catalog.timezone('utc', pg_catalog.now()), 'YYYY-MM')
			else ''
		end
	order by ls.score desc, ls.created_at asc
	limit 10;
$$;

revoke all on function public.submit_leaderboard_score(integer, text) from public, anon, authenticated;
revoke all on function public.get_leaderboard(text) from public, anon, authenticated;
grant execute on function public.submit_leaderboard_score(integer, text) to authenticated;
grant execute on function public.get_leaderboard(text) to authenticated;

notify pgrst, 'reload schema';
