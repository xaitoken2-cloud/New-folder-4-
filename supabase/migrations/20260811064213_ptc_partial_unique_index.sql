-- Replace the full unique index with a partial one that only covers
-- pending and completed sessions. Cancelled/expired sessions should not
-- block a user from starting a new view for the same ad on the same day.

DROP INDEX IF EXISTS ptc_ad_views_user_ad_date_idx;

CREATE UNIQUE INDEX ptc_ad_views_user_ad_date_idx
  ON ptc_ad_views (user_id, ptc_ad_id, view_date)
  WHERE status IN ('pending', 'completed');