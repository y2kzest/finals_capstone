-- Allow buyers to cancel their own orders while still pending.
-- USING: the row must belong to this buyer AND be in 'pending' status.
-- WITH CHECK: after the update the row must still belong to this buyer
--             AND status must be 'cancelled' (no other field can be
--             sneaked in to change ownership or jump to another status).
DROP POLICY IF EXISTS "Buyers can cancel own orders" ON public.orders;
CREATE POLICY "Buyers can cancel own orders"
ON public.orders FOR UPDATE
TO authenticated
USING  (buyer_id = auth.uid() AND status = 'pending')
WITH CHECK (buyer_id = auth.uid() AND status = 'cancelled');
