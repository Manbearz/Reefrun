-- DO NOT RUN THIS FILE. It updates profiles.coins. The live profiles table
-- used by ReefRun does not rely on that column. Review and run
-- tools/supabase/share_rewards_safe.sql instead, and only after approval.
--
-- Share Rewards. Run this yourself in Supabase → SQL Editor → New query.
-- Do not run it from the game. The game keeps using the anon key only.
--
-- This script does not drop tables, does not delete rows, and does not replace
-- get_leaderboard, submit_leaderboard_score, claim_daily_attempt,
-- get_daily_attempt_status, finalize_daily_attempt, or the daily challenge RPCs.
--
-- Impact on existing data:
--   profiles gains three columns, all safe for current rows:
--     referral_code       text, null until that player opens Share
--     first_run_at        timestamptz, null for accounts created after the seal
--     share_reward_coins  integer, default 0, only ever 0 or 100
--   The first time this script runs, every profile that already exists is
--   marked with first_run_at = created_at. Those accounts are not "new players"
--   and cannot be counted as referrals. Re-running the script does not stamp
--   accounts created later. A brand-new profile still has first_run_at null
--   until sync_share_progress records their first finished run.
--   profiles.coins is only increased by this script's grant (100, once).
--   The column grant for authenticated users is unchanged, so the client still
--   cannot update coins, referral_code, first_run_at, or share_reward_coins.
--
-- Anonymous auth is a device session, not a unique person. The functions below
-- reject self-referrals, second attachments, and players who already finished
-- a run. They cannot stop someone from creating three new anonymous users.

create table if not exists public.share_reward_meta (
	id integer primary key check (id = 1),
	existing_players_sealed boolean not null default false
);

insert into public.share_reward_meta (id, existing_players_sealed)
values (1, false)
on conflict (id) do nothing;

alter table public.profiles
	add column if not exists referral_code text,
	add column if not exists first_run_at timestamptz,
	add column if not exists share_reward_coins integer not null default 0;

do $$
begin
	if not exists (
		select 1
		from pg_catalog.pg_constraint
		where conname = 'profiles_share_reward_coins_check'
	) then
		alter table public.profiles
			add constraint profiles_share_reward_coins_check
			check (share_reward_coins in (0, 100));
	end if;
end $$;

create unique index if not exists profiles_referral_code_key
	on public.profiles (referral_code)
	where referral_code is not null and referral_code <> '';

update public.profiles
set first_run_at = coalesce(created_at, pg_catalog.now())
where first_run_at is null
	and exists (
		select 1
		from public.share_reward_meta
		where id = 1 and existing_players_sealed = false
	);

update public.share_reward_meta
set existing_players_sealed = true
where id = 1 and existing_players_sealed = false;

create table if not exists public.referrals (
	id uuid primary key default gen_random_uuid(),
	referrer_id uuid not null references public.profiles (id) on delete cascade,
	referred_id uuid not null references public.profiles (id) on delete cascade,
	created_at timestamptz not null default pg_catalog.now(),
	qualified_at timestamptz,
	constraint referrals_no_self check (referrer_id <> referred_id),
	constraint referrals_one_referrer unique (referred_id)
);

create index if not exists referrals_referrer_qualified
	on public.referrals (referrer_id, qualified_at);

create table if not exists public.share_reward_grants (
	player_id uuid primary key references public.profiles (id) on delete cascade,
	coins integer not null check (coins = 100),
	qualified_count integer not null,
	granted_at timestamptz not null default pg_catalog.now()
);

alter table public.share_reward_meta enable row level security;
alter table public.referrals enable row level security;
alter table public.share_reward_grants enable row level security;

revoke all on public.share_reward_meta from public, anon, authenticated;
revoke all on public.referrals from public, anon, authenticated;
revoke all on public.share_reward_grants from public, anon, authenticated;

-- Internal. Not granted to the client. Uses auth.uid() only.
create or replace function public.ensure_referral_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
	uid uuid := auth.uid();
	existing text;
	candidate text;
	alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
	tries integer := 0;
	i integer;
	pick integer;
begin
	if uid is null then
		raise exception 'not_authenticated';
	end if;
	insert into public.profiles (id)
	values (uid)
	on conflict (id) do nothing;
	select referral_code into existing
	from public.profiles
	where id = uid
	for update;
	if existing is not null and existing <> '' then
		return existing;
	end if;
	loop
		tries := tries + 1;
		candidate := '';
		for i in 1..8 loop
			pick := 1 + pg_catalog.floor(pg_catalog.random() * 32)::integer;
			if pick > 32 then
				pick := 32;
			end if;
			candidate := candidate || pg_catalog.substr(alphabet, pick, 1);
		end loop;
		begin
			update public.profiles
			set referral_code = candidate
			where id = uid
				and (referral_code is null or referral_code = '');
			if found then
				return candidate;
			end if;
			select referral_code into existing
			from public.profiles
			where id = uid;
			if existing is not null and existing <> '' then
				return existing;
			end if;
		exception
			when unique_violation then
				if tries >= 8 then
					raise exception 'code_exhausted';
				end if;
		end;
		if tries >= 8 then
			raise exception 'code_exhausted';
		end if;
	end loop;
end;
$$;

revoke all on function public.ensure_referral_code() from public, anon, authenticated;

create or replace function public.sync_share_progress(
	p_code text default '',
	p_run_completed boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
	uid uuid := auth.uid();
	clean text := '';
	attach_reason text := 'skipped';
	referrer uuid;
	existing_ref uuid;
	mine timestamptz;
	claimed uuid;
	qualified_count integer := 0;
	code text := '';
	did_run boolean := false;
	granted integer := 0;
begin
	if uid is null then
		return pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
	end if;
	insert into public.profiles (id)
	values (uid)
	on conflict (id) do nothing;
	perform public.ensure_referral_code();

	clean := upper(pg_catalog.regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
	if length(clean) > 16 then
		clean := pg_catalog.substr(clean, 1, 16);
	end if;
	if clean <> '' then
		if length(clean) < 4 then
			attach_reason := 'unknown';
		else
			select id into referrer
			from public.profiles
			where referral_code = clean;
			if referrer is null then
				attach_reason := 'unknown';
			elsif referrer = uid then
				attach_reason := 'self';
			else
				select first_run_at into mine
				from public.profiles
				where id = uid
				for update;
				if mine is not null then
					attach_reason := 'already_played';
				else
					select referrer_id into existing_ref
					from public.referrals
					where referred_id = uid;
					if existing_ref is not null then
						attach_reason := 'already_attached';
					else
						begin
							insert into public.referrals (referrer_id, referred_id)
							values (referrer, uid);
							attach_reason := 'attached';
						exception
							when unique_violation then
								attach_reason := 'already_attached';
						end;
					end if;
				end if;
			end if;
		end if;
	end if;

	if coalesce(p_run_completed, false) then
		update public.profiles
		set first_run_at = pg_catalog.now()
		where id = uid and first_run_at is null
		returning id into claimed;
		if claimed is not null then
			referrer := null;
			update public.referrals
			set qualified_at = pg_catalog.now()
			where referred_id = uid and qualified_at is null
			returning referrer_id into referrer;
			if referrer is not null then
				perform 1
				from public.profiles
				where id = referrer
				for update;
				select count(*) into qualified_count
				from public.referrals
				where referrer_id = referrer and qualified_at is not null;
				if qualified_count >= 3 then
					insert into public.share_reward_grants (player_id, coins, qualified_count)
					values (referrer, 100, qualified_count)
					on conflict (player_id) do nothing;
					update public.profiles
					set coins = coins + 100,
						share_reward_coins = 100
					where id = referrer
						and share_reward_coins = 0
						and exists (
							select 1
							from public.share_reward_grants as g
							where g.player_id = referrer
						);
				end if;
			end if;
		end if;
	end if;

	select p.referral_code,
		p.first_run_at is not null,
		p.share_reward_coins
	into code, did_run, granted
	from public.profiles as p
	where p.id = uid;
	select count(*) into qualified_count
	from public.referrals
	where referrer_id = uid and qualified_at is not null;
	return pg_catalog.jsonb_build_object(
		'ok', true,
		'code', coalesce(code, ''),
		'qualified', qualified_count,
		'target', 3,
		'reward_coins', 100,
		'granted_coins', granted,
		'first_run', did_run,
		'attach', attach_reason
	);
end;
$$;

create or replace function public.get_share_reward_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
	uid uuid := auth.uid();
	code text := '';
	did_run boolean := false;
	granted integer := 0;
	qualified_count integer := 0;
begin
	if uid is null then
		return pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
	end if;
	insert into public.profiles (id)
	values (uid)
	on conflict (id) do nothing;
	perform public.ensure_referral_code();
	select p.referral_code,
		p.first_run_at is not null,
		p.share_reward_coins
	into code, did_run, granted
	from public.profiles as p
	where p.id = uid;
	select count(*) into qualified_count
	from public.referrals
	where referrer_id = uid and qualified_at is not null;
	return pg_catalog.jsonb_build_object(
		'ok', true,
		'code', coalesce(code, ''),
		'qualified', qualified_count,
		'target', 3,
		'reward_coins', 100,
		'granted_coins', granted,
		'first_run', did_run,
		'attach', 'skipped'
	);
end;
$$;

revoke all on function public.sync_share_progress(text, boolean) from public, anon, authenticated;
revoke all on function public.get_share_reward_status() from public, anon, authenticated;
grant execute on function public.sync_share_progress(text, boolean) to authenticated;
grant execute on function public.get_share_reward_status() to authenticated;

notify pgrst, 'reload schema';
