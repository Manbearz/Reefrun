-- READ ONLY. Run this immediately after eastern_daily_reset.sql, before any
-- TestFlight play. Do not call gameplay RPCs. Do not call reefrun_publish_today(),
-- because that function inserts a challenge row.
--
-- Compare INFO row counts with the saved production_preflight.sql grid.
-- A count that went down is a blocker. A count that went up means new rows
-- were written after the preflight; it does not by itself mean the migration
-- deleted anything. Run this before playing, so the counts should match.
--
-- Any FAIL means stop and follow tools/supabase/production_backup_checklist.md.
-- This file has not been executed against production.

with clock as (
	select
		(pg_catalog.timezone('utc', pg_catalog.now()))::date as utc_day,
		(pg_catalog.timezone('America/New_York', pg_catalog.now()))::date as eastern_day
),
bodies as (
	select
		functions.proname,
		pg_get_function_identity_arguments(functions.oid) as identity_args,
		pg_get_functiondef(functions.oid) as definition,
		functions.oid,
		functions.pronargdefaults,
		functions.prosecdef
	from pg_proc as functions
	where functions.pronamespace = 'public'::regnamespace
		and functions.proname in (
			'reefrun_publish_today',
			'get_leaderboard',
			'reefrun_daily_mission_board',
			'claim_daily_mission',
			'record_unlimited_mission_run',
			'reefrun_mission_snapshot',
			'get_daily_missions'
		)
)
select check_name, status, detail
from (
	select
		'post_clock' as check_name,
		case when utc_day = eastern_day then 'INFO' else 'REVIEW' end as status,
		format('utc=%s eastern=%s', utc_day, eastern_day) as detail
	from clock

	union all
	select
		'dive_progress_columns',
		case when count(*) = 10 then 'PASS' else 'FAIL' end,
		'found=' || count(*)::text || ' expected=10 integer columns'
	from information_schema.columns
	where table_schema = 'public'
		and table_name = 'daily_mission_progress'
		and column_name in (
			'dives_entered', 'dives_completed', 'best_dives', 'dive_seconds',
			'lane_changes', 'lanes_left', 'lanes_right',
			'obstacles_dodged', 'best_obstacles', 'mines_passed'
		)
		and data_type = 'integer'

	union all
	select
		'dive_run_log_columns',
		case when count(*) = 8 then 'PASS' else 'FAIL' end,
		'found=' || count(*)::text || ' expected=8 integer columns'
	from information_schema.columns
	where table_schema = 'public'
		and table_name = 'daily_mission_run_log'
		and column_name in (
			'dives_entered', 'dives_completed', 'dive_seconds',
			'lane_changes', 'lanes_left', 'lanes_right', 'obstacles', 'mines'
		)
		and data_type = 'integer'

	union all
	select
		'old_pipe_caps_removed',
		case when count(*) = 0 then 'PASS' else 'FAIL' end,
		coalesce(string_agg(format('%s %s :: %s', conrelid::regclass, conname, pg_get_constraintdef(oid)), ' | '), 'none')
	from pg_constraint
	where contype = 'c'
		and conrelid = any (array[
			to_regclass('public.daily_mission_progress'),
			to_regclass('public.daily_mission_run_log')
		]::oid[])
		and (
			pg_get_constraintdef(oid) ~ '<= 80\)'
			or pg_get_constraintdef(oid) ~ '<= 1800\)'
			or pg_get_constraintdef(oid) ~* 'between 0 and 80'
			or pg_get_constraintdef(oid) ~* 'between 0 and 1800'
		)

	union all
	select
		'long_run_caps_present',
		case when count(*) = 4 then 'PASS' else 'FAIL' end,
		coalesce(string_agg(conname || ' :: ' || pg_get_constraintdef(oid), ' | ' order by conname), 'none')
	from pg_constraint
	where conname in (
		'daily_mission_run_log_pipes_cap',
		'daily_mission_run_log_seconds_cap',
		'daily_mission_progress_best_pipes_cap',
		'daily_mission_progress_best_seconds_cap'
	)

	union all
	select
		'recorder_overloads',
		case
			when count(*) = 2 and bool_and(pronargdefaults = 0) then 'PASS'
			else 'FAIL'
		end,
		coalesce(string_agg(identity_args || ' defaults=' || pronargdefaults::text, ' | ' order by identity_args), 'none')
	from bodies
	where proname = 'record_unlimited_mission_run'

	union all
	select
		'snapshot_overloads',
		case when count(*) = 2 then 'PASS' else 'FAIL' end,
		coalesce(string_agg(identity_args, ' | ' order by identity_args), 'none')
	from bodies
	where proname = 'reefrun_mission_snapshot'

	union all
	select
		'publish_uses_eastern',
		case
			when count(*) <> 1 then 'FAIL'
			when bool_and(
				position('America/New_York' in definition) > 0
				and position('timezone(''utc''' in definition) = 0
			) then 'PASS'
			else 'FAIL'
		end,
		'functions=' || count(*)::text
	from bodies
	where proname = 'reefrun_publish_today'

	union all
	select
		'leaderboard_daily_eastern_weekly_monthly_utc',
		case
			when count(*) <> 1 then 'FAIL'
			when bool_and(
				position('America/New_York' in definition) > 0
				and position('date_trunc(''week'', pg_catalog.timezone(''utc''' in definition) > 0
				and position('to_char(pg_catalog.timezone(''utc''' in definition) > 0
			) then 'PASS'
			else 'FAIL'
		end,
		'functions=' || count(*)::text
	from bodies
	where proname = 'get_leaderboard'

	union all
	select
		'missions_use_eastern ' || proname,
		case
			when count(*) < 1 then 'FAIL'
			when bool_or(position('timezone(''utc''' in definition) > 0) then 'FAIL'
			when bool_or(position('America/New_York' in definition) > 0) then 'PASS'
			else 'FAIL'
		end,
		'overloads=' || count(*)::text
	from bodies
	where proname in (
		'reefrun_daily_mission_board',
		'claim_daily_mission',
		'record_unlimited_mission_run'
	)
	group by proname

	union all
	select
		'snapshot_contains_dive_rules',
		case
			when count(*) filter (
				where position('when ''dives_entered''' in definition) > 0
					and position('when ''mines_total''' in definition) > 0
					and position('when ''pipes_total''' in definition) > 0
					and position('when ''survive_best''' in definition) > 0
					and position('when ''window_sum''' in definition) > 0
			) = 1 then 'PASS'
			else 'FAIL'
		end,
		'matching_overloads=' || count(*) filter (
			where position('when ''dives_entered''' in definition) > 0
		)::text
	from bodies
	where proname = 'reefrun_mission_snapshot'

	union all
	select
		'four_argument_forwards_zeros',
		case
			when count(*) filter (
				where identity_args = 'p_run_id text, p_pipes integer, p_seconds integer, p_gameplay_coins integer'
					and position('0, 0, 0, 0, 0, 0, 0, 0' in definition) > 0
			) = 1 then 'PASS'
			else 'FAIL'
		end,
		'four-argument body should forward eight zeros and must not have defaults'
	from bodies
	where proname = 'record_unlimited_mission_run'

	union all
	select
		'deep_dive_definitions_still_absent',
		case
			when count(*) filter (
				where id >= 46
					or rule in (
						'dives_entered', 'dives_completed', 'dives_best', 'dive_seconds',
						'lanes_total', 'lanes_left', 'lanes_right',
						'obstacles_total', 'obstacles_best', 'mines_total'
					)
			) = 0 then 'PASS'
			else 'FAIL'
		end,
		format('definitions=%s', count(*))
	from public.mission_definitions

	union all
	select
		'authenticated_can_call ' || label,
		case
			when to_regprocedure(signature) is null then 'FAIL'
			when has_function_privilege('authenticated', to_regprocedure(signature), 'execute') then 'PASS'
			else 'FAIL'
		end,
		case
			when to_regprocedure(signature) is null then signature || ' missing'
			else signature
		end
	from (values
		('get_daily_missions', 'public.get_daily_missions()'),
		('claim_daily_mission', 'public.claim_daily_mission(text)'),
		('record_4', 'public.record_unlimited_mission_run(text,integer,integer,integer)'),
		('record_12', 'public.record_unlimited_mission_run(text,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer)'),
		('get_leaderboard', 'public.get_leaderboard(text)'),
		('get_daily_challenge', 'public.get_daily_challenge()'),
		('claim_daily_attempt', 'public.claim_daily_attempt(uuid)'),
		('finalize_daily_attempt', 'public.finalize_daily_attempt(uuid,integer,text)'),
		('submit_leaderboard_score', 'public.submit_leaderboard_score(integer,text)')
	) as expected(label, signature)

	union all
	select
		'internal_not_executable ' || label,
		case
			when to_regprocedure(signature) is null then 'FAIL'
			when has_function_privilege('anon', to_regprocedure(signature), 'execute')
				or has_function_privilege('authenticated', to_regprocedure(signature), 'execute')
				then 'FAIL'
			else 'PASS'
		end,
		signature
	from (values
		('board', 'public.reefrun_daily_mission_board(uuid)'),
		('snapshot_20', 'public.reefrun_mission_snapshot(text,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer[])')
	) as expected(label, signature)

	union all
	select
		'anon_cannot_claim_or_record',
		case
			when to_regprocedure('public.claim_daily_mission(text)') is null
				or to_regprocedure('public.record_unlimited_mission_run(text,integer,integer,integer)') is null
				or to_regprocedure('public.record_unlimited_mission_run(text,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer)') is null
				or to_regprocedure('public.get_leaderboard(text)') is null
				then 'FAIL'
			when has_function_privilege('anon', 'public.claim_daily_mission(text)', 'execute')
				or has_function_privilege('anon', 'public.record_unlimited_mission_run(text,integer,integer,integer)', 'execute')
				or has_function_privilege('anon', 'public.record_unlimited_mission_run(text,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer)', 'execute')
				or has_function_privilege('anon', 'public.get_leaderboard(text)', 'execute')
				then 'FAIL'
			else 'PASS'
		end,
		'anon must not claim, record, or read the leaderboard RPC'

	union all
	select
		'row_count ' || tables.table_name,
		'INFO',
		tables.row_count::text
	from (
		select 'profiles' as table_name, count(*) as row_count from public.profiles
		union all select 'daily_challenges', count(*) from public.daily_challenges
		union all select 'daily_attempts', count(*) from public.daily_attempts
		union all select 'leaderboard_scores', count(*) from public.leaderboard_scores
		union all select 'mission_definitions', count(*) from public.mission_definitions
		union all select 'daily_mission_sets', count(*) from public.daily_mission_sets
		union all select 'daily_mission_progress', count(*) from public.daily_mission_progress
		union all select 'daily_mission_run_log', count(*) from public.daily_mission_run_log
		union all select 'daily_mission_claims', count(*) from public.daily_mission_claims
	) as tables
) as results
order by
	case status when 'FAIL' then 0 when 'REVIEW' then 1 when 'INFO' then 3 else 2 end,
	check_name;
