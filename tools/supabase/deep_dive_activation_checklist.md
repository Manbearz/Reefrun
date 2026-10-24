# Deep Dive mission activation — not part of this deploy

Do not run this checklist now. Do not paste `tools/supabase/daily_missions_deep_dive.sql` into production. That file inserts ids 46–90, but it also keeps UTC dates, keeps the 80-pipe recorder limit, and is not the Eastern migration.

The Eastern migration scores a Deep Dive rule when one is already selected. It does not insert or enable those rules. A live query already returned zero rows for ids 46–90 and for the ten Deep Dive rule names. `production_preflight.sql` checks that again before deploy, and `production_postflight.sql` checks that it is still true afterward.

## What a later, separately approved script has to do

Use the 45 definitions already written in `scripts/daily_missions.gd`, ids 46–90. There are ten rules:

- `dives_entered`
- `dives_completed`
- `dives_best`
- `dive_seconds`
- `lanes_total`
- `lanes_left`
- `lanes_right`
- `obstacles_total`
- `obstacles_best`
- `mines_total`

Rewards stay 5 for easy, 10 for medium, and 20 for hard. Do not change missions 1–45, and do not enable the pipe missions that are already disabled.

The live id check, as stored by the local schema and reported by the preflight shape, is `id >= 1 and id <= 45`. The rule check allows only `pipes_total`, `pipes_best`, `runs`, `survive_best`, `coins_total`, `coin_runs`, `runs_at_least`, and `window_sum`. Production must confirm those two definitions with `production_preflight.sql` before any insert. Widen only those two checks. Re-add the rule list explicitly, including the eight existing rules plus the ten above. Leave the reward-tier check in place. Do not drop it.

Do not replace `record_unlimited_mission_run`, `reefrun_publish_today`, or the mission board in the activation script. Those already come from `eastern_daily_reset.sql`.

## Rotation

`reefrun_ensure_daily_mission_set(date)` inserts a set only when that date has no row. The set trigger rejects updates. Activating definitions during the day does not change today's three cards. The new cards can be selected on the next Eastern date that does not already have a set. The picker still chooses one enabled easy, one medium, and one hard mission.

## Verification after a future insert

On a test account, after the next Eastern midnight:

- The board shows progress for a Deep Dive card only after a run that actually performed that action.
- An unfinished card pays nothing.
- A completed easy, medium, or hard claim pays 5, 10, or 20 once.
- Claiming the same slot again pays nothing.
- The all-three bonus pays 25 once, and the 60-coin cap still blocks anything past 60.
- Missions 1–45 still score pipe, survival, coin, and run progress.
- Ids 46–90 exist and the eight older rules still exist.

Duplicate protection is already in `claim_daily_mission`: the unique key is `(player_id, mission_date, slot)`, and a second insert does not add coins.

## Local evidence, not production

On the disposable database, definitions 9001–9011 were inserted inside a transaction, scored by the new snapshot, claimed once, and then rolled back. That did not insert ids 46–90 and did not touch production.
