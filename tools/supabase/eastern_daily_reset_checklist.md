# Eastern daily reset — deployment checklist

Do not run `tools/supabase/eastern_daily_reset.sql` until this checklist is approved. Production has not been modified. The migration file itself was not changed for this package.

Package:

| Step | File |
|---|---|
| Migration | `tools/supabase/eastern_daily_reset.sql` |
| Read-only preflight | `tools/supabase/production_preflight.sql` |
| Function-source download | `tools/supabase/inspect_live_helpers.sql` |
| Backup and recovery | `tools/supabase/production_backup_checklist.md` |
| Read-only postflight | `tools/supabase/production_postflight.sql` |
| TestFlight | `tools/supabase/testflight_validation.md` |
| Later Deep Dive cards | `tools/supabase/deep_dive_activation_checklist.md` |

Do not run `daily_leaderboard_utc.sql`, `daily_missions_eastern_reset.sql`, or `daily_missions_deep_dive.sql`.

## 1. Preflight

Paste `production_preflight.sql` into the Supabase SQL Editor and save the grid.

Stop if any row is `FAIL`. In particular:

- `deployment_window` must be `PASS`. `REVIEW` means you are in the first hour after Eastern midnight or the last hour before UTC midnight. Wait.
- The four pipe and survival caps must show `drop=t`. A cap written as `< 81` or `< 1801` is a `FAIL` because the migration would leave it in place and long runs would still be rejected.
- `claim_daily_attempt`, `get_daily_challenge`, and `get_daily_attempt_status` must call `reefrun_publish_today`.
- `authenticated` must already be able to execute `get_daily_missions`. The migration does not re-grant that function.
- The replaced signatures and `reefrun_daily_seed`, `reefrun_count_at_least`, `reefrun_window_sum`, `auth.uid()`, and `daily_challenges_pkey` must exist.

`REVIEW` on `helper_date_source` is expected before the migration: publish, the board, claim, record, and the daily leaderboard still mention UTC. `submit_leaderboard_score` should stay on UTC. `reefrun_ensure_daily_mission_set` should not calculate its own day.

`deep_dive_definitions` should be `PASS` with zero ids 46–90. That matches the live query already run. The migration does not insert those rows.

Also run `inspect_live_helpers.sql` and download the CSV. That is the function-body copy for the backup notes.

## 2. Backup

Follow `production_backup_checklist.md`. Do not migrate until you can name a completed backup or a point-in-time target. Whether this project has point-in-time recovery is **UNVERIFIED** until that page is read.

## 3. When to run it

The guard is the first statement in `eastern_daily_reset.sql`. It raises, and stops the script, when the UTC date and the America/New_York date differ.

- Eastern daylight saving time: from midnight Eastern until before 8:00 PM Eastern.
- Eastern standard time: from midnight Eastern until before 7:00 PM Eastern.

Deploy in the middle of that window, roughly 9:00 AM to 6:00 PM Eastern during daylight saving time, or 8:00 AM to 5:00 PM Eastern during standard time. Stay away from Eastern midnight, when the daily date turns over, and away from the last hour before UTC midnight, when a slow or retried script could cross the boundary.

On 24 October 2026 daylight saving time is still in effect, so that day's window is midnight to before 8:00 PM Eastern. Being inside the window is not approval to run the script.

The guard was executed on disposable PostgreSQL with the clock fixed at 2026-10-21 00:12 UTC. It raised the refusal exception and left the pre-migration schema unchanged. Do not remove the guard.

## 4. Run the migration once

1. New SQL Editor query.
2. Paste the whole of `eastern_daily_reset.sql`.
3. Run the whole script once. Do not run a selection.
4. If the refusal exception appears, nothing after the guard ran. Stop and wait for the next window.
5. If any other error appears, follow the failure section of `production_backup_checklist.md` before trying again.

## 5. Postflight, then TestFlight

Run `production_postflight.sql` before anyone plays. Every `FAIL` is a stop. Compare `INFO` row counts with the preflight grid. A lower count is a blocker. Then follow `testflight_validation.md` with a test account.

## 6. Outstanding risks

- The production preflight and postflight have not been run on live Supabase. Local execution only proved the SQL runs. Do not treat this package as a passed production check.
- Live helper bodies were inspected earlier and reported: claim, challenge, and attempt status call `reefrun_publish_today`; start and ensure do not pick their own day; weekly and monthly submission stays UTC. The new preflight must confirm that again on the day of the deploy.
- The stored pipe caps on the disposable database match `<= 80` and `<= 1800`, which the migration drops. Production constraints are **UNVERIFIED** until the preflight grid shows `drop=t`.
- Point-in-time recovery for this project is **UNVERIFIED**. Replacing functions does not undo player rows created after a successful deploy.
- Deep Dive cards will not appear. Scoring support is in the migration; ids 46–90 are a separate approval.
- The Godot client calls these RPCs after anonymous sign-in. That session uses the `authenticated` role, not `anon`. The migration keeps client RPCs on `authenticated` and does not grant the mission board or the snapshot to clients.
- An old four-argument client still records a pipe-only run. A twelve-field body, including a run with no dive facts, uses the twelve-argument function. Neither function has defaults, so the two calls are not ambiguous.
