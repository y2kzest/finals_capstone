import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/paymongo_service.dart';

/// Hosts the PayMongo checkout URL. On mobile/macOS uses an in-app WebView;
/// on Windows/Linux opens the system browser and polls for confirmation.
class PaymongoWebViewPage extends StatefulWidget {
  const PaymongoWebViewPage({
    super.key,
    required this.checkoutUrl,
    required this.methodLabel,
    this.pollOrderId,
  });

  final String checkoutUrl;
  final String methodLabel;

  /// Order ID used for payment polling on desktop (where WebView isn't available).
  final String? pollOrderId;

  @override
  State<PaymongoWebViewPage> createState() => _PaymongoWebViewPageState();
}

enum PaymongoWebResult { success, failed, cancelled }

// Platforms where webview_flutter has a registered implementation.
bool get _supportsWebView =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

class _PaymongoWebViewPageState extends State<PaymongoWebViewPage> {
  // --- WebView state ---
  WebViewController? _controller;
  bool _loading = true;
  bool _resolved = false;

  // --- Desktop polling state ---
  bool _polling = false;
  String? _pollError;

  @override
  void initState() {
    super.initState();
    if (_supportsWebView) {
      _initWebView();
    } else {
      _openBrowser();
    }
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (req) {
            if (_resolved) return NavigationDecision.prevent;
            if (req.url.startsWith(PaymongoService.successUrl)) {
              _resolved = true;
              Navigator.of(context).pop(PaymongoWebResult.success);
              return NavigationDecision.prevent;
            }
            if (req.url.startsWith(PaymongoService.failedUrl)) {
              _resolved = true;
              Navigator.of(context).pop(PaymongoWebResult.failed);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  Future<void> _openBrowser() async {
    final uri = Uri.parse(widget.checkoutUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _checkPaymentStatus() async {
    final orderId = widget.pollOrderId;
    if (orderId == null) {
      // No order ID — just return success and let the caller's own polling decide.
      Navigator.of(context).pop(PaymongoWebResult.success);
      return;
    }
    setState(() {
      _polling = true;
      _pollError = null;
    });
    try {
      final status = await PaymongoService.instance.waitForPaymentResult(
        orderId,
        timeout: const Duration(seconds: 20),
        interval: const Duration(seconds: 2),
      );
      if (!mounted) return;
      if (status == 'paid') {
        Navigator.of(context).pop(PaymongoWebResult.success);
      } else if (status == 'failed') {
        Navigator.of(context).pop(PaymongoWebResult.failed);
      } else {
        // Still pending after timeout — return success and let cart_page poll further.
        Navigator.of(context).pop(PaymongoWebResult.success);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _polling = false;
        _pollError = 'Could not verify payment. Try again.';
      });
    }
  }

  Future<bool> _confirmCancel() async {
    final out = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel payment?'),
        content: Text(
          'Your ${widget.methodLabel} payment is still in progress. '
          'Are you sure you want to cancel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep paying'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel payment'),
          ),
        ],
      ),
    );
    return out ?? false;
  }

  // ── Desktop UI ────────────────────────────────────────────────────────────

  Widget _buildDesktopBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.open_in_browser_rounded,
              size: 64,
              color: Color(0xFF2A4BA0),
            ),
            const SizedBox(height: 20),
            Text(
              'Complete your ${widget.methodLabel} payment',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF153075),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your browser has opened the payment page.\n'
              'Once you\'ve finished paying, tap the button below.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.5),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _openBrowser,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Re-open payment page'),
            ),
            const SizedBox(height: 28),
            if (_pollError != null) ...[
              Text(
                _pollError!,
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _polling ? null : _checkPaymentStatus,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2A4BA0),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _polling
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "I've completed payment",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── WebView UI ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_supportsWebView) {
      return Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF153075),
          elevation: 0.5,
          title: Text(
            'Pay with ${widget.methodLabel}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              final ok = await _confirmCancel();
              if (ok && context.mounted) {
                Navigator.of(context).pop(PaymongoWebResult.cancelled);
              }
            },
          ),
        ),
        body: _buildDesktopBody(),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _resolved) return;
        final ok = await _confirmCancel();
        if (ok && context.mounted) {
          Navigator.of(context).pop(PaymongoWebResult.cancelled);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF153075),
          elevation: 0.5,
          title: Text(
            'Pay with ${widget.methodLabel}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              if (_resolved) {
                Navigator.of(context).pop();
                return;
              }
              final ok = await _confirmCancel();
              if (ok && context.mounted) {
                Navigator.of(context).pop(PaymongoWebResult.cancelled);
              }
            },
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller!),
            if (_loading)
              const LinearProgressIndicator(
                minHeight: 2.5,
                color: Color(0xFF1A73E8),
                backgroundColor: Color(0xFFE5E7EB),
              ),
          ],
        ),
      ),
    );
  }
}
