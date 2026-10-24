# Production backup and recovery

Do not run a backup, restore, or migration from this file. Nothing here has been verified against the live ReefRun Supabase project. Whether a backup or point-in-time recovery exists is **UNVERIFIED** until you look at the dashboard and write down what it shows.

## 1. Confirm the project

In the Supabase dashboard, confirm the project URL is the ReefRun project used by the Godot client before opening the SQL Editor. Do not use a service-role key in the game.

## 2. See what recovery this project actually has

Open **Database → Backups** for this project.

Record, in writing:

- Whether **Point in Time Recovery** is enabled.
- If it is, the earliest restorable time and the retention window.
- Whether only scheduled backups are listed, and the time of the newest one.
- Whether the page offers a manual backup or a download.

Do not assume a plan includes point-in-time recovery. The Backups page is the only source for this project. A list of daily backups, with no point-in-time control, cannot restore to an arbitrary minute.

## 3. Make a restore point you can name

Before pasting `eastern_daily_reset.sql`:

1. If the Backups page can start a backup, start one and wait until it is listed. Record its timestamp.
2. If point-in-time recovery is enabled, record the current time from the dashboard clock as the restore target you would use. Do not migrate until that target is inside the restorable window.
3. Run `tools/supabase/production_preflight.sql` and save the full result grid. The `INFO` rows are the row counts and function fingerprints.
4. Run `tools/supabase/inspect_live_helpers.sql` and download the result. That CSV is the source of the function bodies the migration replaces. It is not a database backup.

If you cannot name either a completed backup or a point-in-time target, stop. Do not migrate.

## 4. What each option can and cannot restore

- A database backup or point-in-time restore puts the whole project back to that time. It restores schema and player rows together. It also discards every score, attempt, claim, and profile change made after that time.
- The function CSV lets you compare or reapply an old function body. Replacing a function does not delete challenge rows, attempts, mission progress, claims, or coin balances created after the migration.
- Do not hand-edit `challenge_date`, `period_key`, `mission_date`, or `mission_reward_coins` to undo a deploy.

## 5. If the migration script fails

Supabase SQL Editor should run the pasted script as one transaction. The local PostgreSQL test proved that a later error then rolls the whole script back, including columns and functions.

- If the only error is `Refusing Eastern daily reset...`, the guard stopped on its first statement. No later change ran. Wait for the next safe window. Do not restore.
- If the editor shows a different error and no success message, run `production_postflight.sql`. If the new columns and overloads are absent and the old pipe caps remain, the script rolled back. Fix nothing in production until the error is understood.
- If postflight shows a mixture, such as new columns but old functions, the editor did not keep one transaction. Stop. Restore the backup or point-in-time target from step 3. Do not run the migration again on a half-applied database until that restore is finished.

## 6. If the migration succeeds and a gameplay RPC fails

Do not restore as the first move. Players may already have new rows.

1. Run `production_postflight.sql` and keep the grid.
2. Check the API logs for `PGRST202` and `PGRST203` on `record_unlimited_mission_run`. `PGRST202` means the request body matches neither overload. `PGRST203` means the two overloads are ambiguous. The migration gives the twelve-argument function no defaults so a four-key body stays on the four-argument function.
3. Confirm the script's final `NOTIFY pgrst, 'reload schema'` ran. If the API still shows the old signature, reload the schema from the dashboard API settings and retest one read-only postflight check. Do not submit a score to test that.
4. A wrong grant or a wrong function body can be corrected with a reviewed follow-up script in a later safe window. That is narrower than restoring the database.
5. Restore the backup only when postflight shows the migration itself is wrong and you accept losing every player write made after the restore point.
