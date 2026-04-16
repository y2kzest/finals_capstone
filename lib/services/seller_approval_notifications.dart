import 'package:supabase_flutter/supabase_flutter.dart';

class SellerApprovalNotifications {
  SellerApprovalNotifications({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const List<String> _functionNames = [
    'send-email',
    'seller-approval-notifications',
  ];

  Future<dynamic> _invokeWithFallback(Map<String, dynamic> body) async {
    Object? lastError;

    for (final functionName in _functionNames) {
      try {
        return await _client.functions.invoke(functionName, body: body);
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(
      'Unable to call any email function endpoint. Last error: $lastError',
    );
  }

  Future<Map<String, dynamic>> sendSubmissionReceivedEmail({
    required String email,
    required String storeName,
  }) async {
    final response = await _invokeWithFallback({
      'action': 'submission_received',
      'email': email,
      'storeName': storeName,
    });

    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }

    return const {
      'ok': false,
      'status': 'pending',
      'message': 'No response body from email function',
    };
  }

  Future<Map<String, dynamic>?> checkApprovalAndNotify() async {
    final response = await _invokeWithFallback({
      'action': 'check_and_notify_approval',
    });

    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> listPendingSellers() async {
    final response = await _invokeWithFallback({
      'action': 'list_pending_sellers',
    });

    final data = response.data;
    if (data is Map<String, dynamic> && data['items'] is List) {
      return (data['items'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return const [];
  }

  Future<void> approveSeller({required String sellerUserId}) async {
    await _invokeWithFallback({
      'action': 'approve_seller',
      'sellerUserId': sellerUserId,
    });
  }

  Future<Map<String, dynamic>> syncExternalAdmin({
    required String userId,
    required String storeName,
    required String stallNo,
    required String businessType,
    required String contactEmail,
  }) async {
    final response = await _invokeWithFallback({
      'action': 'sync_external_admin',
      'userId': userId,
      'storeName': storeName,
      'stallNo': stallNo,
      'businessType': businessType,
      'contactEmail': contactEmail,
    });

    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }

    return const {
      'ok': false,
      'syncedTables': <String>[],
      'failedTables': <Map<String, String>>[],
    };
  }

  Future<Map<String, dynamic>> registerSellerCandidate({
    required String email,
    String? password,
    String? userId,
  }) async {
    final body = <String, dynamic>{
      'action': 'register_seller_candidate',
      'email': email,
    };
    if (password != null && password.isNotEmpty) {
      body['password'] = password;
    }
    if (userId != null && userId.isNotEmpty) {
      body['userId'] = userId;
    }

    final response = await _invokeWithFallback(body);

    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }

    return const {
      'ok': false,
      'message': 'No response body from register_seller_candidate',
    };
  }
}
