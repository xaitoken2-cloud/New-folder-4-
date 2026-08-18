/*
# PTC Ad Country-Eligibility Filtering

1. Purpose
   listPtcAds() and getPtcAd() currently use raw SELECT on ptc_ads, leaking
   country-restricted ads to ineligible users. These RPCs filter server-side
   using the exact same country check from ptc_start (migration 039).
   Device targeting is NOT filtered here — it stays a ptc_start-only check.

2. Security
   - Both functions SECURITY DEFINER, revoked from anon, granted to authenticated.
   - Reuse ptc_start's country check: IF NOT target_all_countries AND
     (country IS NULL/'' OR not in ptc_ad_countries) → exclude.

3. Scope
   - Only affects user-facing PTC listing and detail views.
   - Does NOT change ptc_ads RLS, ptc_start, tasks, or advertiser/admin RPCs.
*/

CREATE OR REPLACE FUNCTION public.list_available_ptc_ads()
RETURNS SETOF ptc_ads
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_country text;
BEGIN
  SELECT country INTO v_country FROM profiles WHERE id = auth.uid();

  RETURN QUERY
  SELECT a.*
  FROM ptc_ads a
  WHERE a.active = true
    AND (
      a.target_all_countries = true
      OR (
        v_country IS NOT NULL
        AND v_country <> ''
        AND EXISTS (
          SELECT 1 FROM ptc_ad_countries pac
          WHERE pac.ptc_ad_id = a.id AND upper(pac.country_code) = upper(v_country)
        )
      )
    )
  ORDER BY a.created_at DESC;
END;
$function$;

REVOKE EXECUTE ON FUNCTION list_available_ptc_ads() FROM anon;
GRANT EXECUTE ON FUNCTION list_available_ptc_ads() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_available_ptc_ad(p_ad_id uuid)
RETURNS ptc_ads
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_country text;
  v_ad ptc_ads%ROWTYPE;
BEGIN
  SELECT country INTO v_country FROM profiles WHERE id = auth.uid();

  SELECT a.* INTO v_ad
  FROM ptc_ads a
  WHERE a.id = p_ad_id
    AND a.active = true
    AND (
      a.target_all_countries = true
      OR (
        v_country IS NOT NULL
        AND v_country <> ''
        AND EXISTS (
          SELECT 1 FROM ptc_ad_countries pac
          WHERE pac.ptc_ad_id = a.id AND upper(pac.country_code) = upper(v_country)
        )
      )
    );

  RETURN v_ad;
END;
$function$;

REVOKE EXECUTE ON FUNCTION get_available_ptc_ad(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION get_available_ptc_ad(uuid) TO authenticated;