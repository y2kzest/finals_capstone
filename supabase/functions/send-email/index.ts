import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

type NotificationAction =
  | 'submission_received'
  | 'check_and_notify_approval'
  | 'list_pending_sellers'
  | 'approve_seller'
  | 'sync_external_admin'
  | 'register_seller_candidate';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const action = (body?.action ?? '') as NotificationAction;

    if (!action) {
      return json({ error: 'Missing action' }, 400);
    }

    if (action === 'submission_received') {
      const email = String(body?.email ?? '').trim();
      const storeName = String(body?.storeName ?? 'your store').trim();

      if (!email) {
        return json({ error: 'Missing email' }, 400);
      }

      const sendResult = await sendEmail({
        to: email,
        subject: 'QuickCart Seller Application Received',
        html: `<p>Hi Seller,</p><p>We received your seller application for <strong>${escapeHtml(storeName)}</strong>.</p><p>Your application is now under review. You will receive another email once approved.</p><p>- QuickCart Team</p>`,
      });

      return json({
        ok: sendResult.ok,
        status: 'pending',
        message: sendResult.ok
          ? 'Submission email sent.'
          : `Email provider is not configured or delivery failed. ${sendResult.error ?? ''}`,
        resendStatus: sendResult.status,
      });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    if (action === 'register_seller_candidate') {
      const email = String(body?.email ?? '').trim().toLowerCase();
      const password = String(body?.password ?? '');
      let userId = String(body?.userId ?? '').trim();

      if (!email) {
        return json({ ok: false, message: 'Missing email' }, 400);
      }

      if (!userId) {
        if (!password) {
          return json({ ok: false, message: 'Missing password for user creation' }, 400);
        }

        if (password.length < 6) {
          return json({ ok: false, message: 'Password must be at least 6 characters' }, 400);
        }

        const { data: created, error: createError } = await adminClient.auth.admin.createUser({
          email,
          password,
          email_confirm: true,
          user_metadata: { role: 'seller' },
        });

        if (createError) {
          return json({ ok: false, message: createError.message }, 400);
        }

        userId = created.user?.id ?? '';
        if (!userId) {
          return json({ ok: false, message: 'Unable to create seller user' }, 500);
        }
      }

      await adminClient
        .from('user_roles')
        .upsert({ user_id: userId, role: 'seller' }, { onConflict: 'user_id' });

      const sellerName = email.split('@')[0];

      await adminClient
        .from('seller_profiles')
        .upsert(
          {
            user_id: userId,
            full_name: sellerName,
            store_name: sellerName,
            official_contact_email: email,
            approval_status: 'pending',
            is_profile_finalized: false,
          },
          { onConflict: 'user_id' },
        );

      const candidates = [
        {
          table: 'vendor_applications',
          payload: {
            user_id: userId,
            vendor_name: sellerName,
            email,
            stall_no: '',
            business_type: 'Retail Store',
            contact: email,
            status: 'pending',
          },
        },
        {
          table: 'vendor_profiles',
          payload: {
            user_id: userId,
            vendor_name: sellerName,
            email,
            stall_no: '',
            business_type: 'Retail Store',
            contact: email,
            status: 'pending',
          },
        },
        {
          table: 'vendors',
          payload: {
            user_id: userId,
            vendor_name: sellerName,
            email,
            stall_no: '',
            business_type: 'Retail Store',
            contact: email,
            status: 'pending',
          },
        },
      ];

      const syncedTables: string[] = [];
      const failedTables: Array<{ table: string; error: string }> = [];
      for (const candidate of candidates) {
        const { error } = await adminClient
          .from(candidate.table)
          .upsert(candidate.payload, { onConflict: 'user_id' });
        if (!error) {
          syncedTables.push(candidate.table);
        } else {
          failedTables.push({ table: candidate.table, error: error.message });
        }
      }

      return json({
        ok: true,
        message: 'Seller account created and queued for admin approval.',
        userId,
        syncedTables,
        failedTables,
      });
    }

    const authHeader = req.headers.get('Authorization') ?? '';
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      return json({ error: 'Unauthorized' }, 401);
    }

    const { data: roleRow } = await adminClient
      .from('user_roles')
      .select('role')
      .eq('user_id', user.id)
      .maybeSingle();

    const isAdmin = String(roleRow?.role ?? '').toLowerCase() === 'admin';

    if (action === 'list_pending_sellers') {
      if (!isAdmin) {
        return json({ error: 'Forbidden' }, 403);
      }

      const { data, error } = await adminClient
        .from('seller_profiles')
        .select('user_id, store_name, official_contact_email, approval_status, is_profile_finalized, created_at')
        .eq('is_profile_finalized', true)
        .neq('approval_status', 'approved')
        .order('created_at', { ascending: true });

      if (error) {
        return json({ error: error.message }, 400);
      }

      return json({ items: data ?? [] });
    }

    if (action === 'approve_seller') {
      if (!isAdmin) {
        return json({ error: 'Forbidden' }, 403);
      }

      const sellerUserId = String(body?.sellerUserId ?? '').trim();
      if (!sellerUserId) {
        return json({ error: 'Missing sellerUserId' }, 400);
      }

      const { data: sellerProfile, error: sellerError } = await adminClient
        .from('seller_profiles')
        .select('user_id, official_contact_email, store_name, store_information_final')
        .eq('user_id', sellerUserId)
        .maybeSingle();

      if (sellerError || !sellerProfile) {
        return json({ error: 'Seller profile not found' }, 404);
      }

      await adminClient
        .from('seller_profiles')
        .update({
          approval_status: 'approved',
          approval_email_sent_at: new Date().toISOString(),
        })
        .eq('user_id', sellerUserId);

      const to = String(sellerProfile.official_contact_email ?? '').trim();
      const storeName = String(
        sellerProfile.store_name ?? sellerProfile.store_information_final ?? 'your store',
      ).trim();

      const sent = to
        ? await sendEmail({
            to,
            subject: 'QuickCart Seller Account Approved',
            html: `<p>Great news!</p><p>Your seller account for <strong>${escapeHtml(storeName)}</strong> has been approved.</p><p>You can now fully use seller features in QuickCart.</p><p>- QuickCart Team</p>`,
          })
        : { ok: false, status: 0, error: 'Missing recipient email' };

      return json({
        ok: true,
        emailSent: sent.ok,
        sellerUserId,
        resendStatus: sent.status,
        resendError: sent.error ?? null,
      });
    }

    if (action === 'sync_external_admin') {
      const userId = String(body?.userId ?? user.id).trim();
      const storeName = String(body?.storeName ?? '').trim();
      const stallNo = String(body?.stallNo ?? '').trim();
      const businessType = String(body?.businessType ?? '').trim();
      const contactEmail = String(body?.contactEmail ?? user.email ?? '').trim();

      const candidates = [
        {
          table: 'vendor_applications',
          payload: {
            user_id: userId,
            vendor_name: storeName,
            email: contactEmail,
            stall_no: stallNo,
            business_type: businessType,
            contact: contactEmail,
            status: 'pending',
          },
        },
        {
          table: 'vendor_profiles',
          payload: {
            user_id: userId,
            vendor_name: storeName,
            email: contactEmail,
            stall_no: stallNo,
            business_type: businessType,
            contact: contactEmail,
            status: 'pending',
          },
        },
        {
          table: 'vendors',
          payload: {
            user_id: userId,
            vendor_name: storeName,
            email: contactEmail,
            stall_no: stallNo,
            business_type: businessType,
            contact: contactEmail,
            status: 'pending',
          },
        },
      ];

      const syncedTables: string[] = [];
      const failedTables: Array<{ table: string; error: string }> = [];
      for (const candidate of candidates) {
        const { error } = await adminClient
          .from(candidate.table)
          .upsert(candidate.payload, { onConflict: 'user_id' });
        if (!error) {
          syncedTables.push(candidate.table);
        } else {
          failedTables.push({ table: candidate.table, error: error.message });
        }
      }

      return json({ ok: syncedTables.length > 0, syncedTables, failedTables });
    }

    const { data: profile, error: profileError } = await adminClient
      .from('seller_profiles')
      .select('approval_status, approval_email_sent_at, official_contact_email, store_name, store_information_final')
      .eq('user_id', user.id)
      .maybeSingle();

    if (profileError) {
      return json({
        status: 'pending',
        message: 'Seller profile found, but approval columns are not configured yet.',
        detail: profileError.message,
      });
    }

    if (!profile) {
      return json({ status: 'pending', message: 'Seller profile not found yet.' });
    }

    const status = String(profile.approval_status ?? 'pending').toLowerCase();
    const hasSentApproval = !!profile.approval_email_sent_at;

    if (status === 'approved' && !hasSentApproval) {
      const to = String(profile.official_contact_email ?? user.email ?? '').trim();
      const storeName = String(profile.store_name ?? profile.store_information_final ?? 'your store').trim();

      if (!to) {
        return json({ status: 'approved', message: 'Approved, but no email recipient found.' });
      }

      const sent = await sendEmail({
        to,
        subject: 'QuickCart Seller Account Approved',
        html: `<p>Great news!</p><p>Your seller account for <strong>${escapeHtml(storeName)}</strong> has been approved.</p><p>You can now fully use seller features in QuickCart.</p><p>- QuickCart Team</p>`,
      });

      if (sent.ok) {
        await adminClient
          .from('seller_profiles')
          .update({ approval_email_sent_at: new Date().toISOString() })
          .eq('user_id', user.id);
      }

      return json({
        status: 'approved',
        message: sent.ok
          ? 'Seller approval status: Approved. Your email notification has been sent.'
          : `Seller approval status: Approved, but email delivery failed. ${sent.error ?? ''}`,
        resendStatus: sent.status,
      });
    }

    if (status === 'approved') {
      return json({
        status: 'approved',
        message: 'Seller approval status: Approved. Email notification was already sent.',
      });
    }

    if (status === 'rejected') {
      return json({
        status: 'rejected',
        message: 'Seller approval status: Rejected. Please contact support for details.',
      });
    }

    return json({
      status: 'pending',
      message: 'Seller approval status: Pending review. You will receive an email once approved.',
    });
  } catch (error) {
    return json({ error: String(error) }, 500);
  }
});

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

async function sendEmail({
  to,
  subject,
  html,
}: {
  to: string;
  subject: string;
  html: string;
}): Promise<{ ok: boolean; status: number; error?: string }> {
  const apiKey = Deno.env.get('RESEND_API_KEY');
  const fromEmail = Deno.env.get('FROM_EMAIL') ?? 'QuickCart <no-reply@example.com>';

  if (!apiKey) {
    return { ok: false, status: 0, error: 'RESEND_API_KEY is missing' };
  }

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: fromEmail,
      to: [to],
      subject,
      html,
    }),
  });

  if (response.ok) {
    return { ok: true, status: response.status };
  }

  const responseText = await response.text();
  return {
    ok: false,
    status: response.status,
    error: responseText,
  };
}

function escapeHtml(input: string): string {
  return input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}
