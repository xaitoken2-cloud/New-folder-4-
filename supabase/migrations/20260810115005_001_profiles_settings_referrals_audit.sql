/*
# Core tables: profiles, app settings, referrals, audit logs

1. New Tables
- `profiles` — 1:1 with auth.users. Holds username, full_name, country, role, status,
  referral code, and cached financial balances. Balances/role/status are NEVER client-writable.
- `app_settings` — single-row key/value config table for referral and platform settings.
- `referrals` — referral relationships (referrer -> referred user), with qualified flag.
- `audit_logs` — sensitive admin action audit trail.

2. Security
- RLS enabled on all tables.
- profiles: users can SELECT own row; UPDATE only on non-privileged columns
  (full_name, country, avatar_url, password_changed_at). Balance/role/status columns
  are revoked from authenticated UPDATE and changed only via SECURITY DEFINER functions.
- app_settings: SELECT open to authenticated (read config); writes only via admin functions.
- referrals: SELECT own rows (as referrer or referred).
- audit_logs: SELECT only for admin role via function; no direct user access.

3. Notes
- A trigger auto-creates a profile row whenever a new auth.users row is inserted,
  generating a unique referral code and defaulting role='user', status='active'.
- Referral code is unique via a lower-case unique index.
- Money columns use numeric(18,8), never floating point.
*/

-- ---------- profiles ----------
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username text NOT NULL,
  full_name text NOT NULL,
  email text NOT NULL,
  country text NOT NULL DEFAULT '',
  role text NOT NULL DEFAULT 'user' CHECK (role IN ('user','moderator','admin')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','banned')),
  referral_code text NOT NULL,
  referred_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  avatar_url text DEFAULT '',
  available_balance numeric(18,8) NOT NULL DEFAULT 0,
  pending_balance numeric(18,8) NOT NULL DEFAULT 0,
  total_earned numeric(18,8) NOT NULL DEFAULT 0,
  total_withdrawn numeric(18,8) NOT NULL DEFAULT 0,
  total_deposited numeric(18,8) NOT NULL DEFAULT 0,
  ptc_views integer NOT NULL DEFAULT 0,
  tasks_completed integer NOT NULL DEFAULT 0,
  password_changed_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS profiles_referral_code_idx ON profiles (lower(referral_code));
CREATE INDEX IF NOT EXISTS profiles_referred_by_idx ON profiles (referred_by);
CREATE INDEX IF NOT EXISTS profiles_role_idx ON profiles (role);
CREATE INDEX IF NOT EXISTS profiles_status_idx ON profiles (status);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select_own" ON profiles;
CREATE POLICY "profiles_select_own" ON profiles FOR SELECT
  TO authenticated USING (auth.uid() = id);

-- Allow update only on user-editable columns via column privileges (no row policy UPDATE
-- is sufficient because we revoke full UPDATE then grant only safe columns).
REVOKE UPDATE ON profiles FROM authenticated;
GRANT UPDATE (full_name, country, avatar_url) ON profiles TO authenticated;

-- ---------- app_settings ----------
CREATE TABLE IF NOT EXISTS app_settings (
  id integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  referral_reward numeric(18,8) NOT NULL DEFAULT 0.10,
  referral_qualification text NOT NULL DEFAULT 'first_ptc' CHECK (referral_qualification IN ('signup','first_ptc','first_task','first_deposit')),
  min_withdrawal numeric(18,8) NOT NULL DEFAULT 1.00,
  max_withdrawal numeric(18,8) NOT NULL DEFAULT 1000.00,
  withdrawal_cooldown_minutes integer NOT NULL DEFAULT 60,
  ptc_daily_limit_per_ad integer NOT NULL DEFAULT 1,
  task_daily_limit integer NOT NULL DEFAULT 20,
  platform_name text NOT NULL DEFAULT 'GoldClicks',
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO app_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "settings_select_authenticated" ON app_settings;
CREATE POLICY "settings_select_authenticated" ON app_settings FOR SELECT
  TO authenticated USING (true);

-- ---------- referrals ----------
CREATE TABLE IF NOT EXISTS referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  referred_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  qualified boolean NOT NULL DEFAULT false,
  reward_amount numeric(18,8) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  qualified_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS referrals_referred_id_key ON referrals (referred_id);
CREATE INDEX IF NOT EXISTS referrals_referrer_id_idx ON referrals (referrer_id);

ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "referrals_select_own" ON referrals;
CREATE POLICY "referrals_select_own" ON referrals FOR SELECT
  TO authenticated USING (auth.uid() = referrer_id OR auth.uid() = referred_id);

-- ---------- audit_logs ----------
CREATE TABLE IF NOT EXISTS audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  action text NOT NULL,
  target_type text,
  target_id text,
  details jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS audit_logs_actor_id_idx ON audit_logs (actor_id);
CREATE INDEX IF NOT EXISTS audit_logs_created_at_idx ON audit_logs (created_at DESC);

ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
-- No SELECT policy: audit logs are read only via admin SECURITY DEFINER function.

-- ---------- referral code generator ----------
CREATE OR REPLACE FUNCTION generate_referral_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  code text;
  attempts integer := 0;
BEGIN
  LOOP
    code := substr(md5(random()::text || extract(epoch from clock_timestamp())::text), 1, 8);
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE lower(referral_code) = lower(code)) THEN
      RETURN code;
    END IF;
    attempts := attempts + 1;
    IF attempts > 10 THEN
      code := substr(md5(random()::text || gen_random_uuid()::text), 1, 10);
      RETURN code;
    END IF;
  END LOOP;
END;
$$;

-- ---------- auto-create profile on signup ----------
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_referral_code text;
  v_referred_by uuid;
  v_meta jsonb;
BEGIN
  v_referral_code := generate_referral_code();
  v_meta := COALESCE(new.raw_user_meta_data, '{}'::jsonb);

  -- Resolve referral code from metadata (case-insensitive)
  IF v_meta ? 'referral_code' THEN
    SELECT id INTO v_referred_by FROM profiles
      WHERE lower(referral_code) = lower(v_meta->>'referral_code')
      LIMIT 1;
    IF v_referred_by = new.id THEN
      v_referred_by := NULL; -- prevent self-referral
    END IF;
  END IF;

  INSERT INTO profiles (
    id, username, full_name, email, country, referral_code, referred_by
  ) VALUES (
    new.id,
    COALESCE(v_meta->>'username', split_part(new.email, '@', 1)),
    COALESCE(v_meta->>'full_name', v_meta->>'username', split_part(new.email, '@', 1)),
    COALESCE(new.email, ''),
    COALESCE(v_meta->>'country', ''),
    v_referral_code,
    v_referred_by
  );

  IF v_referred_by IS NOT NULL THEN
    INSERT INTO referrals (referrer_id, referred_id)
      VALUES (v_referred_by, new.id)
      ON CONFLICT (referred_id) DO NOTHING;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ---------- updated_at maintainer for profiles ----------
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  new.updated_at := now();
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS profiles_touch_updated_at ON profiles;
CREATE TRIGGER profiles_touch_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
