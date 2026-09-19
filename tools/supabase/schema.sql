-- Reefrun STAGE 1–6 schema. Run this in Supabase → SQL Editor → New query.
-- Client uses the anon key only. Never put the service_role key in Godot.
--
-- BEFORE THIS WILL WORK:
-- 1. Authentication → Providers → Anonymous → Enable
-- 2. Project Settings → API: copy Project URL + anon public key into scripts/backend/supabase_config.gd
--
-- TRUST BOUNDARY (do not skip later):
-- The Godot client can be modified. Treat submitted score, coins, placement,
-- and GhostRun flap/death data as untrusted until a server-side validator exists.
-- This schema blocks cross-player edits. It does NOT yet verify that a score
-- or coin total is physically possible.

create extension if not exists "pgcrypto";

create table if not exists public.profiles (
	id uuid primary key references auth.users (id) on delete cascade,
	display_name text not null default 'YOU',
	coins integer not null default 0,
	selected_fish integer not null default 0,
	selected_hat integer not null default -1,
	best_score integer not null default 0,
	best_rank integer not null default 100,
	games_played integer not null default 0,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create table if not exists public.player_cosmetics (
	player_id uuid not null references public.profiles (id) on delete cascade,
	cosmetic_id text not null,
	unlocked_at timestamptz not null default now(),
	primary key (player_id, cosmetic_id)
);

create table if not exists public.ghost_runs (
	id uuid primary key default gen_random_uuid(),
	player_id uuid not null references public.profiles (id) on delete cascade,
	course_seed bigint not null,
	display_name text not null default 'YOU',
	fish_id text not null default 'fish_blue',
	hat_id integer not null default -1,
	flap_ticks integer[] not null default '{}',
	death_tick integer not null default -1,
	score integer not null default 0,
	physics_version integer not null default 1,
	course_version integer not null default 1,
	created_at timestamptz not null default now()
);

create index if not exists ghost_runs_lookup
	on public.ghost_runs (course_seed, course_version, physics_version, created_at desc);

create table if not exists public.course_rotations (
	id uuid primary key default gen_random_uuid(),
	course_seed bigint not null,
	course_version integer not null default 1,
	physics_version integer not null default 1,
	starts_at timestamptz not null default now(),
	ends_at timestamptz
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

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
	new.updated_at = now();
	return new;
end;
$$;

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at
	before update on public.profiles
	for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
	insert into public.profiles (id, display_name)
	values (new.id, 'YOU')
	on conflict (id) do nothing;
	return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
	after insert on auth.users
	for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.player_cosmetics enable row level security;
alter table public.ghost_runs enable row level security;
alter table public.course_rotations enable row level security;
alter table public.leaderboard_scores enable row level security;

drop policy if exists profiles_select_own_or_public on public.profiles;
create policy profiles_select_authenticated on public.profiles
	for select to authenticated using (true);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
	for update to authenticated
	using (auth.uid() = id)
	with check (auth.uid() = id);

drop policy if exists cosmetics_select_self on public.player_cosmetics;
create policy cosmetics_select_self on public.player_cosmetics
	for select to authenticated using (auth.uid() = player_id);

drop policy if exists cosmetics_insert_self on public.player_cosmetics;
create policy cosmetics_insert_self on public.player_cosmetics
	for insert to authenticated with check (auth.uid() = player_id);

drop policy if exists ghost_runs_select_compatible on public.ghost_runs;
create policy ghost_runs_select_authenticated on public.ghost_runs
	for select to authenticated using (true);

drop policy if exists ghost_runs_insert_self on public.ghost_runs;
create policy ghost_runs_insert_self on public.ghost_runs
	for insert to authenticated with check (auth.uid() = player_id);

drop policy if exists course_rotations_select on public.course_rotations;
create policy course_rotations_select on public.course_rotations
	for select to authenticated using (true);

drop policy if exists leaderboard_select on public.leaderboard_scores;
create policy leaderboard_select on public.leaderboard_scores
	for select to authenticated using (true);

revoke all on public.profiles from anon, authenticated;
revoke all on public.player_cosmetics from anon, authenticated;
revoke all on public.ghost_runs from anon, authenticated;
revoke all on public.course_rotations from anon, authenticated;
revoke all on public.leaderboard_scores from anon, authenticated;

grant select on public.profiles to authenticated;
grant update (display_name, selected_fish, selected_hat) on public.profiles to authenticated;

grant select, insert on public.player_cosmetics to authenticated;
grant select, insert on public.ghost_runs to authenticated;
grant select on public.course_rotations to authenticated;
grant select on public.leaderboard_scores to authenticated;

-- Seed one shared course so matches can accumulate GhostRuns.
-- Change the seed whenever you rotate the weekly course.
insert into public.course_rotations (course_seed, course_version, physics_version)
select 827361, 1, 1
where not exists (select 1 from public.course_rotations);

-- FUTURE SERVER-SIDE VALIDATION (do not treat client writes as truth):
--   submit_ghost_run(...)     — re-simulate flap_ticks; reject incompatible/impossible runs
--   grant_coins(...)          — award coins only after a validated run
--   record_best(...)          — update best_score / best_rank / games_played
--   submit_leaderboard(...)   — write weekly/monthly rows after validation
-- Until those RPCs exist, a modified client can still inflate its own
-- GhostRun score or cosmetics. It cannot edit another player's rows.
