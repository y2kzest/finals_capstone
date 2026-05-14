import 'package:flutter/material.dart';

import '../services/paymongo_service.dart';

/// Returned by [PaymentMethodPage] via `Navigator.pop`.
class PaymentMethodChoice {
  const PaymentMethodChoice.cod() : wallet = null;
  const PaymentMethodChoice.wallet(this.wallet);

  /// Null when the buyer chose cash-on-delivery / pickup payment.
  final PaymongoWalletMethod? wallet;

  bool get isOnline => wallet != null;
}

/// Lets the buyer pick how they want to pay. Returns a [PaymentMethodChoice]
/// (or null if the buyer backs out).
class PaymentMethodPage extends StatelessWidget {
  const PaymentMethodPage({
    super.key,
    required this.totalAmount,
    this.itemCount = 1,
    this.shopCount = 1,
  });

  final double totalAmount;
  final int itemCount;
  final int shopCount;

  static const Color _kPrimary = Color(0xFF2A4BA0);
  static const Color _kPrimaryDark = Color(0xFF153075);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kPrimaryDark,
        elevation: 0.5,
        title: const Text(
          'Payment method',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _summaryCard(),
            const SizedBox(height: 20),
            const _SectionLabel('Pay online'),
            const SizedBox(height: 8),
            _walletTile(
              context,
              method: PaymongoWalletMethod.gcash,
              icon: Icons.account_balance_wallet_rounded,
              accent: const Color(0xFF1F73E0),
              subtitle: 'Pay via your GCash app',
            ),
            const SizedBox(height: 10),
            _walletTile(
              context,
              method: PaymongoWalletMethod.maya,
              icon: Icons.payments_rounded,
              accent: const Color(0xFF00A85A),
              subtitle: 'Pay via your Maya account',
            ),
            const SizedBox(height: 24),
            const _SectionLabel('Pay later'),
            const SizedBox(height: 8),
            _codTile(context),
            const SizedBox(height: 20),
            _securityNote(),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kPrimary, _kPrimaryDark],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33153075),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$itemCount item${itemCount == 1 ? '' : 's'} · '
                  '$shopCount shop${shopCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Total to pay',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '₱${totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.shopping_bag_rounded,
            color: Colors.white,
            size: 40,
          ),
        ],
      ),
    );
  }

  Widget _walletTile(
    BuildContext context, {
    required PaymongoWalletMethod method,
    required IconData icon,
    required Color accent,
    required String subtitle,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context)
            .pop(PaymentMethodChoice.wallet(method)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: _kPrimaryDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codTile(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).pop(const PaymentMethodChoice.cod()),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.local_atm_rounded,
                  color: Color(0xFFD97706),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cash on pickup / delivery',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: _kPrimaryDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Pay the seller when your order arrives',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _securityNote() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.lock_rounded,
          color: Color(0xFF6B7280),
          size: 14,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Online payments are processed securely by PayMongo. '
            'QuickCart never sees your wallet credentials.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }
}
