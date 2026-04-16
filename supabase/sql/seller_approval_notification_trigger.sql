-- Creates a notifications table if it doesn't exist yet
CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type text NOT NULL,
  title text NOT NULL,
  message text NOT NULL,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Trigger function: inserts a notification when seller status changes
CREATE OR REPLACE FUNCTION notify_seller_on_status_change()
RETURNS TRIGGER AS $$
BEGIN
  -- Only fire when status actually changes to approved or rejected
  IF NEW.approval_status IS DISTINCT FROM OLD.approval_status AND NEW.approval_status IN ('approved', 'rejected') THEN
    INSERT INTO notifications (user_id, type, title, message)
    VALUES (
      NEW.user_id,
      CASE NEW.approval_status
        WHEN 'approved' THEN 'seller_approved'
        ELSE 'seller_rejected'
      END,
      CASE NEW.approval_status
        WHEN 'approved' THEN 'Seller Account Approved'
        ELSE 'Seller Application Denied'
      END,
      CASE NEW.approval_status
        WHEN 'approved' THEN 'Congratulations! Your seller account has been approved. You can now start selling on QuickCart.'
        ELSE 'Your seller application was not approved at this time. Please contact support for more details.'
      END
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger to seller_profiles
DROP TRIGGER IF EXISTS seller_status_notification_trigger ON seller_profiles;
CREATE TRIGGER seller_status_notification_trigger
  AFTER UPDATE OF approval_status ON seller_profiles
  FOR EACH ROW
  EXECUTE FUNCTION notify_seller_on_status_change();
