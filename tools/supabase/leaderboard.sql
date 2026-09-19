-- ============================================================
-- REEFRUN LEADERBOARD SUPABASE SETUP
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to run more than once.
-- Does not change Authentication providers or Godot client keys.
-- ============================================================

create extension if not exists "pgcrypto";

-- Required by leaderboard_scores.player_id FK.
-- No-op if profiles already exists from the main Reefrun schema.
create table if not exists public.profiles (
	id uuid primary key references auth.users (id) on delete cascade,
	display_name text not null default 'YOU',
	created_at timestamptz not null default now()
);

create table if not exists public.leaderboard_scores (
	id uuid primary key default gen_random_uuid(),
	player_id uuid not null references public.profiles (id) on delete cascade,
	display_name text not null,
	score integer not null,
	period text not null check (period in ('weekly', 'monthly')),
	period_key text not null,
	created_at timestamptz not null default now()
);

alter table public.leaderboard_scores
	add column if not exists player_id uuid,
	add column if not exists display_name text,
	add column if not exists score integer,
	add column if not exists period text,
	add column if not exists period_key text,
	add column if not exists created_at timestamptz default now();

-- Required for submit upsert: one best score per auth user per period bucket.
create unique index if not exists leaderboard_scores_player_period
	on public.leaderboard_scores (player_id, period, period_key);

-- Helps get_leaderboard sort/filter the current week/month.
create index if not exists leaderboard_scores_period_lookup
	on public.leaderboard_scores (period, period_key, score desc, created_at asc);

-- ------------------------------------------------------------
-- profiles: RLS required. Reefrun only GETs the signed-in row.
-- Profile creation is done inside submit_leaderboard_score.
-- ------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists profiles_select_own_or_public on public.profiles;
drop policy if exists profiles_select_authenticated on public.profiles;
drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_insert_self on public.profiles;
drop policy if exists profiles_update_self on public.profiles;
drop policy if exists profiles_delete_self on public.profiles;

create policy profiles_select_own on public.profiles
	for select to authenticated
	using (id = auth.uid());

revoke all on table public.profiles from public, anon, authenticated;
grant select on table public.profiles to authenticated;

-- ------------------------------------------------------------
-- leaderboard_scores: authenticated may read. Writes only via RPC.
-- ------------------------------------------------------------
alter table public.leaderboard_scores enable row level security;

drop policy if exists leaderboard_select on public.leaderboard_scores;
drop policy if exists leaderboard_insert on public.leaderboard_scores;
drop policy if exists leaderboard_update on public.leaderboard_scores;
drop policy if exists leaderboard_delete on public.leaderboard_scores;

create policy leaderboard_select on public.leaderboard_scores
	for select to authenticated using (true);

revoke all on table public.leaderboard_scores from public, anon, authenticated;
grant select on table public.leaderboard_scores to authenticated;

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

	-- Server UTC. Do not trust the device clock.
	week_key := pg_catalog.to_char(pg_catalog.date_trunc('week', pg_catalog.timezone('utc', pg_catalog.now())), 'YYYY-MM-DD');
	month_key := pg_catalog.to_char(pg_catalog.timezone('utc', pg_catalog.now()), 'YYYY-MM');

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
