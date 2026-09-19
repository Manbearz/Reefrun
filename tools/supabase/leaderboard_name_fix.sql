-- Targeted name-column fix. Run in Supabase → SQL Editor → New query → Run.
-- Does not change authentication. Makes get_leaderboard return:
--   display_name text, score integer

create or replace function public.get_leaderboard(p_period text)
returns table (display_name text, score integer)
language sql
stable
security definer
set search_path = public
as $$
	select ls.display_name::text as display_name, ls.score::integer as score
	from public.leaderboard_scores ls
	where ls.period = p_period
		and ls.period_key = case
			when p_period = 'weekly' then to_char(date_trunc('week', timezone('utc', now())), 'YYYY-MM-DD')
			when p_period = 'monthly' then to_char(timezone('utc', now()), 'YYYY-MM')
			else ''
		end
	order by ls.score desc, ls.created_at asc
	limit 10;
$$;

grant execute on function public.get_leaderboard(text) to authenticated;
