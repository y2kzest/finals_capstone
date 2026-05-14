-- Enable realtime inserts for the buyer notifications table so the app can
-- show a toast/popup the moment a row is created (e.g. order accepted,
-- payment received, etc.).
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END $$;
