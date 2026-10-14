-- ReefRun preflight. Read-only.
-- Supabase Dashboard → SQL Editor → New query → paste this file → Run.
-- Run this before tools/supabase/daily_attempt.sql.
-- Selects catalog data and score counts only.
-- Does not create, alter, drop, insert, update, delete, grant, or revoke.

select section, item, detail
from (
	select 10 as sort_key, 'server'::text as section, 'version'::text as item,
		current_setting('server_version') as detail

	union all
	select 20, 'expected_table', name,
		case
			when to_regclass('public.' || name) is null then 'absent'
			else 'present'
		end
	from (
		values
			('profiles'),
			('leaderboard_scores'),
			('daily_challenges'),
			('daily_attempts'),
			('ghost_runs')
	) as expected(name)

	union all
	select 30, 'expected_column', table_name || '.' || column_name,
		case
			when exists (
				select 1
				from information_schema.columns as c
				where c.table_schema = 'public'
					and c.table_name = expected.table_name
					and c.column_name = expected.column_name
			) then 'present'
			else 'absent'
		end
	from (
		values
			('leaderboard_scores', 'challenge_id'),
			('ghost_runs', 'challenge_id')
	) as expected(table_name, column_name)

	union all
	select 40, 'column', c.table_name || '.' || c.column_name,
		c.data_type
			|| ' nullable=' || c.is_nullable
			|| ' default=' || coalesce(c.column_default, '(none)')
	from information_schema.columns as c
	where c.table_schema = 'public'
		and c.table_name in ('profiles', 'leaderboard_scores', 'daily_challenges', 'daily_attempts', 'ghost_runs')

	union all
	select 50, 'required_input', c.table_name || '.' || c.column_name,
		c.data_type || ' is not null and has no default'
	from information_schema.columns as c
	where c.table_schema = 'public'
		and c.table_name in ('profiles', 'leaderboard_scores')
		and c.is_nullable = 'NO'
		and c.column_default is null

	union all
	select 60, 'constraint', t.relname || '.' || con.conname,
		con.contype || ' ' || pg_catalog.pg_get_constraintdef(con.oid)
	from pg_catalog.pg_constraint as con
	join pg_catalog.pg_class as t on t.oid = con.conrelid
	join pg_catalog.pg_namespace as n on n.oid = t.relnamespace
	where n.nspname = 'public'
		and t.relname in ('profiles', 'leaderboard_scores', 'daily_challenges', 'daily_attempts')

	union all
	select 70, 'index', t.relname || '.' || ix.relname,
		case when i.indisunique then 'unique ' else '' end
			|| case when i.indpred is not null then 'partial ' else 'nonpartial ' end
			|| pg_catalog.pg_get_indexdef(i.indexrelid)
	from pg_catalog.pg_index as i
	join pg_catalog.pg_class as t on t.oid = i.indrelid
	join pg_catalog.pg_class as ix on ix.oid = i.indexrelid
	join pg_catalog.pg_namespace as n on n.oid = t.relnamespace
	where n.nspname = 'public'
		and t.relname in ('profiles', 'leaderboard_scores', 'daily_challenges', 'daily_attempts', 'ghost_runs')

	union all
	select 80, 'expected_function', name,
		case
			when exists (
				select 1
				from pg_catalog.pg_proc as p
				join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
				where n.nspname = 'public'
					and p.proname = expected.name
			) then 'present'
			else 'absent'
		end
	from (
		values
			('get_leaderboard'),
			('submit_leaderboard_score'),
			('submit_challenge_score'),
			('claim_daily_attempt'),
			('start_daily_attempt'),
			('finalize_daily_attempt'),
			('get_daily_attempt_status'),
			('get_daily_challenge'),
			('reefrun_publish_today'),
			('reefrun_daily_seed')
	) as expected(name)

	union all
	select 90, 'function', p.proname || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')',
		pg_catalog.pg_get_function_result(p.oid)
			|| case when p.prosecdef then ' security_definer' else ' invoker' end
	from pg_catalog.pg_proc as p
	join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
	where n.nspname = 'public'
		and p.proname in (
			'get_leaderboard',
			'submit_leaderboard_score',
			'submit_challenge_score',
			'claim_daily_attempt',
			'start_daily_attempt',
			'finalize_daily_attempt',
			'get_daily_attempt_status',
			'get_daily_challenge',
			'reefrun_publish_today',
			'reefrun_daily_seed'
		)

	union all
	select 100, 'execute_grant', p.proname || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')',
		r.rolname
	from pg_catalog.pg_proc as p
	join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
	cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) as acl
	join pg_catalog.pg_roles as r on r.oid = acl.grantee
	where n.nspname = 'public'
		and p.proname in (
			'get_leaderboard',
			'submit_leaderboard_score',
			'submit_challenge_score',
			'claim_daily_attempt',
			'start_daily_attempt',
			'finalize_daily_attempt',
			'get_daily_attempt_status',
			'get_daily_challenge'
		)
		and acl.privilege_type = 'EXECUTE'

	union all
	select 110, 'score_bucket', period || ' ' || period_key, count(*)::text
	from public.leaderboard_scores
	group by period, period_key

	union all
	select 120, 'unexpected_period', coalesce(period, '(null)'), count(*)::text
	from public.leaderboard_scores
	where period is null
		or period not in ('daily', 'weekly', 'monthly')
	group by period

	union all
	select 130, 'duplicate_groups', 'leaderboard_scores (player_id, period, period_key)', count(*)::text
	from (
		select 1
		from public.leaderboard_scores
		group by player_id, period, period_key
		having count(*) > 1
	) as duplicate_groups
) as report
order by sort_key, section, item;
