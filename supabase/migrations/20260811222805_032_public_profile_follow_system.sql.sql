-- =====================================================
-- Public User Profile + Follow System (Phase 1)
--
-- Adds:
-- 1. profiles.bio + profiles.last_seen_at (nullable, no existing column touched)
-- 2. follows table with RLS (SELECT open to authenticated, writes via functions only)
-- 3. SECURITY DEFINER functions: get_public_profile, follow_user, unfollow_user,
--    list_followers, list_following — same pattern as xc_lookup_recipient (migration 027).
--
-- profiles RLS is NOT modified. The existing profiles_select_own policy stays intact.
-- =====================================================

-- =====================================================
-- 1. Extend profiles with bio + last_seen_at
-- =====================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS bio text DEFAULT '';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS last_seen_at timestamptz;

-- =====================================================
-- 2. follows table
-- =====================================================

CREATE TABLE IF NOT EXISTS follows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  following_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (follower_id, following_id),
  CHECK (follower_id <> following_id)
);

CREATE INDEX IF NOT EXISTS follows_follower_idx ON follows (follower_id);
CREATE INDEX IF NOT EXISTS follows_following_idx ON follows (following_id);

ALTER TABLE follows ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "follows_select_all" ON follows;
CREATE POLICY "follows_select_all" ON follows FOR SELECT
  TO authenticated USING (true);

-- No INSERT/UPDATE/DELETE policies: direct table writes are blocked.
-- All writes go through SECURITY DEFINER functions below.

-- =====================================================
-- 3. get_public_profile — safe public profile lookup by username
-- =====================================================

CREATE OR REPLACE FUNCTION get_public_profile(p_username text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile profiles%ROWTYPE;
  v_self_id uuid;
  v_follower_count int;
  v_following_count int;
  v_is_following boolean := false;
BEGIN
  v_self_id := auth.uid();
  IF v_self_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_username IS NULL OR btrim(p_username) = '' THEN
    RAISE EXCEPTION 'Username is required';
  END IF;

  SELECT * INTO v_profile FROM profiles
    WHERE lower(username) = lower(btrim(p_username))
    LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', false);
  END IF;

  SELECT count(*) INTO v_follower_count FROM follows WHERE following_id = v_profile.id;
  SELECT count(*) INTO v_following_count FROM follows WHERE follower_id = v_profile.id;

  IF v_self_id <> v_profile.id THEN
    SELECT EXISTS(
      SELECT 1 FROM follows WHERE follower_id = v_self_id AND following_id = v_profile.id
    ) INTO v_is_following;
  END IF;

  RETURN jsonb_build_object(
    'found', true,
    'username', v_profile.username,
    'bio', coalesce(v_profile.bio, ''),
    'country', v_profile.country,
    'avatar_url', v_profile.avatar_url,
    'xc_balance', v_profile.xc_balance,
    'created_at', v_profile.created_at,
    'last_seen_at', v_profile.last_seen_at,
    'follower_count', v_follower_count,
    'following_count', v_following_count,
    'is_following', v_is_following,
    'is_self', v_self_id = v_profile.id
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION get_public_profile(text) FROM anon;
GRANT EXECUTE ON FUNCTION get_public_profile(text) TO authenticated;

-- =====================================================
-- 4. follow_user — idempotent follow
-- =====================================================

CREATE OR REPLACE FUNCTION follow_user(p_username text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_self_id uuid;
  v_target_id uuid;
  v_follower_count int;
BEGIN
  v_self_id := auth.uid();
  IF v_self_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_username IS NULL OR btrim(p_username) = '' THEN
    RAISE EXCEPTION 'Username is required';
  END IF;

  SELECT id INTO v_target_id FROM profiles
    WHERE lower(username) = lower(btrim(p_username))
    LIMIT 1;

  IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;

  IF v_target_id = v_self_id THEN
    RAISE EXCEPTION 'You cannot follow yourself';
  END IF;

  INSERT INTO follows (follower_id, following_id)
    VALUES (v_self_id, v_target_id)
    ON CONFLICT (follower_id, following_id) DO NOTHING;

  SELECT count(*) INTO v_follower_count FROM follows WHERE following_id = v_target_id;

  RETURN jsonb_build_object(
    'ok', true,
    'follower_count', v_follower_count
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION follow_user(text) FROM anon;
GRANT EXECUTE ON FUNCTION follow_user(text) TO authenticated;

-- =====================================================
-- 5. unfollow_user — idempotent unfollow
-- =====================================================

CREATE OR REPLACE FUNCTION unfollow_user(p_username text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_self_id uuid;
  v_target_id uuid;
  v_follower_count int;
BEGIN
  v_self_id := auth.uid();
  IF v_self_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_username IS NULL OR btrim(p_username) = '' THEN
    RAISE EXCEPTION 'Username is required';
  END IF;

  SELECT id INTO v_target_id FROM profiles
    WHERE lower(username) = lower(btrim(p_username))
    LIMIT 1;

  IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;

  DELETE FROM follows
    WHERE follower_id = v_self_id AND following_id = v_target_id;

  SELECT count(*) INTO v_follower_count FROM follows WHERE following_id = v_target_id;

  RETURN jsonb_build_object(
    'ok', true,
    'follower_count', v_follower_count
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION unfollow_user(text) FROM anon;
GRANT EXECUTE ON FUNCTION unfollow_user(text) TO authenticated;

-- =====================================================
-- 6. list_followers — paginated followers of a user
-- =====================================================

CREATE OR REPLACE FUNCTION list_followers(
  p_username text,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_self_id uuid;
  v_target_id uuid;
BEGIN
  v_self_id := auth.uid();
  IF v_self_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_username IS NULL OR btrim(p_username) = '' THEN
    RAISE EXCEPTION 'Username is required';
  END IF;

  SELECT id INTO v_target_id FROM profiles
    WHERE lower(username) = lower(btrim(p_username))
    LIMIT 1;

  IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;

  RETURN COALESCE(jsonb_agg(jsonb_build_object(
    'username', p.username,
    'avatar_url', p.avatar_url,
    'is_following', EXISTS(
      SELECT 1 FROM follows f2
      WHERE f2.follower_id = v_self_id AND f2.following_id = p.id
    )
  ) ORDER BY p.username), '[]'::jsonb)
  FROM follows f
  JOIN profiles p ON p.id = f.follower_id
  WHERE f.following_id = v_target_id
  LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE EXECUTE ON FUNCTION list_followers(text, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION list_followers(text, integer, integer) TO authenticated;

-- =====================================================
-- 7. list_following — paginated users a user is following
-- =====================================================

CREATE OR REPLACE FUNCTION list_following(
  p_username text,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_self_id uuid;
  v_target_id uuid;
BEGIN
  v_self_id := auth.uid();
  IF v_self_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_username IS NULL OR btrim(p_username) = '' THEN
    RAISE EXCEPTION 'Username is required';
  END IF;

  SELECT id INTO v_target_id FROM profiles
    WHERE lower(username) = lower(btrim(p_username))
    LIMIT 1;

  IF NOT FOUND THEN RAISE EXCEPTION 'User not found'; END IF;

  RETURN COALESCE(jsonb_agg(jsonb_build_object(
    'username', p.username,
    'avatar_url', p.avatar_url,
    'is_following', EXISTS(
      SELECT 1 FROM follows f2
      WHERE f2.follower_id = v_self_id AND f2.following_id = p.id
    )
  ) ORDER BY p.username), '[]'::jsonb)
  FROM follows f
  JOIN profiles p ON p.id = f.following_id
  WHERE f.follower_id = v_target_id
  LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE EXECUTE ON FUNCTION list_following(text, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION list_following(text, integer, integer) TO authenticated;