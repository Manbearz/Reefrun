-- Disposable-database checks only. Never run this against production.
-- Test definitions 9001-9011 are inserted inside a transaction and rolled back.

do $classic$
declare
	board jsonb;
	slot jsonb;
	snap jsonb;
	pipes integer;
	runs integer;
	best_pipes integer;
	best_seconds integer;
	coins integer;
	coin_runs integer;
	samples integer[];
	dives integer;
	wallet integer;
	attempts integer;
begin
	select progress.pipes_total, progress.runs_completed, progress.best_pipes, progress.best_seconds,
		progress.gameplay_coins, progress.coin_runs, progress.run_pipes, progress.dives_entered
	into pipes, runs, best_pipes, best_seconds, coins, coin_runs, samples, dives
	from public.daily_mission_progress as progress
	where progress.player_id = '33333333-3333-3333-3333-333333333333';
	if pipes is distinct from 5102 or runs is distinct from 4 or best_pipes is distinct from 5000
		or dives is distinct from 166 then
		raise exception 'long-run totals pipes=% runs=% best=% dives=%', pipes, runs, best_pipes, dives;
	end if;

	perform set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
	board := public.get_daily_missions();
	if board ->> 'ok' is distinct from 'true'
		or (board ->> 'mission_date')::date is distinct from (timezone('America/New_York', now()))::date then
		raise exception 'pipe board date failed: %', board;
	end if;
	for slot in select value from jsonb_array_elements(board -> 'slots') loop
		if (slot ->> 'mission_id')::integer = 1
			and ((slot ->> 'progress')::integer is distinct from 5102
				or (slot ->> 'complete')::boolean is distinct from true
				or (slot ->> 'goal')::integer is distinct from 10
				or (slot ->> 'reward')::integer is distinct from 5) then
			raise exception 'pipes_total easy card failed: %', slot;
		end if;
		if (slot ->> 'mission_id')::integer = 16
			and ((slot ->> 'complete')::boolean is distinct from true
				or (slot ->> 'reward')::integer is distinct from 10) then
			raise exception 'pipes_total medium card failed: %', slot;
		end if;
		if (slot ->> 'mission_id')::integer = 31
			and ((slot ->> 'complete')::boolean is distinct from true
				or (slot ->> 'reward')::integer is distinct from 20) then
			raise exception 'pipes_total hard card failed: %', slot;
		end if;
	end loop;

	snap := public.reefrun_mission_snapshot(
		'survive_best', 120, 0, pipes, runs, best_pipes, best_seconds, coins, coin_runs,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, samples
	);
	if (snap ->> 'complete')::boolean is distinct from true or (snap ->> 'progress')::integer is distinct from best_seconds then
		raise exception 'survive_best failed: %', snap;
	end if;
	snap := public.reefrun_mission_snapshot(
		'coins_total', 50, 0, pipes, runs, best_pipes, best_seconds, coins, coin_runs,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, samples
	);
	if (snap ->> 'complete')::boolean is distinct from true or (snap ->> 'progress')::integer is distinct from coins then
		raise exception 'coins_total failed: %', snap;
	end if;
	snap := public.reefrun_mission_snapshot(
		'runs', 3, 0, pipes, runs, best_pipes, best_seconds, coins, coin_runs,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, samples
	);
	if (snap ->> 'complete')::boolean is distinct from true or (snap ->> 'progress')::integer is distinct from 4 then
		raise exception 'runs failed: %', snap;
	end if;
	snap := public.reefrun_mission_snapshot(
		'coin_runs', 3, 0, pipes, runs, best_pipes, best_seconds, coins, coin_runs,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, samples
	);
	if (snap ->> 'complete')::boolean is distinct from true or (snap ->> 'progress')::integer is distinct from coin_runs then
		raise exception 'coin_runs failed: %', snap;
	end if;
	snap := public.reefrun_mission_snapshot(
		'runs_at_least', 10, 3, pipes, runs, best_pipes, best_seconds, coins, coin_runs,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, samples
	);
	if (snap ->> 'complete')::boolean is distinct from true or (snap ->> 'goal')::integer is distinct from 3 then
		raise exception 'runs_at_least failed: %', snap;
	end if;
	snap := public.reefrun_mission_snapshot(
		'window_sum', 50, 3, pipes, runs, best_pipes, best_seconds, coins, coin_runs,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, samples
	);
	if (snap ->> 'complete')::boolean is distinct from true or (snap ->> 'progress')::integer < 5000 then
		raise exception 'window_sum failed: %', snap;
	end if;
	snap := public.reefrun_mission_snapshot(
		'pipes_best', 5000, 0, pipes, runs, best_pipes, best_seconds, coins, coin_runs,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, samples
	);
	if (snap ->> 'complete')::boolean is distinct from true then
		raise exception 'pipes_best failed: %', snap;
	end if;
	snap := public.reefrun_mission_snapshot(
		'dives_entered', 1, 0, pipes, runs, best_pipes, best_seconds, coins, coin_runs,
		dives, 166, 166, 3320, 0, 0, 0, 0, 0, 0, samples
	);
	if (snap ->> 'progress')::integer is distinct from 166 or (snap ->> 'complete')::boolean is distinct from true then
		raise exception 'stored dive score failed: %', snap;
	end if;
	snap := public.reefrun_mission_snapshot(
		'dives_entered', 1, 0, 0, 0, 0, 0, 0, 0, array[]::integer[]
	);
	if (snap ->> 'progress')::integer is distinct from 0 or (snap ->> 'complete')::boolean is distinct from false then
		raise exception 'old snapshot overload scored a dive rule: %', snap;
	end if;

	board := public.claim_daily_mission('easy');
	if (board ->> 'granted_now')::integer is distinct from 5 or board ->> 'reason' is distinct from 'claimed' then
		raise exception 'easy pipe claim failed: %', board ->> 'reason';
	end if;
	board := public.claim_daily_mission('easy');
	if (board ->> 'granted_now')::integer is distinct from 0 or board ->> 'reason' is distinct from 'already' then
		raise exception 'duplicate easy claim was %', board ->> 'reason';
	end if;
	board := public.claim_daily_mission('medium');
	if (board ->> 'granted_now')::integer is distinct from 10 then
		raise exception 'medium claim granted %', board ->> 'granted_now';
	end if;
	board := public.claim_daily_mission('hard');
	if (board ->> 'granted_now')::integer is distinct from 20 then
		raise exception 'hard claim granted %', board ->> 'granted_now';
	end if;
	board := public.claim_daily_mission('bonus');
	if (board ->> 'granted_now')::integer is distinct from 25 or board ->> 'reason' is distinct from 'claimed' then
		raise exception 'bonus claim failed: %', board ->> 'reason';
	end if;
	board := public.claim_daily_mission('bonus');
	if (board ->> 'granted_now')::integer is distinct from 0 or board ->> 'reason' is distinct from 'cap' then
		raise exception 'second bonus was %', board ->> 'reason';
	end if;
	select mission_reward_coins into wallet
	from public.profiles
	where id = '33333333-3333-3333-3333-333333333333';
	if wallet is distinct from 60 then
		raise exception 'pipe reward wallet is %', wallet;
	end if;
	select mission_reward_coins, pipes_total into wallet, pipes
	from public.profiles as profile
	join public.daily_mission_progress as progress
		on progress.player_id = profile.id
	where profile.id = '44444444-4444-4444-4444-444444444444';
	if wallet is distinct from 60 or pipes is distinct from 200 then
		raise exception 'other player changed wallet=% pipes=%', wallet, pipes;
	end if;

	select count(*) into attempts
	from public.daily_attempts
	where player_id = '11111111-1111-1111-1111-111111111111';
	if attempts is distinct from 1 then
		raise exception 'used attempt count %', attempts;
	end if;
	if (select score from public.leaderboard_scores where period_key = '1999-01-01') is distinct from 99 then
		raise exception 'historical daily score changed';
	end if;
	raise notice 'classic missions, claims, and preserved rows passed';
end
$classic$;

do $attempts$
declare
	row record;
	attempts integer;
begin
	perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
	select * into row from public.claim_daily_attempt('ffffffff-ffff-ffff-ffff-ffffffffffff');
	if row.already_used is distinct from true or row.claimed is distinct from false then
		raise exception 'used player received another attempt';
	end if;
	perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
	select * into row from public.claim_daily_attempt('99999999-9999-9999-9999-999999999999');
	if row.already_used is distinct from true or row.claimed is distinct from false then
		raise exception 'started player received another attempt';
	end if;
	select count(*) into attempts from public.daily_attempts
	where player_id in (
		'11111111-1111-1111-1111-111111111111',
		'22222222-2222-2222-2222-222222222222'
	);
	if attempts is distinct from 2 then
		raise exception 'attempt rows became %', attempts;
	end if;
	raise notice 'existing attempts stayed single';
end
$attempts$;

do $runs$
declare
	board jsonb;
	total integer;
	wallet integer;
	other integer;
begin
	perform set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-777777777777', false);
	board := public.record_unlimited_mission_run('p0pipes0', 0, 0, 0);
	if board ->> 'reason' is distinct from 'recorded' then
		raise exception '0 pipes rejected: %', board ->> 'reason';
	end if;
	board := public.record_unlimited_mission_run('p30pipes', 30, 60, 6);
	if board ->> 'reason' is distinct from 'recorded' then
		raise exception '30 pipes rejected: %', board ->> 'reason';
	end if;
	board := public.record_unlimited_mission_run('p30pipes', 30, 60, 6);
	if board ->> 'reason' is distinct from 'duplicate' then
		raise exception 'duplicate 30-pipe run was %', board ->> 'reason';
	end if;
	board := public.record_unlimited_mission_run('p80pipes', 80, 500, 16);
	if board ->> 'reason' is distinct from 'recorded' then
		raise exception '80 pipes rejected: %', board ->> 'reason';
	end if;
	board := public.record_unlimited_mission_run('p81pipes', 81, 100, 16, 0, 0, 0, 0, 0, 0, 0, 0);
	if board ->> 'reason' is distinct from 'recorded' then
		raise exception '81 pipes rejected: %', board ->> 'reason';
	end if;
	board := public.record_unlimited_mission_run('p100pipe', 100, 200, 20, 0, 0, 0, 0, 0, 0, 0, 0);
	if board ->> 'reason' is distinct from 'recorded' then
		raise exception '100 pipes rejected: %', board ->> 'reason';
	end if;
	board := public.record_unlimited_mission_run('p500pipe', 500, 1000, 100, 0, 0, 0, 0, 0, 0, 0, 0);
	if board ->> 'reason' is distinct from 'recorded' then
		raise exception '500 pipes rejected: %', board ->> 'reason';
	end if;
	board := public.record_unlimited_mission_run('p1000pip', 1000, 2000, 200, 0, 0, 0, 0, 0, 0, 0, 0);
	if board ->> 'reason' is distinct from 'recorded' then
		raise exception '1000 pipes rejected: %', board ->> 'reason';
	end if;
	board := public.record_unlimited_mission_run('p5000pip', 5000, 10000, 1000, 0, 0, 0, 0, 0, 0, 0, 0);
	if board ->> 'reason' is distinct from 'recorded' then
		raise exception '5000 pipes without dives rejected: %', board ->> 'reason';
	end if;
	select pipes_total, gameplay_coins into total, wallet
	from public.daily_mission_progress
	where player_id = '77777777-7777-7777-7777-777777777777';
	if total is distinct from 6791 or wallet is distinct from 1358 then
		raise exception 'pipe ladder pipes=% coins=%', total, wallet;
	end if;

	board := public.record_unlimited_mission_run('badfast1', 5000, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0);
	board := public.record_unlimited_mission_run('badcap001', 20001, 30000, 0, 0, 0, 0, 0, 0, 0, 0, 0);
	board := public.record_unlimited_mission_run('badmines1', 60, 180, 0, 2, 2, 40, 10, 4, 6, 3, 4);
	board := public.record_unlimited_mission_run('badlanes1', 60, 180, 0, 2, 2, 40, 10, 4, 5, 8, 3);
	board := public.record_unlimited_mission_run('baddive01', 10, 40, 0, 1, 1, 20, 0, 0, 0, 0, 0);
	board := public.record_unlimited_mission_run('badneg001', -1, 0, 0);
	if board ->> 'reason' is distinct from 'rejected' then
		raise exception 'invalid run was %', board ->> 'reason';
	end if;
	select pipes_total into total
	from public.daily_mission_progress
	where player_id = '77777777-7777-7777-7777-777777777777';
	if total is distinct from 6791 then
		raise exception 'invalid run changed pipes to %', total;
	end if;
	select pipes_total into other
	from public.daily_mission_progress
	where player_id = '33333333-3333-3333-3333-333333333333';
	if other is distinct from 5102 then
		raise exception 'cross-player pipes changed to %', other;
	end if;
	perform set_config('request.jwt.claim.sub', '', false);
	board := public.record_unlimited_mission_run('noauth001', 10, 20, 0);
	if board ->> 'reason' is distinct from 'not_authenticated' then
		raise exception 'anonymous run was %', board ->> 'reason';
	end if;
	raise notice 'pipe ladder and invalid submissions passed';
end
$runs$;

begin;

do $widen$
declare
	r record;
begin
	for r in
		select conname
		from pg_constraint
		where conrelid = 'public.mission_definitions'::regclass
			and contype = 'c'
			and (
				pg_get_constraintdef(oid) ~ '<= 45\)'
				or pg_get_constraintdef(oid) like '%pipes_total%'
			)
	loop
		execute format('alter table public.mission_definitions drop constraint %I', r.conname);
	end loop;
end
$widen$;

insert into public.mission_definitions (id, tier, family, description, reward, rule, goal, goal_b, enabled)
values
	(9001, 'easy', 'test_dive', 'Test enter dives.', 5, 'dives_entered', 2, 0, true),
	(9002, 'medium', 'test_dive', 'Test finish dives.', 10, 'dives_completed', 2, 0, true),
	(9003, 'hard', 'test_dive', 'Test best finishes.', 20, 'dives_best', 2, 0, true),
	(9004, 'easy', 'test_dive', 'Test dive time.', 5, 'dive_seconds', 40, 0, true),
	(9005, 'medium', 'test_dive', 'Test lane changes.', 10, 'lanes_total', 10, 0, true),
	(9006, 'hard', 'test_dive', 'Test left lanes.', 20, 'lanes_left', 4, 0, true),
	(9007, 'easy', 'test_dive', 'Test right lanes.', 5, 'lanes_right', 6, 0, true),
	(9008, 'medium', 'test_dive', 'Test obstacles.', 10, 'obstacles_total', 8, 0, true),
	(9009, 'hard', 'test_dive', 'Test best obstacles.', 20, 'obstacles_best', 8, 0, true),
	(9010, 'easy', 'test_dive', 'Test mines.', 5, 'mines_total', 3, 0, true),
	(9011, 'hard', 'test_dive', 'Test unfinished mines.', 20, 'mines_total', 99, 0, true);

delete from public.daily_mission_sets
where mission_date = (timezone('America/New_York', now()))::date;

insert into public.daily_mission_sets (mission_date, easy_id, medium_id, hard_id)
values ((timezone('America/New_York', now()))::date, 9001, 9002, 9003);

select set_config('request.jwt.claim.sub', '88888888-8888-8888-8888-888888888888', false);

do $before$
declare
	board jsonb;
	slot jsonb;
begin
	board := public.get_daily_missions();
	if board ->> 'ok' is distinct from 'true' then
		raise exception 'empty dive board failed: %', board;
	end if;
	for slot in select value from jsonb_array_elements(board -> 'slots') loop
		if (slot ->> 'progress')::integer is distinct from 0
			or (slot ->> 'complete')::boolean is distinct from false then
			raise exception 'dive card started complete: %', slot;
		end if;
	end loop;
	board := public.claim_daily_mission('easy');
	if board ->> 'reason' is distinct from 'incomplete' or (board ->> 'granted_now')::integer is distinct from 0 then
		raise exception 'incomplete dive claim was %', board ->> 'reason';
	end if;
end
$before$;

do $record$
declare
	board jsonb;
begin
	board := public.record_unlimited_mission_run(
		'diveall01', 60, 180, 12,
		2, 2, 40, 10, 4, 6, 8, 3
	);
	if board ->> 'reason' is distinct from 'recorded' then
		raise exception 'representative dive run rejected: %', board ->> 'reason';
	end if;
	board := public.record_unlimited_mission_run(
		'diveall01', 60, 180, 12,
		2, 2, 40, 10, 4, 6, 8, 3
	);
	if board ->> 'reason' is distinct from 'duplicate' then
		raise exception 'duplicate dive run was %', board ->> 'reason';
	end if;
end
$record$;

do $groups$
declare
	today date := (timezone('America/New_York', now()))::date;
	board jsonb;
	slot jsonb;
	expected jsonb := '[
		{"id": 9001, "progress": 2, "goal": 2, "complete": true, "reward": 5},
		{"id": 9002, "progress": 2, "goal": 2, "complete": true, "reward": 10},
		{"id": 9003, "progress": 2, "goal": 2, "complete": true, "reward": 20},
		{"id": 9004, "progress": 40, "goal": 40, "complete": true, "reward": 5},
		{"id": 9005, "progress": 10, "goal": 10, "complete": true, "reward": 10},
		{"id": 9006, "progress": 4, "goal": 4, "complete": true, "reward": 20},
		{"id": 9007, "progress": 6, "goal": 6, "complete": true, "reward": 5},
		{"id": 9008, "progress": 8, "goal": 8, "complete": true, "reward": 10},
		{"id": 9009, "progress": 8, "goal": 8, "complete": true, "reward": 20},
		{"id": 9010, "progress": 3, "goal": 3, "complete": true, "reward": 5},
		{"id": 9011, "progress": 3, "goal": 99, "complete": false, "reward": 10}
	]'::jsonb;
	groups integer[][] := array[
		array[9001, 9002, 9003],
		array[9004, 9005, 9006],
		array[9007, 9008, 9009],
		array[9010, 9011, 9003]
	];
	grp integer[];
	want jsonb;
	seen integer;
begin
	foreach grp slice 1 in array groups loop
		delete from public.daily_mission_sets where mission_date = today;
		insert into public.daily_mission_sets (mission_date, easy_id, medium_id, hard_id)
		values (today, grp[1], grp[2], grp[3]);
		board := public.get_daily_missions();
		seen := 0;
		for slot in select value from jsonb_array_elements(board -> 'slots') loop
			select value into want
			from jsonb_array_elements(expected) as value
			where (value ->> 'id')::integer = (slot ->> 'mission_id')::integer;
			if want is null
				or (slot ->> 'progress')::integer is distinct from (want ->> 'progress')::integer
				or (slot ->> 'goal')::integer is distinct from (want ->> 'goal')::integer
				or (slot ->> 'complete')::boolean is distinct from (want ->> 'complete')::boolean
				or (slot ->> 'reward')::integer is distinct from (want ->> 'reward')::integer then
				raise exception 'dive card mismatch: %', slot;
			end if;
			seen := seen + 1;
		end loop;
		if seen is distinct from 3 then
			raise exception 'dive board returned % cards', seen;
		end if;
	end loop;

	delete from public.daily_mission_sets where mission_date = today;
	insert into public.daily_mission_sets (mission_date, easy_id, medium_id, hard_id)
	values (today, 9001, 9002, 9003);
	board := public.claim_daily_mission('easy');
	if (board ->> 'granted_now')::integer is distinct from 5 or board ->> 'reason' is distinct from 'claimed' then
		raise exception 'dive easy claim failed: %', board ->> 'reason';
	end if;
	board := public.claim_daily_mission('medium');
	if (board ->> 'granted_now')::integer is distinct from 10 then
		raise exception 'dive medium claim granted %', board ->> 'granted_now';
	end if;
	board := public.claim_daily_mission('hard');
	if (board ->> 'granted_now')::integer is distinct from 20 then
		raise exception 'dive hard claim granted %', board ->> 'granted_now';
	end if;
	board := public.claim_daily_mission('easy');
	if (board ->> 'granted_now')::integer is distinct from 0 or board ->> 'reason' is distinct from 'already' then
		raise exception 'duplicate dive claim was %', board ->> 'reason';
	end if;
	board := public.claim_daily_mission('bonus');
	if (board ->> 'granted_now')::integer is distinct from 25 then
		raise exception 'dive bonus granted %', board ->> 'granted_now';
	end if;
	if (select mission_reward_coins from public.profiles where id = '88888888-8888-8888-8888-888888888888')
		is distinct from 60 then
		raise exception 'dive wallet was not 60';
	end if;
	if (select dives_entered from public.daily_mission_progress where player_id = '88888888-8888-8888-8888-888888888888')
		is distinct from 2 then
		raise exception 'duplicate dive run changed entered count';
	end if;
	raise notice 'deep dive board, thresholds, and claims passed';
end
$groups$;

rollback;

do $after$
declare
	easy integer;
	medium integer;
	hard integer;
	definitions integer;
	wallet integer;
begin
	select count(*) into definitions from public.mission_definitions where id >= 9000;
	select easy_id, medium_id, hard_id into easy, medium, hard
	from public.daily_mission_sets
	where mission_date = (timezone('America/New_York', now()))::date;
	select mission_reward_coins into wallet
	from public.profiles
	where id = '44444444-4444-4444-4444-444444444444';
	if definitions is distinct from 0 or easy is distinct from 1
		or medium is distinct from 16 or hard is distinct from 31 or wallet is distinct from 60 then
		raise exception 'rollback leaked defs=% set=%/%/% wallet=%', definitions, easy, medium, hard, wallet;
	end if;
	if has_function_privilege('anon', 'public.claim_daily_mission(text)', 'execute')
		or has_function_privilege('anon', 'public.get_leaderboard(text)', 'execute')
		or has_function_privilege('authenticated', 'public.reefrun_daily_mission_board(uuid)', 'execute')
		or has_function_privilege(
			'authenticated',
			'public.reefrun_mission_snapshot(text,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer,integer[])',
			'execute'
		) then
		raise exception 'a private helper or anon entry point is executable';
	end if;
	if not has_function_privilege('authenticated', 'public.get_daily_missions()', 'execute')
		or not has_function_privilege('authenticated', 'public.claim_daily_mission(text)', 'execute')
		or not has_function_privilege('authenticated', 'public.get_leaderboard(text)', 'execute') then
		raise exception 'authenticated lost a client entry point';
	end if;
	if (
		select count(*) from pg_constraint
		where conrelid in (
			'public.daily_mission_run_log'::regclass,
			'public.daily_mission_progress'::regclass
		)
			and pg_get_constraintdef(oid) ~ '<= 20000\)|<= 86400\)'
	) is distinct from 4 then
		raise exception 'long-run checks are missing';
	end if;
	raise notice 'dive transaction rolled back and privileges held';
end
$after$;
