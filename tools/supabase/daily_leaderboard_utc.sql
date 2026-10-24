-- Do not apply this file. The live Daily Challenge and Daily leaderboard
-- reset at midnight America/New_York. Applying this would move the Daily
-- board to midnight UTC.
--
-- Align the Daily leaderboard with the UTC challenge date.
-- Supabase Dashboard → SQL Editor → New query → paste this file → Run.
-- Do not run until the UTC date fix is approved.
--
-- reefrun_publish_today in daily_start_fix.sql publishes
-- daily:YYYY-MM-DD:cv1:pv1 for the UTC date. finalize_daily_attempt stores
-- leaderboard_scores.period_key from that challenge_date. This function was
-- still selecting America/New_York, so after 00:00 UTC (20:00 EDT) the stored
-- score is on the next UTC date and the board query misses it.
--
-- Replaces get_leaderboard only. Does not insert, update, or delete scores
-- or attempts. Weekly and monthly stay on UTC. One attempt per day is unchanged.
--
-- Before running, this read-only check shows whether the finished run was stored
-- and which date key it used. Run it by itself if you want to look first:
--
-- select period_key, challenge_id, display_name, score, created_at
-- from public.leaderboard_scores
-- where period = 'daily' and challenge_id is not null
-- order by created_at desc
-- limit 20;

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
			when p_period = 'daily' then pg_catalog.to_char((pg_catalog.timezone('utc', pg_catalog.now()))::date, 'YYYY-MM-DD')
			when p_period = 'weekly' then pg_catalog.to_char(pg_catalog.date_trunc('week', pg_catalog.timezone('utc', pg_catalog.now())), 'YYYY-MM-DD')
			when p_period = 'monthly' then pg_catalog.to_char(pg_catalog.timezone('utc', pg_catalog.now()), 'YYYY-MM')
			else ''
		end
	order by ls.score desc, ls.created_at asc
	limit 10;
$$;

grant execute on function public.get_leaderboard(text) to authenticated;

notify pgrst, 'reload schema';
