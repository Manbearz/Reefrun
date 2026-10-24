# TestFlight validation

Run this only after `tools/supabase/production_postflight.sql` has no `FAIL` rows. Use a TestFlight account, not a public player's account. Do not use this list as a production SQL script.

The rewarded-ad coin bonus is added on the device by `GameSession.add_coins`. It is not a Supabase RPC. The migration does not change it. Daily Mission coins are separate: they are the 5 / 10 / 20 / 25 server rewards, not the ad bonus.

## Before playing

- Install the build that sends the twelve-field mission body and accepts long Unlimited runs.
- Sign in with the test account.
- Note the mission board: three cards, their progress, and the countdown.
- Note the spendable coin total on the device.

## Daily Challenge

1. Start one Daily Challenge. The swim should begin.
2. Finish it. The completion screen should show a score.
3. Try to start Daily Challenge again with the same account. A second swim that day should not start.
4. Open the Daily leaderboard. The score just finalized should be visible.
5. Open Weekly and Monthly. Existing scores should still be listed. This deploy does not rewrite them.

## Unlimited runs and Daily Missions

1. Die on a short Unlimited run that does not enter a dive. The mission board progress for a pipe, survival, coin, or run card should move, and the run should not stay pending.
2. Play one Unlimited run that enters a Deep Dive and dodges at least one obstacle. The client may store those facts. The current server cards are still the existing pipe, survival, coin, and run missions, because mission ids 46–90 are not inserted by this migration. The dive run should record rather than stay pending. Do not expect a Deep Dive card to appear.
3. If a pipe card reaches its goal, claim it once. The reward should be 5, 10, or 20 for that slot. Claim the same slot again. The balance should not increase a second time.
4. Confirm the mission countdown still points at the next Eastern midnight, not the next 00:00 UTC.

## Rewarded ad

1. On an Unlimited run, collect at least one coin and die while a rewarded ad is available.
2. Watch the ad to completion. The device wallet should increase by the coins collected on that run, once. That is the double: the run already awarded its coins, and the completed ad awards the same amount again.
3. Close the ad early, or fail the ad. The extra amount should not be added. Coins already collected during the swim stay.
4. Do not treat the ad bonus as a Daily Mission claim. It should not change `mission_reward_coins`.

## After the session

- Run `production_postflight.sql` again only if you need to confirm definitions 46–90 are still absent. Playing will increase attempt, score, and mission counts. That increase is expected and is not a migration failure.
- Watch the API logs for `PGRST202`, `PGRST203`, and mission replies with reason `rejected` on a normal short run.
