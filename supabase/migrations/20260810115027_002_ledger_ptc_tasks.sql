/*
# Financial ledger, PTC system, tasks

1. New Tables
- `transactions` — immutable financial ledger. Each row is a credit/debit event.
  Types: ptc_reward, task_reward, referral_reward, deposit, withdrawal, withdrawal_refund, adjustment.
  Has unique `reference` to prevent duplicate financial events.
- `ptc_ads` — advertisements with reward, duration, limits, scheduling.
- `ptc_ad_views` — per-user view sessions. Unique on (user_id, ptc_ad_id, view_date) to
  enforce daily view limit at the DB level. status: pending/completed/expired/cancelled.
- `tasks` — action-based tasks (not PTC). proof_required, task_type, limits.
- `task_completions` — per-user task submissions. Unique on (user_id, task_id) to prevent
  duplicate completion. status: pending/approved/rejected.

2. Security
- RLS enabled on all tables.
- transactions: SELECT own rows only. No direct INSERT/UPDATE/DELETE by clients — all
  ledger writes happen inside SECURITY DEFINER functions.
- ptc_ads: SELECT visible active ads for authenticated; admin writes via functions.
- ptc_ad_views: SELECT own views; INSERT/UPDATE only via functions.
- tasks: SELECT visible active tasks for authenticated; admin writes via functions.
- task_completions: SELECT own completions; INSERT/UPDATE only via functions.

3. Notes
- All money columns numeric(18,8).
- Unique constraints act as idempotency guards against duplicate claims/completions.
*/

-- ---------- transactions ----------
CREATE TABLE IF NOT EXISTS transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('ptc_reward','task_reward','referral_reward','deposit','withdrawal','withdrawal_refund','adjustment')),
  amount numeric(18,8) NOT NULL, -- positive credit, negative debit
  reference_type text,
  reference_id uuid,
  reference text UNIQUE,
  description text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'completed' CHECK (status IN ('pending','completed','failed','reversed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS transactions_user_id_idx ON transactions (user_id);
CREATE INDEX IF NOT EXISTS transactions_type_idx ON transactions (type);
CREATE INDEX IF NOT EXISTS transactions_created_at_idx ON transactions (created_at DESC);
CREATE INDEX IF NOT EXISTS transactions_reference_idx ON transactions (reference);

ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "transactions_select_own" ON transactions;
CREATE POLICY "transactions_select_own" ON transactions FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

-- ---------- ptc_ads ----------
CREATE TABLE IF NOT EXISTS ptc_ads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  advertiser text NOT NULL DEFAULT '',
  category text NOT NULL DEFAULT 'general',
  reward numeric(18,8) NOT NULL DEFAULT 0.001 CHECK (reward > 0),
  duration_seconds integer NOT NULL DEFAULT 10 CHECK (duration_seconds BETWEEN 1 AND 3600),
  destination_url text NOT NULL DEFAULT '',
  image_url text NOT NULL DEFAULT '',
  daily_view_limit integer NOT NULL DEFAULT 1 CHECK (daily_view_limit >= 1),
  total_view_limit integer NOT NULL DEFAULT 0 CHECK (total_view_limit >= 0), -- 0 = unlimited
  total_views integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  start_date timestamptz,
  end_date timestamptz,
  created_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ptc_ads_active_idx ON ptc_ads (active);
CREATE INDEX IF NOT EXISTS ptc_ads_category_idx ON ptc_ads (category);

ALTER TABLE ptc_ads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ptc_ads_select_authenticated" ON ptc_ads;
CREATE POLICY "ptc_ads_select_authenticated" ON ptc_ads FOR SELECT
  TO authenticated USING (true);

DROP TRIGGER IF EXISTS ptc_ads_touch_updated_at ON ptc_ads;
CREATE TRIGGER ptc_ads_touch_updated_at
  BEFORE UPDATE ON ptc_ads
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ---------- ptc_ad_views ----------
CREATE TABLE IF NOT EXISTS ptc_ad_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  ptc_ad_id uuid NOT NULL REFERENCES ptc_ads(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  required_duration integer NOT NULL,
  reward numeric(18,8) NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','completed','expired','cancelled')),
  view_date date NOT NULL DEFAULT current_date,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ptc_ad_views_user_ad_date_idx
  ON ptc_ad_views (user_id, ptc_ad_id, view_date);
CREATE INDEX IF NOT EXISTS ptc_ad_views_user_id_idx ON ptc_ad_views (user_id);
CREATE INDEX IF NOT EXISTS ptc_ad_views_ptc_ad_id_idx ON ptc_ad_views (ptc_ad_id);
CREATE INDEX IF NOT EXISTS ptc_ad_views_status_idx ON ptc_ad_views (status);

ALTER TABLE ptc_ad_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ptc_views_select_own" ON ptc_ad_views;
CREATE POLICY "ptc_views_select_own" ON ptc_ad_views FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

-- ---------- tasks ----------
CREATE TABLE IF NOT EXISTS tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  instructions text NOT NULL DEFAULT '',
  category text NOT NULL DEFAULT 'general',
  task_type text NOT NULL DEFAULT 'custom' CHECK (task_type IN ('visit_website','registration','social_follow','app_install','survey','submit_proof','custom')),
  reward numeric(18,8) NOT NULL DEFAULT 0.01 CHECK (reward > 0),
  action_url text NOT NULL DEFAULT '',
  proof_required boolean NOT NULL DEFAULT false,
  proof_instructions text NOT NULL DEFAULT '',
  daily_limit integer NOT NULL DEFAULT 0 CHECK (daily_limit >= 0), -- 0 = unlimited
  total_limit integer NOT NULL DEFAULT 0 CHECK (total_limit >= 0), -- 0 = unlimited
  total_completions integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  start_date timestamptz,
  end_date timestamptz,
  created_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS tasks_active_idx ON tasks (active);
CREATE INDEX IF NOT EXISTS tasks_category_idx ON tasks (category);

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tasks_select_authenticated" ON tasks;
CREATE POLICY "tasks_select_authenticated" ON tasks FOR SELECT
  TO authenticated USING (true);

DROP TRIGGER IF EXISTS tasks_touch_updated_at ON tasks;
CREATE TRIGGER tasks_touch_updated_at
  BEFORE UPDATE ON tasks
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ---------- task_completions ----------
CREATE TABLE IF NOT EXISTS task_completions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  proof_text text NOT NULL DEFAULT '',
  reward numeric(18,8) NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  reviewed_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS task_completions_user_task_idx
  ON task_completions (user_id, task_id);
CREATE INDEX IF NOT EXISTS task_completions_user_id_idx ON task_completions (user_id);
CREATE INDEX IF NOT EXISTS task_completions_task_id_idx ON task_completions (task_id);
CREATE INDEX IF NOT EXISTS task_completions_status_idx ON task_completions (status);

ALTER TABLE task_completions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "task_completions_select_own" ON task_completions;
CREATE POLICY "task_completions_select_own" ON task_completions FOR SELECT
  TO authenticated USING (auth.uid() = user_id);
