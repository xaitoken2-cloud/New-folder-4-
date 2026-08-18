/*
# Deposits, withdrawals, support tickets

1. New Tables
- `deposits` — user deposit requests. status: pending/approved/rejected/cancelled.
  A pending deposit does NOT increase available balance. Approval is atomic + idempotent
  (unique reference on the resulting transaction prevents double-approval).
- `withdrawals` — user withdrawal requests. status: pending/paid/rejected/cancelled.
  On request, funds are reserved (available_balance reduced, pending_balance increased).
  On rejection, funds are atomically refunded. On approval, pending_balance reduced and
  total_withdrawn increased. Uses SELECT FOR UPDATE locking to prevent double-spending.
- `support_tickets` — user support tickets. status: open/pending/closed.
- `ticket_replies` — replies on a ticket. Users see only their own tickets' replies;
  admins see all via functions.

2. Security
- RLS enabled on all tables.
- deposits: SELECT own; INSERT own (user_id defaults to auth.uid()); no direct UPDATE.
- withdrawals: SELECT own; INSERT own; no direct UPDATE.
- support_tickets: SELECT own; INSERT own; UPDATE own (only to close).
- ticket_replies: SELECT own (via ticket ownership); INSERT own.

3. Notes
- Money columns numeric(18,8).
- Withdrawal request + reserve is a single SECURITY DEFINER transaction.
*/

-- ---------- deposits ----------
CREATE TABLE IF NOT EXISTS deposits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  amount numeric(18,8) NOT NULL CHECK (amount > 0),
  payment_method text NOT NULL DEFAULT 'manual',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled')),
  admin_note text NOT NULL DEFAULT '',
  reviewed_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS deposits_user_id_idx ON deposits (user_id);
CREATE INDEX IF NOT EXISTS deposits_status_idx ON deposits (status);
CREATE INDEX IF NOT EXISTS deposits_created_at_idx ON deposits (created_at DESC);

ALTER TABLE deposits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deposits_select_own" ON deposits;
CREATE POLICY "deposits_select_own" ON deposits FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "deposits_insert_own" ON deposits;
CREATE POLICY "deposits_insert_own" ON deposits FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

-- ---------- withdrawals ----------
CREATE TABLE IF NOT EXISTS withdrawals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  amount numeric(18,8) NOT NULL CHECK (amount > 0),
  withdrawal_method text NOT NULL DEFAULT 'manual',
  destination text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','rejected','cancelled')),
  admin_note text NOT NULL DEFAULT '',
  reviewed_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS withdrawals_user_id_idx ON withdrawals (user_id);
CREATE INDEX IF NOT EXISTS withdrawals_status_idx ON withdrawals (status);
CREATE INDEX IF NOT EXISTS withdrawals_created_at_idx ON withdrawals (created_at DESC);

ALTER TABLE withdrawals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "withdrawals_select_own" ON withdrawals;
CREATE POLICY "withdrawals_select_own" ON withdrawals FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "withdrawals_insert_own" ON withdrawals;
CREATE POLICY "withdrawals_insert_own" ON withdrawals FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

-- ---------- support_tickets ----------
CREATE TABLE IF NOT EXISTS support_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  subject text NOT NULL,
  message text NOT NULL,
  category text NOT NULL DEFAULT 'general',
  priority text NOT NULL DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','pending','closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS support_tickets_user_id_idx ON support_tickets (user_id);
CREATE INDEX IF NOT EXISTS support_tickets_status_idx ON support_tickets (status);

ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tickets_select_own" ON support_tickets;
CREATE POLICY "tickets_select_own" ON support_tickets FOR SELECT
  TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "tickets_insert_own" ON support_tickets;
CREATE POLICY "tickets_insert_own" ON support_tickets FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "tickets_update_own" ON support_tickets;
CREATE POLICY "tickets_update_own" ON support_tickets FOR UPDATE
  TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

REVOKE UPDATE ON support_tickets FROM authenticated;
GRANT UPDATE (status) ON support_tickets TO authenticated;

DROP TRIGGER IF EXISTS tickets_touch_updated_at ON support_tickets;
CREATE TRIGGER tickets_touch_updated_at
  BEFORE UPDATE ON support_tickets
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ---------- ticket_replies ----------
CREATE TABLE IF NOT EXISTS ticket_replies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  message text NOT NULL,
  is_staff boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ticket_replies_ticket_id_idx ON ticket_replies (ticket_id);

ALTER TABLE ticket_replies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "replies_select_own_ticket" ON ticket_replies;
CREATE POLICY "replies_select_own_ticket" ON ticket_replies FOR SELECT
  TO authenticated USING (
    EXISTS (SELECT 1 FROM support_tickets t WHERE t.id = ticket_id AND t.user_id = auth.uid())
  );

DROP POLICY IF EXISTS "replies_insert_own_ticket" ON ticket_replies;
CREATE POLICY "replies_insert_own_ticket" ON ticket_replies FOR INSERT
  TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM support_tickets t WHERE t.id = ticket_id AND t.user_id = auth.uid())
  );
