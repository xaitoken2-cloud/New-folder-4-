/*
# Add missing referral_earned column to profiles
1. Bug
- credit_referral_commission() (added in migration 017) writes to
  profiles.referral_earned on every referral commission payout, but that
  column was never created on the profiles table. This causes
  'column "referral_earned" does not exist' errors whenever a user with
  an active referrer claims a PTC ad reward, submits an auto-approved
  task, or has a deposit approved.
2. Fix
- Add referral_earned numeric(18,8) NOT NULL DEFAULT 0 to profiles,
  backfilled from the sum of completed referral_reward transactions
  already credited to each user, so existing balances stay accurate.
*/
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS referral_earned numeric(18,8) NOT NULL DEFAULT 0;
-- Backfill from existing referral_reward transactions so totals are
-- correct for users who already earned referral commissions before
-- this column existed.
UPDATE profiles p
SET referral_earned = COALESCE(t.total, 0)
FROM (
  SELECT user_id, sum(amount) AS total
  FROM transactions
  WHERE type = 'referral_reward' AND status = 'completed'
  GROUP BY user_id
) t
WHERE p.id = t.user_id;