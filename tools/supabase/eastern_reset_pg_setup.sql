-- Isolated reconstruction of the pre-migration tables. This is not production.
-- Profiles are not tied to auth.users so the throwaway database needs no GoTrue.

create extension if not exists pgcrypto;

do $roles$
begin
	if not exists (select 1 from pg_roles where rolname = 'anon') then
		create role anon nologin;
	end if;
	if not exists (select 1 from pg_roles where rolname = 'authenticated') then
		create role authenticated nologin;
	end if;
end
$roles$;

create schema if not exists auth;

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
	select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create table if not exists public.profiles (
	id uuid primary key,
	display_name text not null default 'YOU',
	created_at timestamptz not null default now()
);

create table if not exists public.daily_challenges (
	challenge_id text primary key,
	challenge_date date not null,
	course_seed bigint not null,
	course_version integer not null,
	physics_version integer not null,
	created_at timestamptz not null default now()
);

create table if not exists public.daily_attempts (
	id uuid primary key default gen_random_uuid(),
	player_id uuid not null references public.profiles (id) on delete cascade,
	challenge_id text not null references public.daily_challenges (challenge_id),
	idempotency_key uuid not null,
	score integer,
	finalized_at timestamptz,
	started_at timestamptz,
	claimed_at timestamptz not null default now(),
	constraint daily_attempts_player_challenge unique (player_id, challenge_id)
);

create table if not exists public.leaderboard_scores (
	id uuid primary key default gen_random_uuid(),
	player_id uuid not null references public.profiles (id) on delete cascade,
	display_name text not null,
	score integer not null check (score >= 0),
	period text not null check (period in ('daily', 'weekly', 'monthly')),
	period_key text not null,
	challenge_id text,
	created_at timestamptz not null default now()
);

create unique index if not exists leaderboard_scores_player_period_daily
	on public.leaderboard_scores (player_id, period, period_key)
	where challenge_id is not null;

create unique index if not exists leaderboard_scores_player_period_open
	on public.leaderboard_scores (player_id, period, period_key)
	where challenge_id is null;

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
