import 'package:flutter/material.dart';

// You can run this main function for a minimal example
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Analytics Report',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AnalyticsReportScreen(),
    );
  }
}

class AnalyticsReportScreen extends StatefulWidget {
  const AnalyticsReportScreen({super.key});

  @override
  State<AnalyticsReportScreen> createState() => _AnalyticsReportScreenState();
}

class _AnalyticsReportScreenState extends State<AnalyticsReportScreen> {
  // State variables for the Timeframe selector
  String selectedTimeframe = 'All-time'; // Display text for the main selector
  bool isTimeframeMenuOpen = false;
  String selectedQuickPeriod = 'This Month'; // Highlighted item in the dropdown

  final List<String> quickPeriods = ['Last 7 Days', 'This Month', 'This Year', 'Custom'];
  
  // Dummy data for the table
  final List<Map<String, String>> productSales = const [
    {'Product': 'Tilapia', 'Sold': '45Kg', 'Revenue': '₱8,100', 'StockLeft': '26Kg'},
    {'Product': 'Pork Belly', 'Sold': '32Kg', 'Revenue': '₱7,800', 'StockLeft': '21Kg'},
    {'Product': 'Beef', 'Sold': '15Kg', 'Revenue': '₱4,212', 'StockLeft': '13Kg'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(
        children: [
          // --- Main Content (Scrollable) ---
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Header (with Padding to account for Status Bar)
                Padding(
                  padding: const EdgeInsets.only(top: 30, bottom: 20),
                  child: Row(
                    children: [
                      // Back Button
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[200],
                        ),
                        child: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.black87),
                      ),
                      const SizedBox(width: 10),
                      // Title
                      const Text(
                        'Analytics Report',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),

                // --- Timeframe Selector ---
                GestureDetector(
                  onTap: () {
                    setState(() {
                      isTimeframeMenuOpen = !isTimeframeMenuOpen;
                    });
                  },
                  child: Row(
                    children: [
                      const Text(
                        'Timeframe:',
                        style: TextStyle(fontSize: 16, color: Colors.black),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        selectedTimeframe,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Icon(
                        isTimeframeMenuOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // --- Metric Cards ---
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(), // To allow main scroll view to handle scrolling
                  crossAxisSpacing: 15,
                  mainAxisSpacing: 15,
                  childAspectRatio: 1.2, // Adjust aspect ratio for card size
                  children: const <Widget>[
                    MetricCard(title: 'Top Sales', value: '₱00.00'),
                    MetricCard(title: 'Total Orders', value: '000'),
                    MetricCard(title: 'Average Order', value: '000'),
                    MetricCard(title: 'Top Selling', value: 'Pork'),
                  ],
                ),
                const SizedBox(height: 30),

                // --- Product Sales Table Header ---
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Manually space the headers to match the image layout
                      SizedBox(width: 80, child: Text('Product', style: TextStyle(color: Colors.grey))),
                      SizedBox(width: 60, child: Text('Sold', style: TextStyle(color: Colors.grey))),
                      SizedBox(width: 80, child: Text('Revenue', style: TextStyle(color: Colors.grey))),
                      Text('Stock Left', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.grey),
                const SizedBox(height: 10),

                // --- Product Sales List ---
                ...productSales.map((sale) => ProductSaleRow(sale: sale)).toList(),

                const SizedBox(height: 50),
              ],
            ),
          ),
          
          // --- Timeframe Menu Overlay (Conditional) ---
          if (isTimeframeMenuOpen)
            Positioned(
              top: 170, // Adjust this value to position the dropdown below the Timeframe label
              left: 20,
              child: TimeframeMenu(
                quickPeriods: quickPeriods,
                selectedPeriod: selectedQuickPeriod,
                onSelect: (period) {
                  setState(() {
                    selectedQuickPeriod = period;
                    selectedTimeframe = period; // Update main display text
                    isTimeframeMenuOpen = false;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }
}

// --- Metric Card Widget ---
class MetricCard extends StatelessWidget {
  final String title;
  final String value;

  const MetricCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Product Sale Row Widget (Custom Table) ---
class ProductSaleRow extends StatelessWidget {
  final Map<String, String> sale;

  const ProductSaleRow({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          SizedBox(width: 80, child: Text(sale['Product']!, style: const TextStyle(fontWeight: FontWeight.w600))),
          SizedBox(width: 60, child: Text(sale['Sold']!)),
          SizedBox(width: 80, child: Text(sale['Revenue']!)),
          Text(sale['StockLeft']!),
        ],
      ),
    );
  }
}

// --- Timeframe Selection Menu Overlay Widget ---
class TimeframeMenu extends StatelessWidget {
  final List<String> quickPeriods;
  final String selectedPeriod;
  final Function(String) onSelect;

  const TimeframeMenu({
    super.key,
    required this.quickPeriods,
    required this.selectedPeriod,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 5,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 150, // Fixed width based on image size
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 10, 10, 5),
              child: Text(
                'Timeframe: This Month', // Based on the visual in the overlay
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
              ),
            ),
            const Divider(height: 1),
            ...quickPeriods.map((period) {
              final isSelected = period == selectedPeriod;
              return GestureDetector(
                onTap: () => onSelect(period),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  color: isSelected ? Colors.blue[50] : Colors.white,
                  child: Text(
                    period,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.blue[800] : Colors.black,
                    ),
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}