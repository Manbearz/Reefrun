-- READ ONLY. Paste the whole file into the Supabase SQL Editor and run it once.
-- Do not add INSERT, UPDATE, DELETE, ALTER, DROP, GRANT, NOTIFY, or a call
-- to a gameplay RPC. This file does not start a challenge, record a run,
-- claim a reward, or submit a score.
--
-- Save the result grid before migrating. Any row whose status is FAIL means
-- do not run eastern_daily_reset.sql. REVIEW rows need a human decision.
-- INFO rows are the backup notes: row counts, fingerprints, and clock.
--
-- This file has not been executed against production.

with clock as (
	select
		(pg_catalog.timezone('utc', pg_catalog.now()))::date as utc_day,
		(pg_catalog.timezone('America/New_York', pg_catalog.now()))::date as eastern_day,
		pg_catalog.timezone('America/New_York', pg_catalog.now()) as eastern_local,
		(
			(pg_catalog.date_trunc('day', pg_catalog.timezone('utc', pg_catalog.now())) + interval '1 day')
			at time zone 'utc'
		) as next_utc_midnight
),
required_tables(table_name) as (
	values
		('public.profiles'),
		('public.daily_challenges'),
		('public.daily_attempts'),
		('public.leaderboard_scores'),
		('public.mission_definitions'),
		('public.daily_mission_sets'),
		('public.daily_mission_progress'),
		('public.daily_mission_run_log'),
		('public.daily_mission_claims')
),
required_columns(table_name, column_name, type_name) as (
	values
		('profiles', 'id', 'uuid'),
		('profiles', 'mission_reward_coins', 'integer'),
		('daily_challenges', 'challenge_id', 'text'),
		('daily_challenges', 'challenge_date', 'date'),
		('daily_challenges', 'course_seed', 'bigint'),
		('daily_challenges', 'course_version', 'integer'),
		('daily_challenges', 'physics_version', 'integer'),
		('daily_attempts', 'player_id', 'uuid'),
		('daily_attempts', 'challenge_id', 'text'),
		('daily_attempts', 'idempotency_key', 'uuid'),
		('leaderboard_scores', 'player_id', 'uuid'),
		('leaderboard_scores', 'score', 'integer'),
		('leaderboard_scores', 'period', 'text'),
		('leaderboard_scores', 'period_key', 'text'),
		('leaderboard_scores', 'challenge_id', 'text'),
		('leaderboard_scores', 'created_at', 'timestamp with time zone'),
		('mission_definitions', 'id', 'integer'),
		('mission_definitions', 'tier', 'text'),
		('mission_definitions', 'rule', 'text'),
		('mission_definitions', 'goal', 'integer'),
		('mission_definitions', 'goal_b', 'integer'),
		('mission_definitions', 'reward', 'integer'),
		('mission_definitions', 'enabled', 'boolean'),
		('daily_mission_sets', 'mission_date', 'date'),
		('daily_mission_sets', 'easy_id', 'integer'),
		('daily_mission_sets', 'medium_id', 'integer'),
		('daily_mission_sets', 'hard_id', 'integer'),
		('daily_mission_progress', 'player_id', 'uuid'),
		('daily_mission_progress', 'mission_date', 'date'),
		('daily_mission_progress', 'pipes_total', 'integer'),
		('daily_mission_progress', 'runs_completed', 'integer'),
		('daily_mission_progress', 'best_pipes', 'integer'),
		('daily_mission_progress', 'best_seconds', 'integer'),
		('daily_mission_progress', 'gameplay_coins', 'integer'),
		('daily_mission_progress', 'coin_runs', 'integer'),
		('daily_mission_progress', 'run_pipes', 'ARRAY'),
		('daily_mission_run_log', 'player_id', 'uuid'),
		('daily_mission_run_log', 'run_id', 'text'),
		('daily_mission_run_log', 'mission_date', 'date'),
		('daily_mission_run_log', 'pipes', 'integer'),
		('daily_mission_run_log', 'seconds', 'integer'),
		('daily_mission_run_log', 'gameplay_coins', 'integer'),
		('daily_mission_claims', 'player_id', 'uuid'),
		('daily_mission_claims', 'mission_date', 'date'),
		('daily_mission_claims', 'slot', 'text'),
		('daily_mission_claims', 'coins', 'integer'),
		('daily_mission_claims', 'mission_id', 'integer')
),
replaced_functions(signature) as (
	values
		('public.reefrun_publish_today()'),
		('public.get_leaderboard(text)'),
		('public.reefrun_daily_mission_board(uuid)'),
		('public.claim_daily_mission(text)'),
		('public.record_unlimited_mission_run(text,integer,integer,integer)'),
		('public.reefrun_mission_snapshot(text,integer,integer,integer,integer,integer,integer,integer,integer,integer[])')
),
dependencies(signature) as (
	values
		('public.reefrun_daily_seed(text,integer)'),
		('public.reefrun_count_at_least(integer[],integer)'),
		('public.reefrun_window_sum(integer[],integer)'),
		('auth.uid()')
),
client_functions(function_name) as (
	values
		('get_daily_missions'),
		('claim_daily_mission'),
		('record_unlimited_mission_run'),
		('get_leaderboard'),
		('get_daily_challenge'),
		('claim_daily_attempt'),
		('start_daily_attempt'),
		('get_daily_attempt_status'),
		('finalize_daily_attempt'),
		('submit_leaderboard_score')
),
follow_publish(function_name) as (
	values
		('claim_daily_attempt'),
		('get_daily_challenge'),
		('get_daily_attempt_status')
),
cap_checks as (
	select
		con.conrelid::regclass::text as table_name,
		con.conname,
		pg_get_constraintdef(con.oid) as definition,
		(
			pg_get_constraintdef(con.oid) ~ '<= 80\)'
			or pg_get_constraintdef(con.oid) ~ '<= 1800\)'
			or pg_get_constraintdef(con.oid) ~* 'between 0 and 80'
			or pg_get_constraintdef(con.oid) ~* 'between 0 and 1800'
		) as migration_will_drop
	from pg_constraint as con
	where con.contype = 'c'
		and con.conrelid = any (array[
			to_regclass('public.daily_mission_progress'),
			to_regclass('public.daily_mission_run_log')
		]::oid[])
		and (
			pg_get_constraintdef(con.oid) ~ '<= 80([^0-9]|$)'
			or pg_get_constraintdef(con.oid) ~ '<= 1800([^0-9]|$)'
			or pg_get_constraintdef(con.oid) ~* 'between 0 and 80([^0-9]|$)'
			or pg_get_constraintdef(con.oid) ~* 'between 0 and 1800([^0-9]|$)'
			or pg_get_constraintdef(con.oid) ~ '< 81([^0-9]|$)'
			or pg_get_constraintdef(con.oid) ~ '< 1801([^0-9]|$)'
		)
)
select check_name, status, detail
from (
	select
		'deployment_window' as check_name,
		case
			when utc_day is distinct from eastern_day then 'FAIL'
			when eastern_local::time < time '01:00' then 'REVIEW'
			when next_utc_midnight - pg_catalog.now() < interval '1 hour' then 'REVIEW'
			else 'PASS'
		end as status,
		format(
			'utc=%s eastern=%s eastern_local=%s utc_midnight_in=%s',
			utc_day,
			eastern_day,
			to_char(eastern_local, 'YYYY-MM-DD HH24:MI'),
			next_utc_midnight - pg_catalog.now()
		) as detail
	from clock

	union all
	select
		'required_table ' || table_name,
		case when to_regclass(table_name) is null then 'FAIL' else 'PASS' end,
		coalesce(to_regclass(table_name)::text, 'missing')
	from required_tables

	union all
	select
		'required_column ' || required_columns.table_name || '.' || required_columns.column_name,
		case
			when columns.data_type is null then 'FAIL'
			when columns.data_type is distinct from required_columns.type_name
				and not (required_columns.type_name = 'ARRAY' and columns.data_type = 'ARRAY')
				then 'FAIL'
			else 'PASS'
		end,
		coalesce(columns.data_type, 'missing')
	from required_columns
	left join information_schema.columns as columns
		on columns.table_schema = 'public'
		and columns.table_name = required_columns.table_name
		and columns.column_name = required_columns.column_name

	union all
	select
		'run_pipes_element_type',
		case
			when columns.udt_name is null then 'FAIL'
			when columns.udt_name <> '_int4' then 'FAIL'
			else 'PASS'
		end,
		coalesce(columns.udt_name, 'missing')
	from (select 1) as anchor
	left join information_schema.columns as columns
		on columns.table_schema = 'public'
		and columns.table_name = 'daily_mission_progress'
		and columns.column_name = 'run_pipes'

	union all
	select
		'dive_columns_absent_before_migration',
		case when count(*) = 0 then 'PASS' else 'REVIEW' end,
		'present=' || count(*)::text
	from information_schema.columns
	where table_schema = 'public'
		and (
			(table_name = 'daily_mission_progress' and column_name in (
				'dives_entered', 'dives_completed', 'best_dives', 'dive_seconds',
				'lane_changes', 'lanes_left', 'lanes_right',
				'obstacles_dodged', 'best_obstacles', 'mines_passed'
			))
			or (table_name = 'daily_mission_run_log' and column_name in (
				'dives_entered', 'dives_completed', 'dive_seconds',
				'lane_changes', 'lanes_left', 'lanes_right', 'obstacles', 'mines'
			))
		)

	union all
	select
		'pipe_and_survival_caps',
		case
			when exists (select 1 from cap_checks where not migration_will_drop) then 'FAIL'
			when (select count(*) from cap_checks where migration_will_drop) < 4 then 'REVIEW'
			else 'PASS'
		end,
		coalesce((
			select string_agg(
				format('%s %s drop=%s :: %s', table_name, conname, migration_will_drop, definition),
				' | ' order by table_name, conname
			)
			from cap_checks
		), 'no 80 or 1800 checks found')

	union all
	select
		'mission_definition_checks',
		'INFO',
		coalesce((
			select string_agg(format('%s :: %s', conname, pg_get_constraintdef(oid)), ' | ' order by conname)
			from pg_constraint
			where conrelid = to_regclass('public.mission_definitions')
				and contype = 'c'
		), 'mission_definitions missing')

	union all
	select
		'deep_dive_definitions',
		case
			when to_regclass('public.mission_definitions') is null then 'FAIL'
			when (
				select count(*)
				from public.mission_definitions
				where id >= 46
					or rule in (
						'dives_entered', 'dives_completed', 'dives_best', 'dive_seconds',
						'lanes_total', 'lanes_left', 'lanes_right',
						'obstacles_total', 'obstacles_best', 'mines_total'
					)
			) = 0 then 'PASS'
			else 'REVIEW'
		end,
		(
			select format(
				'definitions=%s ids_1_45=%s ids_46_90=%s dive_rules=%s rules=%s',
				count(*),
				count(*) filter (where id between 1 and 45),
				count(*) filter (where id between 46 and 90),
				count(*) filter (where rule in (
					'dives_entered', 'dives_completed', 'dives_best', 'dive_seconds',
					'lanes_total', 'lanes_left', 'lanes_right',
					'obstacles_total', 'obstacles_best', 'mines_total'
				)),
				coalesce(string_agg(distinct rule, ',' order by rule), '')
			)
			from public.mission_definitions
		)

	union all
	select
		'replaced_signature ' || signature,
		case when to_regprocedure(signature) is null then 'FAIL' else 'PASS' end,
		coalesce(to_regprocedure(signature)::text, 'missing')
	from replaced_functions

	union all
	select
		'twelve_argument_recorder_not_yet_present',
		case
			when to_regprocedure('public.record_unlimited_mission_run(text,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer)') is null
				then 'PASS'
			else 'REVIEW'
		end,
		coalesce(
			to_regprocedure('public.record_unlimited_mission_run(text,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer)')::text,
			'absent'
		)

	union all
	select
		'snapshot_overload_not_yet_present',
		case
			when to_regprocedure('public.reefrun_mission_snapshot(text,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer[])') is null
				then 'PASS'
			else 'REVIEW'
		end,
		'20-argument snapshot should be absent before the first migration'

	union all
	select
		'dependency ' || signature,
		case when to_regprocedure(signature) is null then 'FAIL' else 'PASS' end,
		coalesce(to_regprocedure(signature)::text, 'missing')
	from dependencies

	union all
	select
		'daily_challenges_pkey',
		case
			when exists (
				select 1
				from pg_constraint
				where conname = 'daily_challenges_pkey'
					and conrelid = to_regclass('public.daily_challenges')
					and contype = 'p'
			) then 'PASS'
			else 'FAIL'
		end,
		'publish uses on conflict on constraint daily_challenges_pkey'

	union all
	select
		'attempt_unique_player_challenge',
		case
			when exists (
				select 1
				from pg_constraint
				where conrelid = to_regclass('public.daily_attempts')
					and contype in ('u', 'p')
					and pg_get_constraintdef(oid) ilike '%player_id%'
					and pg_get_constraintdef(oid) ilike '%challenge_id%'
			) then 'PASS'
			else 'FAIL'
		end,
		coalesce((
			select string_agg(format('%s :: %s', conname, pg_get_constraintdef(oid)), ' | ' order by conname)
			from pg_constraint
			where conrelid = to_regclass('public.daily_attempts')
				and contype in ('u', 'p')
		), 'no unique or primary key found')

	union all
	select
		'client_execute ' || client_functions.function_name,
		case
			when count(functions.oid) = 0 then 'FAIL'
			when bool_and(has_function_privilege('authenticated', functions.oid, 'execute')) then 'PASS'
			else 'FAIL'
		end,
		format(
			'overloads=%s authenticated=%s anon=%s',
			count(functions.oid),
			coalesce(bool_or(has_function_privilege('authenticated', functions.oid, 'execute')), false),
			coalesce(bool_or(has_function_privilege('anon', functions.oid, 'execute')), false)
		)
	from client_functions
	left join pg_proc as functions
		on functions.proname = client_functions.function_name
		and functions.pronamespace = 'public'::regnamespace
	group by client_functions.function_name

	union all
	select
		'publish_follower ' || follow_publish.function_name,
		case
			when count(functions.oid) = 0 then 'FAIL'
			when bool_and(position('reefrun_publish_today' in pg_get_functiondef(functions.oid)) > 0) then 'PASS'
			else 'FAIL'
		end,
		format(
			'calls_publish=%s mentions_utc=%s mentions_new_york=%s',
			coalesce(bool_or(position('reefrun_publish_today' in pg_get_functiondef(functions.oid)) > 0), false),
			coalesce(bool_or(position('timezone(''utc''' in pg_get_functiondef(functions.oid)) > 0), false),
			coalesce(bool_or(position('America/New_York' in pg_get_functiondef(functions.oid)) > 0), false)
		)
	from follow_publish
	left join pg_proc as functions
		on functions.proname = follow_publish.function_name
		and functions.pronamespace = 'public'::regnamespace
	group by follow_publish.function_name

	union all
	select
		'helper_date_source ' || functions.proname || '(' || pg_get_function_identity_arguments(functions.oid) || ')',
		'REVIEW',
		format(
			'mentions_utc=%s mentions_new_york=%s calls_publish=%s security_definer=%s search_path=%s',
			position('timezone(''utc''' in pg_get_functiondef(functions.oid)) > 0,
			position('America/New_York' in pg_get_functiondef(functions.oid)) > 0,
			position('reefrun_publish_today' in pg_get_functiondef(functions.oid)) > 0,
			functions.prosecdef,
			coalesce(array_to_string(functions.proconfig, ','), '')
		)
	from pg_proc as functions
	where functions.pronamespace = 'public'::regnamespace
		and functions.proname in (
			'reefrun_publish_today',
			'get_leaderboard',
			'submit_leaderboard_score',
			'finalize_daily_attempt',
			'reefrun_ensure_daily_mission_set',
			'reefrun_mission_snapshot',
			'reefrun_daily_mission_board',
			'claim_daily_mission',
			'record_unlimited_mission_run',
			'start_daily_attempt'
		)

	union all
	select
		'function_fingerprint ' || functions.proname || '(' || pg_get_function_identity_arguments(functions.oid) || ')',
		'INFO',
		md5(pg_get_functiondef(functions.oid))
	from pg_proc as functions
	where functions.pronamespace = 'public'::regnamespace
		and functions.proname in (
			'reefrun_publish_today',
			'get_leaderboard',
			'submit_leaderboard_score',
			'finalize_daily_attempt',
			'reefrun_ensure_daily_mission_set',
			'reefrun_mission_snapshot',
			'reefrun_daily_mission_board',
			'claim_daily_mission',
			'record_unlimited_mission_run',
			'get_daily_missions',
			'claim_daily_attempt',
			'start_daily_attempt',
			'get_daily_attempt_status',
			'get_daily_challenge'
		)

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

	union all
	select
		'row_level_security ' || cls.relname,
		'INFO',
		format('enabled=%s forced=%s', cls.relrowsecurity, cls.relforcerowsecurity)
	from pg_class as cls
	join pg_namespace as namespace on namespace.oid = cls.relnamespace
	where namespace.nspname = 'public'
		and cls.relname in (
			'profiles', 'daily_challenges', 'daily_attempts', 'leaderboard_scores',
			'mission_definitions', 'daily_mission_sets', 'daily_mission_progress',
			'daily_mission_run_log', 'daily_mission_claims'
		)

	union all
	select
		'installed_extensions',
		'INFO',
		coalesce((
			select string_agg(extname || ' ' || extversion, ', ' order by extname)
			from pg_extension
		), 'none')
) as results
order by
	case status when 'FAIL' then 0 when 'REVIEW' then 1 when 'INFO' then 3 else 2 end,
	check_name;
