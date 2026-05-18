import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Client-side glue around the `paymongo-create-payment` Edge Function and
/// order payment-status polling. Never holds the PayMongo secret key.
class PaymongoService {
  PaymongoService._();
  static final PaymongoService instance = PaymongoService._();

  /// Where PayMongo redirects after a wallet payment.
  /// - Native: sentinel URLs intercepted by the in-app WebView's navigation
  ///   delegate. They never need to be reachable.
  /// - Web: the current app origin with a `?paymongo=` flag, so PayMongo
  ///   sends the user back into the Flutter web app where we can resume.
  static String get successUrl => kIsWeb
      ? '${Uri.base.origin}/?paymongo=success'
      : 'https://quickcart.app/payment/success';

  static String get failedUrl => kIsWeb
      ? '${Uri.base.origin}/?paymongo=failed'
      : 'https://quickcart.app/payment/failed';

  /// On web, the value of `?paymongo=` captured at app startup, awaiting the
  /// first authenticated screen to handle it. Null if not a payment return.
  static String? pendingWebReturn;

  static const _kPendingOrderKey = 'paymongo_pending_order_id';

  /// Web only: stash the order ID before navigating to PayMongo, so we can
  /// resume polling after the user is redirected back.
  Future<void> stashPendingOrder(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingOrderKey, orderId);
  }

  /// Web only: consume the stashed order ID on return from PayMongo.
  Future<String?> takePendingOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kPendingOrderKey);
    if (id != null) await prefs.remove(_kPendingOrderKey);
    return id;
  }

  /// Creates a PayMongo Source for an e-wallet checkout. Returns the
  /// checkout URL to open in a WebView.
  Future<PaymongoCheckout> createWalletCheckout({
    required List<String> orderIds,
    required PaymongoWalletMethod method,
    required int amountCentavos,
    String? email,
    String? name,
  }) async {
    final res = await Supabase.instance.client.functions.invoke(
      'paymongo-create-payment',
      body: {
        'order_ids': orderIds,
        'payment_method': method.apiValue,
        'amount_centavos': amountCentavos,
        if (email != null && email.isNotEmpty) 'email': email,
        if (name != null && name.isNotEmpty) 'name': name,
        'success_url': successUrl,
        'failed_url': failedUrl,
      },
    );

    if (res.status != 200 || res.data == null) {
      final detail = res.data is Map ? (res.data as Map)['error'] : res.data;
      throw PaymongoException(
        'Could not start payment (${res.status}): ${detail ?? 'unknown error'}',
      );
    }
    final data = (res.data as Map).cast<String, dynamic>();
    final sourceId = data['source_id'] as String?;
    final checkoutUrl = data['checkout_url'] as String?;
    if (sourceId == null || checkoutUrl == null) {
      throw const PaymongoException('Malformed checkout response');
    }
    return PaymongoCheckout(
      sourceId: sourceId,
      checkoutUrl: checkoutUrl,
      status: (data['status'] as String?) ?? 'pending',
    );
  }

  /// Reads the payment_status of an order. Used to confirm the webhook
  /// has marked it paid after the WebView closes.
  Future<String?> paymentStatusFor(String orderId) async {
    final row = await Supabase.instance.client
        .from('orders')
        .select('payment_status')
        .eq('id', orderId)
        .maybeSingle();
    return row?['payment_status'] as String?;
  }

  /// Polls the order's payment_status until it's no longer 'pending'
  /// (or the timeout elapses). Returns the final status, or 'pending'
  /// if the timeout was hit.
  Future<String> waitForPaymentResult(
    String orderId, {
    Duration timeout = const Duration(seconds: 30),
    Duration interval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await paymentStatusFor(orderId);
      if (status != null && status != 'pending') return status;
      await Future<void>.delayed(interval);
    }
    return 'pending';
  }
}

enum PaymongoWalletMethod {
  gcash('gcash', 'GCash'),
  maya('maya', 'Maya'),
  grabPay('grab_pay', 'GrabPay');

  const PaymongoWalletMethod(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class PaymongoCheckout {
  const PaymongoCheckout({
    required this.sourceId,
    required this.checkoutUrl,
    required this.status,
  });
  final String sourceId;
  final String checkoutUrl;
  final String status;
}

class PaymongoException implements Exception {
  const PaymongoException(this.message);
  final String message;
  @override
  String toString() => message;
}
