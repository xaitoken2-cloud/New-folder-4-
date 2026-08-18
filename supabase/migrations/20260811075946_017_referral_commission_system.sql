/*
# Referral commission system (replaces flat referral_reward)

1. Schema
- Add referral_commission_percent (default 5) and referral_deposit_commission_percent
  (default 2) to app_settings. Old referral_reward / referral_qualification columns
  are left in place for backward compatibility but no longer used by new logic.

2. New function
- credit_referral_commission(p_referred_id, p_source_amount, p_source_type, p_source_ref)
  SECURITY DEFINER, search_path = public. Looks up the referral row for the referred
  user, picks the rate based on source type, computes commission, inserts a unique
  'referral_reward' ledger transaction (idempotent via ON CONFLICT on reference), and
  if inserted, credits the referrer's balance/total_earned/referral_earned and updates
  the referral row's reward_amount + qualified flag.

3. Updated functions
- ptc_claim: after crediting the viewer, PERFORM credit_referral_commission for PTC.
- task_submit auto-approve branch: after crediting the submitter, PERFORM for task.
- admin_review_task approve branch: after crediting the submitter, PERFORM for task.
- approve_deposit: after crediting the depositor, PERFORM for deposit.
- admin_update_settings: accept new percentage params instead of reward/qualification.
- qualify_referral: dropped (superseded by credit_referral_commission).
*/

-- ---------- new app_settings columns ----------
ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS referral_commission_percent numeric(5,2) NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS referral_deposit_commission_percent numeric(5,2) NOT NULL DEFAULT 2;

-- ---------- credit_referral_commission ----------
CREATE OR REPLACE FUNCTION credit_referral_commission(
  p_referred_id uuid,
  p_source_amount numeric,
  p_source_type text,
  p_source_ref text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_referral referrals%ROWTYPE;
  v_rate numeric;
  v_commission numeric;
  v_ref text;
  v_tx_id uuid;
BEGIN
  SELECT * INTO v_referral FROM referrals WHERE referred_id = p_referred_id LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;

  CASE p_source_type
    WHEN 'ptc_reward' THEN
      SELECT referral_commission_percent INTO v_rate FROM app_settings WHERE id = 1;
    WHEN 'task_reward' THEN
      SELECT referral_commission_percent INTO v_rate FROM app_settings WHERE id = 1;
    WHEN 'deposit' THEN
      SELECT referral_deposit_commission_percent INTO v_rate FROM app_settings WHERE id = 1;
    ELSE
      RETURN;
  END CASE;

  IF v_rate IS NULL OR v_rate <= 0 THEN RETURN; END IF;

  v_commission := round(p_source_amount * v_rate / 100, 8);
  IF v_commission <= 0 THEN RETURN; END IF;

  v_ref := 'refcomm:' || p_source_ref;

  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (
      v_referral.referrer_id,
      'referral_reward',
      v_commission,
      'referral',
      v_referral.id,
      v_ref,
      'Referral commission ' || v_rate || '%',
      'completed'
    )
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

  IF v_tx_id IS NOT NULL THEN
    UPDATE profiles
      SET available_balance = available_balance + v_commission,
          total_earned = total_earned + v_commission,
          referral_earned = referral_earned + v_commission
      WHERE id = v_referral.referrer_id;

    UPDATE referrals
      SET reward_amount = reward_amount + v_commission,
          qualified = true,
          qualified_at = COALESCE(qualified_at, now())
      WHERE id = v_referral.id;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION credit_referral_commission(uuid, numeric, text, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION credit_referral_commission(uuid, numeric, text, text) TO authenticated;

-- ---------- drop qualify_referral ----------
DROP FUNCTION IF EXISTS qualify_referral(uuid);

-- ---------- ptc_claim (add commission) ----------
CREATE OR REPLACE FUNCTION ptc_claim(p_view_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_view ptc_ad_views%ROWTYPE;
  v_ad ptc_ads%ROWTYPE;
  v_profile profiles%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
  v_elapsed numeric;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

  SELECT * INTO v_view FROM ptc_ad_views WHERE id = p_view_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'View session not found'; END IF;
  IF v_view.user_id != auth.uid() THEN RAISE EXCEPTION 'View does not belong to you'; END IF;
  IF v_view.status = 'completed' THEN RAISE EXCEPTION 'Reward already claimed'; END IF;
  IF v_view.status = 'expired' OR v_view.status = 'cancelled' THEN RAISE EXCEPTION 'View session is no longer valid'; END IF;

  v_elapsed := extract(epoch from (now() - v_view.started_at));
  IF v_elapsed < v_view.required_duration THEN
    RAISE EXCEPTION 'View duration not yet satisfied (elapsed %, required %)', v_elapsed, v_view.required_duration;
  END IF;

  SELECT * INTO v_ad FROM ptc_ads WHERE id = v_view.ptc_ad_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Advertisement not found'; END IF;
  IF NOT v_ad.active THEN RAISE EXCEPTION 'Advertisement is no longer active'; END IF;
  IF v_ad.end_date IS NOT NULL AND now() > v_ad.end_date THEN RAISE EXCEPTION 'Advertisement has expired'; END IF;
  IF v_ad.total_view_limit > 0 AND v_ad.total_views >= v_ad.total_view_limit THEN
    RAISE EXCEPTION 'Total view limit reached for this advertisement';
  END IF;

  v_ref := 'ptc:' || v_view.id::text;

  UPDATE ptc_ad_views SET status = 'completed', completed_at = now() WHERE id = p_view_id;

  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (auth.uid(), 'ptc_reward', v_view.reward, 'ptc_ad_view', v_view.id, v_ref, 'PTC advertisement reward', 'completed')
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

  IF v_tx_id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'already_claimed', true, 'reward', v_view.reward);
  END IF;

  UPDATE profiles
    SET available_balance = available_balance + v_view.reward,
        total_earned = total_earned + v_view.reward,
        ptc_views = ptc_views + 1
    WHERE id = auth.uid();

  UPDATE ptc_ads SET total_views = total_views + 1 WHERE id = v_ad.id;

  PERFORM credit_referral_commission(auth.uid(), v_view.reward, 'ptc_reward', v_ref);

  RETURN jsonb_build_object(
    'ok', true,
    'reward', v_view.reward,
    'transaction_id', v_tx_id,
    'completed_at', now()
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION ptc_claim(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION ptc_claim(uuid) TO authenticated;

-- ---------- task_submit (add commission on auto-approve) ----------
CREATE OR REPLACE FUNCTION task_submit(p_task_id uuid, p_proof_text text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_task tasks%ROWTYPE;
  v_profile profiles%ROWTYPE;
  v_completion task_completions%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
  v_today_count integer;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_profile.status != 'active' THEN RAISE EXCEPTION 'Account is not active'; END IF;

  SELECT * INTO v_task FROM tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found'; END IF;
  IF NOT v_task.active THEN RAISE EXCEPTION 'Task is not active'; END IF;
  IF v_task.start_date IS NOT NULL AND now() < v_task.start_date THEN RAISE EXCEPTION 'Task not yet available'; END IF;
  IF v_task.end_date IS NOT NULL AND now() > v_task.end_date THEN RAISE EXCEPTION 'Task has expired'; END IF;
  IF v_task.total_limit > 0 AND v_task.total_completions >= v_task.total_limit THEN
    RAISE EXCEPTION 'Task completion limit reached';
  END IF;

  IF v_task.daily_limit > 0 THEN
    SELECT count(*) INTO v_today_count FROM task_completions
      WHERE user_id = auth.uid() AND task_id = p_task_id
        AND date_trunc('day', created_at) = current_date;
    IF v_today_count >= v_task.daily_limit THEN RAISE EXCEPTION 'Daily limit reached for this task'; END IF;
  END IF;

  INSERT INTO task_completions (user_id, task_id, proof_text, reward, status)
    VALUES (auth.uid(), p_task_id, COALESCE(p_proof_text, ''), v_task.reward,
      CASE WHEN v_task.proof_required THEN 'pending' ELSE 'approved' END)
    ON CONFLICT (user_id, task_id) DO NOTHING
    RETURNING * INTO v_completion;

  IF v_completion IS NULL THEN
    RAISE EXCEPTION 'You have already submitted this task';
  END IF;

  UPDATE tasks SET total_completions = total_completions + 1 WHERE id = p_task_id;

  IF NOT v_task.proof_required THEN
    v_ref := 'task:' || v_completion.id::text;
    INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
      VALUES (auth.uid(), 'task_reward', v_task.reward, 'task_completion', v_completion.id, v_ref, 'Task reward', 'completed')
      ON CONFLICT (reference) DO NOTHING
      RETURNING id INTO v_tx_id;

    IF v_tx_id IS NOT NULL THEN
      UPDATE profiles
        SET available_balance = available_balance + v_task.reward,
            total_earned = total_earned + v_task.reward,
            tasks_completed = tasks_completed + 1
        WHERE id = auth.uid();
      PERFORM credit_referral_commission(auth.uid(), v_task.reward, 'task_reward', v_ref);
    END IF;
    RETURN jsonb_build_object('ok', true, 'status', 'approved', 'reward', v_task.reward, 'completion_id', v_completion.id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 'pending', 'completion_id', v_completion.id);
END;
$$;

REVOKE EXECUTE ON FUNCTION task_submit(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION task_submit(uuid, text) TO authenticated;

-- ---------- admin_review_task (add commission on approve) ----------
CREATE OR REPLACE FUNCTION admin_review_task(p_completion_id uuid, p_approve boolean, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_completion task_completions%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT * INTO v_completion FROM task_completions WHERE id = p_completion_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task completion not found'; END IF;
  IF v_completion.status != 'pending' THEN RAISE EXCEPTION 'Task already reviewed'; END IF;

  IF p_approve THEN
    v_ref := 'task:' || v_completion.id::text;
    INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
      VALUES (v_completion.user_id, 'task_reward', v_completion.reward, 'task_completion', v_completion.id, v_ref, 'Task reward (approved)', 'completed')
      ON CONFLICT (reference) DO NOTHING
      RETURNING id INTO v_tx_id;

    IF v_tx_id IS NOT NULL THEN
      UPDATE profiles
        SET available_balance = available_balance + v_completion.reward,
            total_earned = total_earned + v_completion.reward,
            tasks_completed = tasks_completed + 1
        WHERE id = v_completion.user_id;
      PERFORM credit_referral_commission(v_completion.user_id, v_completion.reward, 'task_reward', v_ref);
    END IF;

    UPDATE task_completions SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
      WHERE id = p_completion_id;
    INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
      VALUES (auth.uid(), 'approve_task', 'task_completion', p_completion_id::text, jsonb_build_object('reward', v_completion.reward));
    RETURN jsonb_build_object('ok', true, 'status', 'approved');
  ELSE
    UPDATE task_completions SET status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
      WHERE id = p_completion_id;
    INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
      VALUES (auth.uid(), 'reject_task', 'task_completion', p_completion_id::text, jsonb_build_object('note', p_note));
    RETURN jsonb_build_object('ok', true, 'status', 'rejected');
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_review_task(uuid, boolean, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_review_task(uuid, boolean, text) TO authenticated;

-- ---------- approve_deposit (add commission) ----------
CREATE OR REPLACE FUNCTION approve_deposit(p_deposit_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_deposit deposits%ROWTYPE;
  v_ref text;
  v_tx_id uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;

  SELECT * INTO v_deposit FROM deposits WHERE id = p_deposit_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Deposit not found'; END IF;
  IF v_deposit.status = 'approved' THEN RETURN jsonb_build_object('ok', true, 'already_approved', true); END IF;
  IF v_deposit.status != 'pending' THEN RAISE EXCEPTION 'Deposit is not pending (status: %)', v_deposit.status; END IF;

  v_ref := 'deposit:' || v_deposit.id::text;
  INSERT INTO transactions (user_id, type, amount, reference_type, reference_id, reference, description, status)
    VALUES (v_deposit.user_id, 'deposit', v_deposit.amount, 'deposit', v_deposit.id, v_ref, 'Deposit approved', 'completed')
    ON CONFLICT (reference) DO NOTHING
    RETURNING id INTO v_tx_id;

  IF v_tx_id IS NOT NULL THEN
    UPDATE profiles
      SET available_balance = available_balance + v_deposit.amount,
          total_deposited = total_deposited + v_deposit.amount
      WHERE id = v_deposit.user_id;
    PERFORM credit_referral_commission(v_deposit.user_id, v_deposit.amount, 'deposit', v_ref);
  END IF;

  UPDATE deposits SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
    WHERE id = p_deposit_id;

  INSERT INTO audit_logs (actor_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'approve_deposit', 'deposit', p_deposit_id::text,
      jsonb_build_object('amount', v_deposit.amount, 'user_id', v_deposit.user_id));

  RETURN jsonb_build_object('ok', true, 'transaction_id', v_tx_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION approve_deposit(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION approve_deposit(uuid) TO authenticated;

-- ---------- admin_update_settings (new percentage params) ----------
CREATE OR REPLACE FUNCTION admin_update_settings(
  p_referral_commission_percent numeric,
  p_referral_deposit_commission_percent numeric,
  p_min_withdrawal numeric,
  p_max_withdrawal numeric,
  p_withdrawal_cooldown_minutes integer,
  p_ptc_daily_limit_per_ad integer,
  p_task_daily_limit integer,
  p_platform_name text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  UPDATE app_settings SET
    referral_commission_percent = COALESCE(p_referral_commission_percent, referral_commission_percent),
    referral_deposit_commission_percent = COALESCE(p_referral_deposit_commission_percent, referral_deposit_commission_percent),
    min_withdrawal = COALESCE(p_min_withdrawal, min_withdrawal),
    max_withdrawal = COALESCE(p_max_withdrawal, max_withdrawal),
    withdrawal_cooldown_minutes = COALESCE(p_withdrawal_cooldown_minutes, withdrawal_cooldown_minutes),
    ptc_daily_limit_per_ad = COALESCE(p_ptc_daily_limit_per_ad, ptc_daily_limit_per_ad),
    task_daily_limit = COALESCE(p_task_daily_limit, task_daily_limit),
    platform_name = COALESCE(p_platform_name, platform_name),
    updated_at = now()
    WHERE id = 1;
  INSERT INTO audit_logs (actor_id, action, target_type, details)
    VALUES (auth.uid(), 'update_settings', 'app_settings', jsonb_build_object('platform_name', p_platform_name));
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_update_settings(numeric, numeric, numeric, numeric, integer, integer, integer, text) FROM anon;
GRANT EXECUTE ON FUNCTION admin_update_settings(numeric, numeric, numeric, numeric, integer, integer, integer, text) TO authenticated;
