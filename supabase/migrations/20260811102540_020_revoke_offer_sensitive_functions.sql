/*
# Revoke EXECUTE on sensitive offer functions from anon and authenticated

## Purpose
The security advisor flagged that `offer_process_conversion` and
`offer_get_postback_secret` are callable by the `anon` and `authenticated`
roles. These functions are the authoritative reward-crediting and
secret-decryption paths — they must ONLY be callable by the service role
(edge function), never by any client.

`REVOKE ... FROM PUBLIC` removes the default grant, but Supabase's `anon`
and `authenticated` roles may retain direct grants. This migration explicitly
revokes from both roles.

## Changes
- REVOKE EXECUTE on `offer_process_conversion` FROM anon, authenticated
- REVOKE EXECUTE on `offer_get_postback_secret` FROM anon, authenticated

No other functions are affected. User-facing functions
(`offer_start_session`, `offer_list_available`, etc.) remain granted to
`authenticated` only — they are safe because they check `auth.uid()` internally.
*/

REVOKE EXECUTE ON FUNCTION offer_process_conversion(text, text, text, numeric, numeric, text, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION offer_process_conversion(text, text, text, numeric, numeric, text, jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION offer_process_conversion(text, text, text, numeric, numeric, text, jsonb) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION offer_get_postback_secret(text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION offer_get_postback_secret(text, text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION offer_get_postback_secret(text, text) FROM PUBLIC;
