-- Add xc_total_earned to get_dashboard so the Total Earned card can show XC
CREATE OR REPLACE FUNCTION get_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_today_earned numeric;
  v_referral_earned numeric;
  v_pending_count integer;
  v_series jsonb;
  v_xc_today_earned numeric;
  v_xc_total_earned numeric;
BEGIN
  SELECT * INTO v_profile FROM profiles WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT COALESCE(sum(amount), 0) INTO v_today_earned FROM transactions
  WHERE user_id = auth.uid() AND amount > 0 AND currency = 'USD'
    AND date_trunc('day', created_at) = current_date;

  SELECT COALESCE(sum(amount), 0) INTO v_xc_today_earned FROM transactions
  WHERE user_id = auth.uid() AND amount > 0 AND currency = 'XC'
    AND date_trunc('day', created_at) = current_date;

  SELECT COALESCE(sum(amount), 0) INTO v_xc_total_earned FROM transactions
  WHERE user_id = auth.uid() AND amount > 0 AND currency = 'XC';

  SELECT COALESCE(sum(amount), 0) INTO v_referral_earned FROM transactions
  WHERE user_id = auth.uid() AND type = 'referral_reward' AND status = 'completed';

  SELECT count(*) INTO v_pending_count FROM withdrawals WHERE user_id = auth.uid() AND status = 'pending';

  SELECT COALESCE(jsonb_agg(jsonb_build_object('date', d, 'amount', coalesce(amt, 0)) ORDER BY d), '[]'::jsonb) INTO v_series
  FROM (
    SELECT generate_series(current_date - interval '6 days', current_date, '1 day')::date AS d
  ) days
  LEFT JOIN LATERAL (
    SELECT sum(amount) AS amt FROM transactions
    WHERE user_id = auth.uid() AND amount > 0 AND currency = 'XC'
      AND date_trunc('day', created_at) = d::timestamptz
  ) s ON true;

  RETURN jsonb_build_object(
    'available_balance', v_profile.available_balance,
    'pending_balance', v_profile.pending_balance,
    'xc_balance', v_profile.xc_balance,
    'total_earned', v_profile.total_earned,
    'xc_total_earned', v_xc_total_earned,
    'total_withdrawn', v_profile.total_withdrawn,
    'total_deposited', v_profile.total_deposited,
    'today_earned', v_today_earned,
    'xc_today_earned', v_xc_today_earned,
    'referral_earned', v_referral_earned,
    'ptc_views', v_profile.ptc_views,
    'tasks_completed', v_profile.tasks_completed,
    'pending_withdrawals', v_pending_count,
    'role', v_profile.role,
    'status', v_profile.status,
    'earnings_series', v_series
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION get_dashboard() FROM anon;
GRANT EXECUTE ON FUNCTION get_dashboard() TO authenticated;
