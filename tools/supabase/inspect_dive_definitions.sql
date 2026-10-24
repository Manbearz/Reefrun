-- READ ONLY. Paste into the Supabase SQL Editor.
-- Shows whether Deep Dive mission rows exist. Does not change data.

select id, tier, family, rule, goal, reward, enabled
from public.mission_definitions
where id >= 46
	or rule in (
		'dives_entered', 'dives_completed', 'dives_best', 'dive_seconds',
		'lanes_total', 'lanes_left', 'lanes_right',
		'obstacles_total', 'obstacles_best', 'mines_total'
	)
order by id;

select conrelid::regclass as table_name, conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.mission_definitions'::regclass
	and contype = 'c'
order by conname;
