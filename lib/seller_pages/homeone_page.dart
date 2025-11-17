import 'package:flutter/material.dart';
import 'fill_business_info.dart'; // Make sure this file exists
import 'dashboard_screen.dart'; // 👈 Import your Shop Dashboard file

class HomeOnePage  extends StatelessWidget {
  const HomeOnePage ({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          "Activate Quickcart",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),

            // Placeholder image
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.image_outlined,
                size: 60,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              "Grow your business and boost your sales by using QuickCart features:",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // White card: How to activate
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "How to activate",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 20),
                  StepItem(
                    title: "Fill in the form and submit",
                    subtitle:
                        "You will submit all business details, ID Card, legal documents, menu and food photo",
                  ),
                  SizedBox(height: 20),
                  StepItem(
                    title: "Wait for approval",
                    subtitle:
                        "Automatic bank transfer of earnings from GrabPay every day",
                  ),
                  SizedBox(height: 20),
                  StepItem(
                    title: "Activate your store",
                    subtitle:
                        "On the Orders page, toggle the status from “Paused” to “Open” to begin receiving orders.",
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // ✅ Activate button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
onPressed: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => FillBusinessInfoPage(), // ❌ removed const
    ),
  );
},

                child: const Text(
                  "Activate",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 15),

            // 📞 Dashboard Support button → redirects to Shop Dashboard
            SizedBox(
              width: double.infinity,
              height: 50,
              child: TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ShopDashboardScreen(),
                    ),
                  );
                },
                child: const Text(
                  "Dashboard",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF007AFF),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class StepItem extends StatelessWidget {
  final String title;
  final String subtitle;
  const StepItem({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.radio_button_checked, color: Colors.grey, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
