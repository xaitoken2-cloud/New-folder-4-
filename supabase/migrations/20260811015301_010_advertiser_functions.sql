/*
# Advertiser System — RPC Functions

1. Functions
   - `ad_transfer_to_advertising(p_amount)` — transfers funds from available_balance to
     advertising_balance. Locks profile FOR UPDATE, validates positive amount and
     sufficient balance. Creates an 'ad_transfer' ledger transaction (negative from
     available, tracked via reference). Atomic.
   - `ad_create_ptc_campaign(...)` — advertiser creates a PTC ad campaign. Validates
     advertising_balance >= budget. Deducts budget from advertising_balance. Creates
     ptc_ads row with advertiser_id, budget, spent=0, status='pending' (needs admin
     approval). Creates 'ad_spend' ledger transaction.
   - `ad_create_task_campaign(...)` — same for task campaigns.
   - `ad_pause_campaign(p_campaign_id, p_type)` — advertiser pauses their active campaign.
   - `ad_resume_campaign(p_campaign_id, p_type)` — advertiser resumes a paused campaign.
   - `ad_stop_campaign(p_campaign_id, p_type)` — advertiser stops campaign. Refunds
     unspent budget (budget - spent) back to advertising_balance. Sets status='completed'.
     Creates 'ad_refund' ledger transaction.
   - `ad_get_dashboard()` — returns advertiser's dashboard: advertising_balance, total
     campaigns, active campaigns, total spent, total budget, campaign breakdown.
   - `ad_list_campaigns()` — returns all campaigns for the advertiser (both PTC and tasks).

2. Security
   - All SECURITY DEFINER, search_path = public, REVOKE anon, GRANT authenticated.
   - All ownership checks via auth.uid(). Advertiser can only manage their own campaigns.
   - No client-supplied amount is trusted for rewards — budget is validated server-side.

3. Notes
   - Campaign status flow: pending -> active (admin approves) -> paused/active -> completed.
   - When budget is exhausted (spent >= budget), campaign auto-deactivates (active=false,
     status='completed').
   - Refund on stop returns unspent funds to advertising_balance.
*/

-- ---------- ad_transfer_to_advertising ----------
CREATE OR REPLACE FUNCTION ad_transfer_to_advertising(p_amount numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Invalid amount'; END IF;

  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;
  IF p_amount > v_profile.available_balance THEN RAISE EXCEPTION 'Insufficient available balance'; END IF;

  UPDATE profiles
    SET available_balance = available_balance - p_amount,
        advertising_balance = advertising_balance + p_amount
    WHERE id = auth.uid();

  v_ref := 'ad_transfer:' || auth.uid()::text || ':' || extract(epoch from now())::bigint::text;
  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (auth.uid(), 'ad_transfer', -p_amount, 'ad_transfer', auth.uid(), v_ref,
      'Transfer to advertising balance', 'completed')
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

  RETURN jsonb_build_object('ok', true, 'advertising_balance', v_profile.advertising_balance + p_amount);
END;
$$;

REVOKE EXECUTE ON FUNCTION ad_transfer_to_advertising(numeric) FROM anon;
GRANT EXECUTE ON FUNCTION ad_transfer_to_advertising(numeric) TO authenticated;

-- ---------- ad_create_ptc_campaign ----------
CREATE OR REPLACE FUNCTION ad_create_ptc_campaign(
  p_title text, p_description text, p_advertiser text, p_category text,
  p_reward numeric, p_duration_seconds integer, p_destination_url text,
  p_image_url text, p_daily_view_limit integer, p_total_view_limit integer,
  p_budget numeric
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_ad_id uuid;
  v_ref text;
  v_tx_id uuid;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

  IF p_budget IS NULL OR p_budget <= 0 THEN RAISE EXCEPTION 'Invalid budget'; END IF;
  IF p_reward IS NULL OR p_reward <= 0 THEN RAISE EXCEPTION 'Invalid reward per view'; END IF;
  IF p_duration_seconds IS NULL OR p_duration_seconds < 1 OR p_duration_seconds > 3600 THEN
    RAISE EXCEPTION 'Duration must be between 1 and 3600 seconds'; END IF;
  IF p_daily_view_limit IS NULL OR p_daily_view_limit < 1 THEN
    RAISE EXCEPTION 'Daily view limit must be at least 1'; END IF;
  IF p_total_view_limit IS NULL OR p_total_view_limit < 0 THEN
    RAISE EXCEPTION 'Total view limit must be 0 or positive'; END IF;
  IF p_budget > v_profile.advertising_balance THEN
    RAISE EXCEPTION 'Insufficient advertising balance (need %, have %)', p_budget, v_profile.advertising_balance; END IF;

  -- Deduct budget from advertising balance
  UPDATE profiles SET advertising_balance = advertising_balance - p_budget WHERE id = auth.uid();

  -- Create campaign (status='pending' for admin approval)
  INSERT INTO ptc_ads (
    title, description, advertiser, category, reward, duration_seconds,
    destination_url, image_url, daily_view_limit, total_view_limit,
    active, advertiser_id, budget, spent, status
  ) VALUES (
    p_title, COALESCE(p_description, ''), COALESCE(p_advertiser, ''), COALESCE(p_category, 'general'),
    p_reward, p_duration_seconds, COALESCE(p_destination_url, ''), COALESCE(p_image_url, ''),
    p_daily_view_limit, p_total_view_limit, false, auth.uid(), p_budget, 0, 'pending'
  ) RETURNING id INTO v_ad_id;

  v_ref := 'ad_spend:ptc:' || v_ad_id::text;
  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (auth.uid(), 'ad_spend', -p_budget, 'ptc_ad', v_ad_id, v_ref,
      'PTC campaign budget allocation', 'completed')
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

  RETURN jsonb_build_object('ok', true, 'campaign_id', v_ad_id, 'status', 'pending');
END;
$$;

REVOKE EXECUTE ON FUNCTION ad_create_ptc_campaign FROM anon;
GRANT EXECUTE ON FUNCTION ad_create_ptc_campaign TO authenticated;

-- ---------- ad_create_task_campaign ----------
CREATE OR REPLACE FUNCTION ad_create_task_campaign(
  p_title text, p_description text, p_instructions text, p_category text,
  p_task_type text, p_reward numeric, p_action_url text,
  p_proof_required boolean, p_proof_instructions text,
  p_daily_limit integer, p_total_limit integer, p_budget numeric
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_task_id uuid;
  v_ref text;
  v_tx_id uuid;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

  IF p_budget IS NULL OR p_budget <= 0 THEN RAISE EXCEPTION 'Invalid budget'; END IF;
  IF p_reward IS NULL OR p_reward <= 0 THEN RAISE EXCEPTION 'Invalid reward'; END IF;
  IF p_daily_limit IS NULL OR p_daily_limit < 0 THEN RAISE EXCEPTION 'Invalid daily limit'; END IF;
  IF p_total_limit IS NULL OR p_total_limit < 0 THEN RAISE EXCEPTION 'Invalid total limit'; END IF;
  IF p_budget > v_profile.advertising_balance THEN
    RAISE EXCEPTION 'Insufficient advertising balance'; END IF;

  UPDATE profiles SET advertising_balance = advertising_balance - p_budget WHERE id = auth.uid();

  INSERT INTO tasks (
    title, description, instructions, category, task_type, reward, action_url,
    proof_required, proof_instructions, daily_limit, total_limit,
    active, advertiser_id, budget, spent, status
  ) VALUES (
    p_title, COALESCE(p_description, ''), COALESCE(p_instructions, ''),
    COALESCE(p_category, 'general'), COALESCE(p_task_type, 'custom'),
    p_reward, COALESCE(p_action_url, ''), COALESCE(p_proof_required, false),
    COALESCE(p_proof_instructions, ''), p_daily_limit, p_total_limit,
    false, auth.uid(), p_budget, 0, 'pending'
  ) RETURNING id INTO v_task_id;

  v_ref := 'ad_spend:task:' || v_task_id::text;
  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (auth.uid(), 'ad_spend', -p_budget, 'task', v_task_id, v_ref,
      'Task campaign budget allocation', 'completed')
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

  RETURN jsonb_build_object('ok', true, 'campaign_id', v_task_id, 'status', 'pending');
END;
$$;

REVOKE EXECUTE ON FUNCTION ad_create_task_campaign FROM anon;
GRANT EXECUTE ON FUNCTION ad_create_task_campaign TO authenticated;

-- ---------- ad_pause_campaign ----------
CREATE OR REPLACE FUNCTION ad_pause_campaign(p_campaign_id uuid, p_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_owner uuid;
BEGIN
  IF p_type = 'ptc' THEN
    SELECT advertiser_id INTO v_owner FROM ptc_ads WHERE id = p_campaign_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Campaign not found'; END IF;
    IF v_owner != auth.uid() THEN RAISE EXCEPTION 'Not authorized'; END IF;
    UPDATE ptc_ads SET status = 'paused', active = false WHERE id = p_campaign_id AND status = 'active';
  ELSIF p_type = 'task' THEN
    SELECT advertiser_id INTO v_owner FROM tasks WHERE id = p_campaign_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Campaign not found'; END IF;
    IF v_owner != auth.uid() THEN RAISE EXCEPTION 'Not authorized'; END IF;
    UPDATE tasks SET status = 'paused', active = false WHERE id = p_campaign_id AND status = 'active';
  ELSE
    RAISE EXCEPTION 'Invalid campaign type';
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION ad_pause_campaign(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION ad_pause_campaign(uuid, text) TO authenticated;

-- ---------- ad_resume_campaign ----------
CREATE OR REPLACE FUNCTION ad_resume_campaign(p_campaign_id uuid, p_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_owner uuid;
BEGIN
  IF p_type = 'ptc' THEN
    SELECT advertiser_id INTO v_owner FROM ptc_ads WHERE id = p_campaign_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Campaign not found'; END IF;
    IF v_owner != auth.uid() THEN RAISE EXCEPTION 'Not authorized'; END IF;
    UPDATE ptc_ads SET status = 'active', active = true WHERE id = p_campaign_id AND status = 'paused';
  ELSIF p_type = 'task' THEN
    SELECT advertiser_id INTO v_owner FROM tasks WHERE id = p_campaign_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Campaign not found'; END IF;
    IF v_owner != auth.uid() THEN RAISE EXCEPTION 'Not authorized'; END IF;
    UPDATE tasks SET status = 'active', active = true WHERE id = p_campaign_id AND status = 'paused';
  ELSE
    RAISE EXCEPTION 'Invalid campaign type';
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION ad_resume_campaign(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION ad_resume_campaign(uuid, text) TO authenticated;

-- ---------- ad_stop_campaign ----------
CREATE OR REPLACE FUNCTION ad_stop_campaign(p_campaign_id uuid, p_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_owner uuid;
  v_budget numeric(18,8);
  v_spent numeric(18,8);
  v_refund numeric(18,8);
  v_ref text;
BEGIN
  IF p_type = 'ptc' THEN
    SELECT advertiser_id, budget, spent INTO v_owner, v_budget, v_spent FROM ptc_ads WHERE id = p_campaign_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Campaign not found'; END IF;
    IF v_owner != auth.uid() THEN RAISE EXCEPTION 'Not authorized'; END IF;
    v_refund := v_budget - v_spent;
    UPDATE ptc_ads SET status = 'completed', active = false WHERE id = p_campaign_id;
    IF v_refund > 0 THEN
      UPDATE profiles SET advertising_balance = advertising_balance + v_refund WHERE id = auth.uid();
      v_ref := 'ad_refund:ptc:' || p_campaign_id::text;
      INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
        VALUES (auth.uid(), 'ad_refund', v_refund, 'ptc_ad', p_campaign_id, v_ref,
          'PTC campaign refund (unspent budget)', 'completed')
        ON CONFLICT (reference) DO NOTHING;
    END IF;
  ELSIF p_type = 'task' THEN
    SELECT advertiser_id, budget, spent INTO v_owner, v_budget, v_spent FROM tasks WHERE id = p_campaign_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Campaign not found'; END IF;
    IF v_owner != auth.uid() THEN RAISE EXCEPTION 'Not authorized'; END IF;
    v_refund := v_budget - v_spent;
    UPDATE tasks SET status = 'completed', active = false WHERE id = p_campaign_id;
    IF v_refund > 0 THEN
      UPDATE profiles SET advertising_balance = advertising_balance + v_refund WHERE id = auth.uid();
      v_ref := 'ad_refund:task:' || p_campaign_id::text;
      INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
        VALUES (auth.uid(), 'ad_refund', v_refund, 'task', p_campaign_id, v_ref,
          'Task campaign refund (unspent budget)', 'completed')
        ON CONFLICT (reference) DO NOTHING;
    END IF;
  ELSE
    RAISE EXCEPTION 'Invalid campaign type';
  END IF;
  RETURN jsonb_build_object('ok', true, 'refund', v_refund);
END;
$$;

REVOKE EXECUTE ON FUNCTION ad_stop_campaign(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION ad_stop_campaign(uuid, text) TO authenticated;

-- ---------- ad_get_dashboard ----------
CREATE OR REPLACE FUNCTION ad_get_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_ptc_total integer;
  v_ptc_active integer;
  v_task_total integer;
  v_task_active integer;
  v_total_budget numeric(18,8);
  v_total_spent numeric(18,8);
  v_ptc_views integer;
  v_task_completions integer;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT count(*), count(*) FILTER (WHERE status = 'active'),
    COALESCE(sum(budget), 0), COALESCE(sum(spent), 0), COALESCE(sum(total_views), 0)
    INTO v_ptc_total, v_ptc_active, v_total_budget, v_total_spent, v_ptc_views
    FROM ptc_ads WHERE advertiser_id = auth.uid();

  SELECT count(*), count(*) FILTER (WHERE status = 'active'),
    COALESCE(sum(total_completions), 0)
    INTO v_task_total, v_task_active, v_task_completions
    FROM tasks WHERE advertiser_id = auth.uid();

  SELECT count(*), COALESCE(sum(budget), 0), COALESCE(sum(spent), 0)
    INTO v_task_total, v_total_budget, v_total_spent
    FROM tasks WHERE advertiser_id = auth.uid();

  RETURN jsonb_build_object(
    'advertising_balance', v_profile.advertising_balance,
    'ptc_campaigns', v_ptc_total,
    'ptc_active', v_ptc_active,
    'task_campaigns', v_task_total,
    'task_active', v_task_active,
    'total_budget', v_total_budget,
    'total_spent', v_total_spent,
    'ptc_views', v_ptc_views,
    'task_completions', v_task_completions
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION ad_get_dashboard() FROM anon;
GRANT EXECUTE ON FUNCTION ad_get_dashboard() TO authenticated;

-- ---------- ad_list_campaigns ----------
CREATE OR REPLACE FUNCTION ad_list_campaigns()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  RETURN jsonb_build_object(
    'ptc_campaigns', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'title', title, 'category', category, 'reward', reward,
        'duration_seconds', duration_seconds, 'budget', budget, 'spent', spent,
        'status', status, 'active', active, 'total_views', total_views,
        'daily_view_limit', daily_view_limit, 'total_view_limit', total_view_limit,
        'created_at', created_at
      ) ORDER BY created_at DESC)
      FROM ptc_ads WHERE advertiser_id = auth.uid()
    ),
    'task_campaigns', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'title', title, 'category', category, 'reward', reward,
        'task_type', task_type, 'budget', budget, 'spent', spent,
        'status', status, 'active', active, 'total_completions', total_completions,
        'daily_limit', daily_limit, 'total_limit', total_limit,
        'created_at', created_at
      ) ORDER BY created_at DESC)
      FROM tasks WHERE advertiser_id = auth.uid()
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION ad_list_campaigns() FROM anon;
GRANT EXECUTE ON FUNCTION ad_list_campaigns() TO authenticated;
