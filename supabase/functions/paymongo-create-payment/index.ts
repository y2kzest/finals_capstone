// PayMongo: create a Source (GCash / Maya / GrabPay) for an authenticated
// buyer's order(s). Returns the checkout_url that the Flutter app opens
// in a WebView. Secret key never leaves this function.
//
// POST body:
//   {
//     order_ids: string[],
//     payment_method: 'gcash' | 'maya' | 'grab_pay',
//     amount_centavos: number,   // sum of order totals, sanity-checked server-side
//     email?: string,
//     name?: string,
//     success_url: string,
//     failed_url: string
//   }
//
// Response:
//   { source_id, checkout_url, status }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const PAYMONGO_BASE = 'https://api.paymongo.com/v1';
const ALLOWED_METHODS = ['gcash', 'paymaya', 'grab_pay'] as const;
type WalletMethod = (typeof ALLOWED_METHODS)[number];

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);

  const PAYMONGO_SK = Deno.env.get('PAYMONGO_SECRET_KEY');
  const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
  const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!PAYMONGO_SK || !SUPABASE_URL || !SERVICE_KEY) {
    return json({ error: 'server not configured' }, 500);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: 'invalid JSON body' }, 400);
  }

  const orderIds = payload.order_ids;
  const method = String(payload.payment_method ?? '') as WalletMethod;
  const amountCentavos = Number(payload.amount_centavos ?? 0);
  const email = typeof payload.email === 'string' ? payload.email : '';
  const name =
    typeof payload.name === 'string' && payload.name.trim()
      ? payload.name.trim()
      : 'Customer';
  const successUrl =
    typeof payload.success_url === 'string' ? payload.success_url : '';
  const failedUrl =
    typeof payload.failed_url === 'string' ? payload.failed_url : '';

  if (!Array.isArray(orderIds) || orderIds.length === 0) {
    return json({ error: 'order_ids required' }, 400);
  }
  if (!ALLOWED_METHODS.includes(method)) {
    return json({ error: `unsupported payment_method: ${method}` }, 400);
  }
  // PayMongo minimum is 100 centavos (PHP 1.00)
  if (!Number.isFinite(amountCentavos) || amountCentavos < 100) {
    return json({ error: 'amount_centavos must be a number >= 100' }, 400);
  }
  if (!successUrl || !failedUrl) {
    return json({ error: 'success_url and failed_url required' }, 400);
  }

  // Authenticate the calling buyer
  const authHeader = req.headers.get('Authorization') ?? '';
  const accessToken = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!accessToken) return json({ error: 'unauthorized' }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false },
  });

  const { data: userInfo, error: userErr } = await admin.auth.getUser(
    accessToken,
  );
  if (userErr || !userInfo?.user) {
    return json({ error: 'unauthorized' }, 401);
  }
  const userId = userInfo.user.id;

  // Verify orders belong to this user, are not already paid, and amount matches
  const { data: orders, error: ordErr } = await admin
    .from('orders')
    .select('id, buyer_id, total_amount, payment_status')
    .in('id', orderIds);

  if (ordErr) return json({ error: ordErr.message }, 500);
  if (!orders || orders.length !== orderIds.length) {
    return json({ error: 'one or more orders not found' }, 404);
  }
  const mismatch = orders.find((o) => o.buyer_id !== userId);
  if (mismatch) return json({ error: 'forbidden' }, 403);
  const alreadyPaid = orders.find((o) => o.payment_status === 'paid');
  if (alreadyPaid) return json({ error: 'one or more orders already paid' }, 400);

  const expectedCentavos = Math.round(
    orders.reduce((sum, o) => sum + Number(o.total_amount ?? 0), 0) * 100,
  );
  if (Math.abs(expectedCentavos - amountCentavos) > 1) {
    return json(
      {
        error: 'amount mismatch — refusing to create payment',
        expected_centavos: expectedCentavos,
        got_centavos: amountCentavos,
      },
      400,
    );
  }

  // Create a PayMongo Source
  let sourceRes: Response;
  try {
    sourceRes = await fetch(`${PAYMONGO_BASE}/sources`, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${btoa(`${PAYMONGO_SK}:`)}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        data: {
          attributes: {
            amount: amountCentavos,
            currency: 'PHP',
            type: method,
            redirect: { success: successUrl, failed: failedUrl },
            billing: {
              name,
              ...(email ? { email } : {}),
            },
          },
        },
      }),
    });
  } catch (e) {
    return json({ error: `paymongo network error: ${e}` }, 502);
  }

  const sourceBody = await sourceRes.text();
  if (!sourceRes.ok) {
    return json(
      { error: 'paymongo source creation failed', detail: sourceBody },
      502,
    );
  }

  let sourceJson: any;
  try {
    sourceJson = JSON.parse(sourceBody);
  } catch {
    return json({ error: 'paymongo returned non-JSON', body: sourceBody }, 502);
  }

  const sourceId = sourceJson?.data?.id as string | undefined;
  const checkoutUrl = sourceJson?.data?.attributes?.redirect?.checkout_url as
    | string
    | undefined;
  const sourceStatus = sourceJson?.data?.attributes?.status as
    | string
    | undefined;

  if (!sourceId || !checkoutUrl) {
    return json(
      { error: 'paymongo response missing id/checkout_url', body: sourceJson },
      502,
    );
  }

  // Tag all orders in this group with the source so the webhook can find them
  const { error: updErr } = await admin
    .from('orders')
    .update({
      payment_method: method,
      payment_status: 'pending',
      paymongo_source_id: sourceId,
      paymongo_checkout_url: checkoutUrl,
    })
    .in('id', orderIds);

  if (updErr) {
    return json(
      { error: `db update failed: ${updErr.message}`, source_id: sourceId },
      500,
    );
  }

  return json({
    source_id: sourceId,
    checkout_url: checkoutUrl,
    status: sourceStatus ?? 'pending',
  });
});
