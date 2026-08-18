-- Campaign images storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('campaign-images', 'campaign-images', true, 2097152,
        ARRAY['image/jpeg','image/png','image/webp','image/gif'])
ON CONFLICT (id) DO NOTHING;

-- RLS: each authenticated user can upload/delete only inside their own folder
CREATE POLICY "campaign_images_insert_own" ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'campaign-images' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "campaign_images_select_public" ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'campaign-images');

CREATE POLICY "campaign_images_delete_own" ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'campaign-images' AND (storage.foldername(name))[1] = auth.uid()::text);
