/*
# Advertiser System — Schema Changes

1. Purpose
   Allows any user to become an advertiser by transferring funds from their available
   balance to a separate advertising balance. They can then create PTC ad campaigns and
   task campaigns funded from that balance. Each view/completion deducts from the
   campaign's remaining budget. When budget runs out, the campaign auto-deactivates.

2. Profile Changes
   - Add `advertising_balance numeric(18,8) NOT NULL DEFAULT 0` to `profiles`.

3. PTC Ads Changes
   - Add `advertiser_id uuid REFERENCES profiles(id) ON DELETE SET NULL` — the user who
     created this campaign (NULL for admin-created ads).
   - Add `budget numeric(18,8) NOT NULL DEFAULT 0` — total budget allocated.
   - Add `spent numeric(18,8) NOT NULL DEFAULT 0` — amount spent so far.
   - Add `status text NOT NULL DEFAULT 'active' CHECK (status IN ('draft','pending','active','paused','completed','rejected'))`
     — campaign lifecycle. Admin-created ads default to 'active'; advertiser-created
     start as 'pending' for admin approval.

4. Tasks Changes
   - Add `advertiser_id uuid REFERENCES profiles(id) ON DELETE SET NULL`.
   - Add `budget numeric(18,8) NOT NULL DEFAULT 0`.
   - Add `spent numeric(18,8) NOT NULL DEFAULT 0`.
   - Add `status text NOT NULL DEFAULT 'active' CHECK (status IN ('draft','pending','active','paused','completed','rejected'))`.

5. Transaction Types
   - Add 'ad_transfer' (moving funds to advertising balance).
   - Add 'ad_spend' (deducting from advertising balance for campaign creation).
   - Add 'ad_refund' (refunding unspent budget when campaign stopped).
   - Update the CHECK constraint on `transactions.type`.

6. Security
   - RLS policies: advertisers can SELECT their own campaigns (ptc_ads and tasks where
     advertiser_id = auth.uid()). Admin can see all.
   - No direct INSERT/UPDATE/DELETE by clients on campaigns — all through SECURITY DEFINER
     functions.

7. Notes
   - All money columns numeric(18,8).
   - Existing admin-created ads/tasks get advertiser_id = NULL and status = 'active',
     so they continue working unchanged.
*/

-- ---------- Add advertising_balance to profiles ----------
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'profiles' AND column_name = 'advertising_balance') THEN
    ALTER TABLE profiles ADD COLUMN advertising_balance numeric(18,8) NOT NULL DEFAULT 0;
  END IF;
END $$;

-- ---------- Add advertiser columns to ptc_ads ----------
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ptc_ads' AND column_name = 'advertiser_id') THEN
    ALTER TABLE ptc_ads ADD COLUMN advertiser_id uuid REFERENCES profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ptc_ads' AND column_name = 'budget') THEN
    ALTER TABLE ptc_ads ADD COLUMN budget numeric(18,8) NOT NULL DEFAULT 0;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ptc_ads' AND column_name = 'spent') THEN
    ALTER TABLE ptc_ads ADD COLUMN spent numeric(18,8) NOT NULL DEFAULT 0;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ptc_ads' AND column_name = 'status') THEN
    ALTER TABLE ptc_ads ADD COLUMN status text NOT NULL DEFAULT 'active'
      CHECK (status IN ('draft','pending','active','paused','completed','rejected'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS ptc_ads_advertiser_id_idx ON ptc_ads (advertiser_id);
CREATE INDEX IF NOT EXISTS ptc_ads_status_idx ON ptc_ads (status);

-- ---------- Add advertiser columns to tasks ----------
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'advertiser_id') THEN
    ALTER TABLE tasks ADD COLUMN advertiser_id uuid REFERENCES profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'budget') THEN
    ALTER TABLE tasks ADD COLUMN budget numeric(18,8) NOT NULL DEFAULT 0;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'spent') THEN
    ALTER TABLE tasks ADD COLUMN spent numeric(18,8) NOT NULL DEFAULT 0;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tasks' AND column_name = 'status') THEN
    ALTER TABLE tasks ADD COLUMN status text NOT NULL DEFAULT 'active'
      CHECK (status IN ('draft','pending','active','paused','completed','rejected'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS tasks_advertiser_id_idx ON tasks (advertiser_id);
CREATE INDEX IF NOT EXISTS tasks_status_idx ON tasks (status);

-- ---------- Update transaction type constraint ----------
ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_type_check;
ALTER TABLE transactions ADD CONSTRAINT transactions_type_check CHECK (type IN (
  'ptc_reward','task_reward','referral_reward','deposit','withdrawal',
  'withdrawal_refund','adjustment','ad_transfer','ad_spend','ad_refund'
));

-- ---------- RLS: advertisers can view their own campaigns ----------
DROP POLICY IF EXISTS "ptc_ads_select_own_advertiser" ON ptc_ads;
CREATE POLICY "ptc_ads_select_own_advertiser" ON ptc_ads FOR SELECT
  TO authenticated USING (advertiser_id = auth.uid());

DROP POLICY IF EXISTS "tasks_select_own_advertiser" ON tasks;
CREATE POLICY "tasks_select_own_advertiser" ON tasks FOR SELECT
  TO authenticated USING (advertiser_id = auth.uid());
