import 'package:flutter/material.dart';

class BusinessProfileScreen extends StatelessWidget {
  const BusinessProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back icon
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              ),

              const SizedBox(height: 8),

              // Title
              const Text(
                "Business Profile",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Complete the store and business information that will be registered",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),

              const SizedBox(height: 24),

              // Section header
              const Text(
                "General information",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 10),

              // Store name input
              _buildTextField(label: "Store Name *"),

              const SizedBox(height: 20),

              // Dropdowns
              _buildDropdown(label: "Services *", hint: "Select Service"),
              const SizedBox(height: 20),
              _buildDropdown(label: "Stall *", hint: "Select Stall"),
              const SizedBox(height: 20),
              _buildDropdown(label: "Select Business size *", hint: "Select Size"),

              const SizedBox(height: 30),

              // Store address section
              const Text(
                "Store Address",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              _buildDropdown(label: "Address *", hint: "Select Address"),

              const SizedBox(height: 40),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D4BF0), // Blue button
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  onPressed: () {},
                  child: const Text(
                    "Save",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Custom text field
  Widget _buildTextField({required String label}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        TextFormField(
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blue),
            ),
          ),
        ),
      ],
    );
  }

  // Custom dropdown
  Widget _buildDropdown({required String label, required String hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blue),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          hint: Text(hint, style: const TextStyle(color: Colors.black54)),
          items: const [
            DropdownMenuItem(value: "Option 1", child: Text("Option 1")),
            DropdownMenuItem(value: "Option 2", child: Text("Option 2")),
          ],
          onChanged: (value) {},
        ),
      ],
    );
  }
}
