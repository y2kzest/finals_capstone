// activate.dart

import 'package:flutter/material.dart';
// IMPORTANT: Add these imports for navigation
import 'package:caps_finals/main.dart';
import 'seller_signin.dart';

// Define the primary color constant
const Color kPrimaryColor = Color(0xFF283A97);

void main() {
  runApp(const Activate());
}

class Activate extends StatelessWidget {
  const Activate({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Activate Quickcart',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black),
        ),
      ),
      home: const ActivateQuickcartScreen(),
    );
  }
}

// --- Placeholder for main.dart (Sign In) ---
// DELETE THIS SECTION if main.dart is already a separate file!
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Main / Sign In Screen')),
      body: const Center(child: Text('Navigated to Main Screen.')),
    );
  }
}
// ----------------------------------------------

// --- Placeholder for fill_business_info.dart ---
// DELETE THIS SECTION if fill_business_info.dart is already a separate file!
class FillBusinessInfoScreen extends StatelessWidget {
  const FillBusinessInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fill Business Info')),
      body: const Center(
        child: Text('Navigated to Fill Business Info Screen.'),
      ),
    );
  }
}
// ----------------------------------------------

class ActivateQuickcartScreen extends StatelessWidget {
  const ActivateQuickcartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Text(
          'Activate Quickcart',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: kPrimaryColor.withValues(alpha: 0.06),
                border: Border.all(
                  color: kPrimaryColor.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/img/logo.png',
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Start selling with Quickcart Merchant',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: kPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Grow your business and handle orders faster with a streamlined seller setup.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Merchant features',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildFeatureItem('Accept Quickcart orders automatically'),
                  _buildFeatureItem('Change menu and price anytime you want'),
                  _buildFeatureItem(
                    'Track payouts and earnings with confidence',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'How to activate',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildStepItem(
                    context,
                    stepNumber: 1,
                    title: 'Fill in the form and submit',
                    subtitle:
                        'Submit business details, ID card, legal documents, and product photos.',
                    isFirst: true,
                  ),
                  _buildStepItem(
                    context,
                    stepNumber: 2,
                    title: 'Wait for approval',
                    subtitle:
                        'Our team reviews your submission and verifies your business profile.',
                  ),
                  _buildStepItem(
                    context,
                    stepNumber: 3,
                    title: 'Activate your store',
                    subtitle:
                        'Switch your store status from "Paused" to "Open" and start receiving orders.',
                    isLast: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Activation Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                // NAVIGATE: Activate button directs to fill_business_info.dart
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SellerSignInPage(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Activate',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Sign In Link
            Center(
              child: GestureDetector(
                // NAVIGATE: Back to Sign In directs to main.dart
                onTap: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                },
                child: Text.rich(
                  TextSpan(
                    text: 'Already have an account? ',
                    style: const TextStyle(color: Colors.black54),
                    children: <TextSpan>[
                      TextSpan(
                        text: 'Back to Sign In',
                        style: TextStyle(
                          color: kPrimaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods remain the same, ensuring they use kPrimaryColor
  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.check_circle, color: kPrimaryColor, size: 24),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildStepItem(
    BuildContext context, {
    required int stepNumber,
    required String title,
    required String subtitle,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kPrimaryColor.withValues(alpha: 0.12),
                  border: Border.all(color: kPrimaryColor, width: 1.4),
                ),
                child: Text(
                  '$stepNumber',
                  style: const TextStyle(
                    color: kPrimaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 74,
                  color: kPrimaryColor.withValues(alpha: 0.22),
                ),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
