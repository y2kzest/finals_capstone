import 'package:flutter/material.dart';

// You can run this main function for a minimal example

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventory App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const InventoryManagementScreen(),
    );
  }
}

class InventoryManagementScreen extends StatelessWidget {
  const InventoryManagementScreen({super.key});

  // Dummy data for the product list
  final List<Map<String, String>> products = const [
    {'name': 'Pork Liempo', 'stock': '10Kg', 'price': '₱400.00/Kg', 'id': '#765433'},
    {'name': 'Pork Liempo', 'stock': '10Kg', 'price': '₱400.00/Kg', 'id': '#765433'},
    {'name': 'Pork Liempo', 'stock': '10Kg', 'price': '₱400.00/Kg', 'id': '#765433'},
    {'name': 'Pork Liempo', 'stock': '10Kg', 'price': '₱400.00/Kg', 'id': '#765433'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // The image shows the word 'Inventory' above the main container,
        // which isn't a typical AppBar. We'll use a standard Scaffold
        // and put the header content in the body for closer replication.
        backgroundColor: Colors.transparent, // Making AppBar background transparent
        elevation: 0,
        toolbarHeight: 0, // Hiding the actual AppBar space
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[

              // --- Header Section: Inventory Management ---
              Row(
                children: <Widget>[
                  // Back Button (Circle with an arrow)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[200],
                    ),
                    child: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.black87),
                  ),
                  const SizedBox(width: 8),
                  // Title
                  const Text(
                    'Inventory Management',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- Search Bar and Add Product Button ---
              Row(
                children: <Widget>[
                  // Search Bar
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.blue[900], // Dark blue background
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.search, color: Colors.white70),
                          SizedBox(width: 8),
                          // Placeholder text for search
                          Text(
                            'Search Products',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Add Product Button
                  ElevatedButton.icon(
                    onPressed: () {
                      // Handle Add Product tap
                    },
                    icon: const Icon(Icons.add, size: 24),
                    label: const Text('Add product'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white, 
                      backgroundColor: Colors.blue, // Primary blue color
                      minimumSize: const Size(120, 50), // Set button size
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // --- Product List ---
              // ListView to show all the products
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(), // Important for nested ListViews
                itemCount: products.length,
                itemBuilder: (context, index) {
                  return ProductListItem(product: products[index]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Product List Item Widget ---
class ProductListItem extends StatelessWidget {
  final Map<String, String> product;

  const ProductListItem({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15.0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Image Placeholder (The gallery icon)
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade100,
                ),
                child: const Icon(Icons.image_outlined, size: 30, color: Colors.grey),
              ),
              const SizedBox(width: 10),

              // Product Details (Name, Stock, Low Stock tag)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      product['name']!,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Stock : ${product['stock']}',
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    // Low Stock Tag
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue[100], // Light blue background
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Low stock',
                        style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

              // Price, ID, and Edit Icon
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    'ID: ${product['id']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product['price']!,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  // Edit Icon (Pencil)
                  const Icon(Icons.edit, color: Colors.green),
                ],
              ),
            ],
          ),
          // Divider line between items (implied by the original design's spacing and lines)
          Padding(
            padding: const EdgeInsets.only(top: 15.0),
            child: Divider(height: 1, color: Colors.grey.shade200),
          ),
        ],
      ),
    );
  }
}