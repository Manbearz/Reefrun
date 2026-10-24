-- Deep Dive mission definitions 46-90.
-- DO NOT RUN against production until this file is approved.
--
-- The Eastern daily-reset migration is already applied. This file does not
-- replace those functions, add progress columns, or edit missions 1-45.
-- It only widens the two mission-definition checks and inserts the new rows.
-- Existing daily_mission_sets rows stay as they are. The picker includes
-- these missions on the next date that does not already have a set.
--
-- A completed dive lasts 20 seconds. Dives start at pipe 30 and repeat
-- every 30 pipes, and only Unlimited Mode records them. The first dive has
-- no mines. Mission 85 asks for 80 seconds, four full dives, so it stays
-- harder than the 60-second medium mission.

alter table public.mission_definitions
	drop constraint if exists mission_definitions_id_check;
alter table public.mission_definitions
	drop constraint if exists mission_definitions_rule_check;

alter table public.mission_definitions
	add constraint mission_definitions_id_check check (id >= 1 and id <= 90);

alter table public.mission_definitions
	add constraint mission_definitions_rule_check check (rule = any (array[
		'pipes_total'::text, 'pipes_best'::text, 'runs'::text, 'survive_best'::text,
		'coins_total'::text, 'coin_runs'::text, 'runs_at_least'::text, 'window_sum'::text,
		'dives_entered'::text, 'dives_completed'::text, 'dives_best'::text, 'dive_seconds'::text,
		'lanes_total'::text, 'lanes_left'::text, 'lanes_right'::text,
		'obstacles_total'::text, 'obstacles_best'::text, 'mines_total'::text
	]));

insert into public.mission_definitions (id, tier, family, description, reward, rule, goal, goal_b, enabled)
values
	(46, 'easy', 'dive_enter', 'Deep Diver: enter a dive.', 5, 'dives_entered', 1, 0, true),
	(47, 'easy', 'dive_lanes', 'First Splash: switch lanes 10 times.', 5, 'lanes_total', 10, 0, true),
	(48, 'easy', 'dive_time', 'Into the Abyss: spend 20 seconds diving.', 5, 'dive_seconds', 20, 0, true),
	(49, 'easy', 'dive_left', 'Side Stepper: move left 10 times.', 5, 'lanes_left', 10, 0, true),
	(50, 'easy', 'dive_enter', 'Deep Traveler: enter 2 dives.', 5, 'dives_entered', 2, 0, true),
	(51, 'easy', 'dive_dodge', 'Quick Fins: dodge 5 obstacles.', 5, 'obstacles_total', 5, 0, true),
	(52, 'easy', 'dive_right', 'Right Turn: move right 10 times.', 5, 'lanes_right', 10, 0, true),
	(53, 'easy', 'dive_time', 'Warm Up: spend 10 seconds diving.', 5, 'dive_seconds', 10, 0, true),
	(54, 'easy', 'dive_dodge', 'Light Dodge: dodge 3 obstacles.', 5, 'obstacles_total', 3, 0, true),
	(55, 'easy', 'dive_complete', 'Surface: finish a dive.', 5, 'dives_completed', 1, 0, true),
	(56, 'easy', 'dive_lanes', 'Little Nudge: switch lanes 5 times.', 5, 'lanes_total', 5, 0, true),
	(57, 'easy', 'dive_left', 'Port Side: move left 5 times.', 5, 'lanes_left', 5, 0, true),
	(58, 'easy', 'dive_right', 'Starboard: move right 5 times.', 5, 'lanes_right', 5, 0, true),
	(59, 'easy', 'dive_dodge', 'Clear Path: dodge 8 obstacles.', 5, 'obstacles_total', 8, 0, true),
	(60, 'easy', 'dive_time', 'Hold Breath: spend 15 seconds diving.', 5, 'dive_seconds', 15, 0, true),
	(61, 'medium', 'dive_dodge', 'Close Call: dodge 15 obstacles.', 10, 'obstacles_total', 15, 0, true),
	(62, 'medium', 'dive_enter', 'Deep Explorer: enter 3 dives.', 10, 'dives_entered', 3, 0, true),
	(63, 'medium', 'dive_dodge', 'Slippery Fish: dodge 30 obstacles.', 10, 'obstacles_total', 30, 0, true),
	(64, 'medium', 'dive_lanes', 'Ocean Navigator: switch lanes 30 times.', 10, 'lanes_total', 30, 0, true),
	(65, 'medium', 'dive_complete', 'Deep Survivor: finish 2 dives.', 10, 'dives_completed', 2, 0, true),
	(66, 'medium', 'dive_mines', 'Mine Dodger: pass 5 mines.', 10, 'mines_total', 5, 0, true),
	(67, 'medium', 'dive_time', 'Deep Breath: spend 40 seconds diving.', 10, 'dive_seconds', 40, 0, true),
	(68, 'medium', 'dive_left', 'Left Current: move left 20 times.', 10, 'lanes_left', 20, 0, true),
	(69, 'medium', 'dive_right', 'Right Current: move right 20 times.', 10, 'lanes_right', 20, 0, true),
	(70, 'medium', 'dive_enter', 'Return Trip: enter 4 dives.', 10, 'dives_entered', 4, 0, true),
	(71, 'medium', 'dive_dodge', 'Steady Weave: dodge 20 obstacles.', 10, 'obstacles_total', 20, 0, true),
	(72, 'medium', 'dive_mines', 'Mine Watch: pass 3 mines.', 10, 'mines_total', 3, 0, true),
	(73, 'medium', 'dive_lanes', 'Lane Hopper: switch lanes 20 times.', 10, 'lanes_total', 20, 0, true),
	(74, 'medium', 'dive_time', 'One Minute: spend 60 seconds diving.', 10, 'dive_seconds', 60, 0, true),
	(75, 'medium', 'dive_mines', 'Mine Line: pass 8 mines.', 10, 'mines_total', 8, 0, true),
	(76, 'hard', 'dive_complete', 'Survivor of the Deep: finish 3 dives.', 20, 'dives_completed', 3, 0, true),
	(77, 'hard', 'dive_complete', 'Depth Master: finish 4 dives.', 20, 'dives_completed', 4, 0, true),
	(78, 'hard', 'dive_one_run', 'Untouchable: finish 2 dives in one run.', 20, 'dives_best', 2, 0, true),
	(79, 'hard', 'dive_dodge', 'Danger Below: dodge 60 obstacles.', 20, 'obstacles_total', 60, 0, true),
	(80, 'hard', 'dive_lanes', 'Master Navigator: switch lanes 75 times.', 20, 'lanes_total', 75, 0, true),
	(81, 'hard', 'dive_mines', 'Minefield Expert: pass 15 mines.', 20, 'mines_total', 15, 0, true),
	(82, 'hard', 'dive_dodge', 'Wide Berth: dodge 45 obstacles.', 20, 'obstacles_total', 45, 0, true),
	(83, 'hard', 'dive_lanes', 'Swift Fins: switch lanes 50 times.', 20, 'lanes_total', 50, 0, true),
	(84, 'hard', 'dive_mines', 'Mine Course: pass 10 mines.', 20, 'mines_total', 10, 0, true),
	(85, 'hard', 'dive_time', 'Stay Down: spend 80 seconds diving.', 20, 'dive_seconds', 80, 0, true),
	(86, 'hard', 'dive_left', 'Port Master: move left 35 times.', 20, 'lanes_left', 35, 0, true),
	(87, 'hard', 'dive_right', 'Starboard Master: move right 35 times.', 20, 'lanes_right', 35, 0, true),
	(88, 'hard', 'dive_enter', 'Frequent Diver: enter 6 dives.', 20, 'dives_entered', 6, 0, true),
	(89, 'hard', 'dive_dodge', 'Full Course: dodge 18 obstacles in one run.', 20, 'obstacles_best', 18, 0, true),
	(90, 'hard', 'dive_enter', 'Five Down: enter 5 dives.', 20, 'dives_entered', 5, 0, true)
on conflict (id) do update set
	tier = excluded.tier,
	family = excluded.family,
	description = excluded.description,
	reward = excluded.reward,
	rule = excluded.rule,
	goal = excluded.goal,
	goal_b = excluded.goal_b,
	enabled = excluded.enabled
where public.mission_definitions.id >= 46;
