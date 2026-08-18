/*
# Pay PTC/task referral commissions in XC instead of USD
1. Change
- credit_referral_commission() previously paid all referral commissions in USD
  (available_balance). PTC and task referral commissions now pay in XC
  (xc_balance), matching how ptc_claim/task_submit/admin_review_task pay the
  primary rewards. Deposit referral commissions remain in USD.
2. Details
- v_multiplier added to DECLARE; used for XC-source commission calculation and
  recorded in the transaction row.
- Commission calculation branches: XC sources use compute_xc_reward() * rate;
  deposits use the raw USD amount * rate (unchanged).
- transactions INSERT now records currency/usd_equivalent/base_usd_amount/
  reward_multiplier depending on source type.
- profiles UPDATE branches: XC sources credit xc_balance + total_earned (USD
  equivalent); deposits credit available_balance + total_earned (unchanged).
- referrals.reward_amount records the USD equivalent for all source types so
  the referral dashboard continues to display consistent USD totals.
*/
CREATE OR REPLACE FUNCTION public.credit_referral_commission(p_referred_id uuid, p_source_amount numeric, p_source_type text, p_source_ref text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
v_referral referrals%ROWTYPE;
v_rate numeric;
v_commission numeric;
v_ref text;
v_tx_id uuid;
v_multiplier numeric(18,8);
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

IF p_source_type IN ('ptc_reward', 'task_reward') THEN
  v_multiplier := (SELECT reward_multiplier FROM app_settings WHERE id = 1);
  v_commission := round(compute_xc_reward(p_source_amount) * v_rate / 100, 8);
ELSE
  v_commission := round(p_source_amount * v_rate / 100, 8);
END IF;
IF v_commission <= 0 THEN RETURN; END IF;

v_ref := 'refcomm:' || p_source_ref;

INSERT INTO transactions (
  user_id, type, amount, currency, usd_equivalent,
  base_usd_amount, reward_multiplier,
  reference_type, reference_id, reference, description, status
) VALUES (
  v_referral.referrer_id,
  'referral_reward',
  v_commission,
  CASE WHEN p_source_type IN ('ptc_reward','task_reward') THEN 'XC' ELSE 'USD' END,
  CASE WHEN p_source_type IN ('ptc_reward','task_reward') THEN round(p_source_amount * v_rate / 100, 8) ELSE NULL END,
  CASE WHEN p_source_type IN ('ptc_reward','task_reward') THEN round(p_source_amount * v_rate / 100, 8) ELSE NULL END,
  CASE WHEN p_source_type IN ('ptc_reward','task_reward') THEN v_multiplier ELSE NULL END,
  'referral', v_referral.id, v_ref,
  'Referral commission ' || v_rate || '%',
  'completed'
)
ON CONFLICT (reference) DO NOTHING
RETURNING id INTO v_tx_id;

IF v_tx_id IS NOT NULL THEN
IF p_source_type IN ('ptc_reward', 'task_reward') THEN
  UPDATE profiles
  SET xc_balance = xc_balance + v_commission,
  total_earned = total_earned + round(p_source_amount * v_rate / 100, 8),
  referral_earned = referral_earned + round(p_source_amount * v_rate / 100, 8)
  WHERE id = v_referral.referrer_id;
ELSE
  UPDATE profiles
  SET available_balance = available_balance + v_commission,
  total_earned = total_earned + v_commission,
  referral_earned = referral_earned + v_commission
  WHERE id = v_referral.referrer_id;
END IF;

UPDATE referrals
SET reward_amount = reward_amount + round(p_source_amount * v_rate / 100, 8),
qualified = true,
qualified_at = COALESCE(qualified_at, now())
WHERE id = v_referral.id;
END IF;
END;
$function$;