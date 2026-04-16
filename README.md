# caps_finals

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Seller Approval Email Notifications

This project now includes an app-side integration with a Supabase Edge Function
for seller approval emails.

### 1) Apply SQL migration

Run the SQL in `supabase/sql/seller_approval_status.sql` in Supabase SQL Editor.

Also run:

- `supabase/sql/vendor_admin_bridge_tables.sql`

This creates the `vendor_applications`, `vendor_profiles`, and `vendors` bridge
tables used to sync pending sellers to an external admin panel.

### 2) Deploy Edge Function

The function source is at:

- `supabase/functions/seller-approval-notifications/index.ts`

Deploy with Supabase CLI:

```bash
supabase functions deploy send-email
```

If you also keep a second function alias, you may deploy it too:

```bash
supabase functions deploy seller-approval-notifications
```

### 3) Set required secrets

Set these function secrets:

- `RESEND_API_KEY` (from Resend)
- `FROM_EMAIL` (example: `QuickCart <no-reply@yourdomain.com>`)

Example:

```bash
supabase secrets set RESEND_API_KEY=your_key
supabase secrets set FROM_EMAIL="QuickCart <no-reply@yourdomain.com>"
```

### 4) Approval flow

- Seller submits profile -> submission-received email is sent.
- Admin marks `approval_status` as `approved` in `seller_profiles`.
- Seller dashboard checks approval status via function and sends approval email once.
