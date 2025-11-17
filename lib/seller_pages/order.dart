import 'package:flutter/material.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            // Back button
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF1F1F1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              "Orders",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
            ),
            const Spacer(),
            // Open status
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                "Open",
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF0045D8),
              unselectedLabelColor: Colors.black54,
              indicatorColor: const Color(0xFF0045D8),
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              tabs: [
                const Tab(text: "Incoming"),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Preparing"),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          "2",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const Tab(text: "Ready"),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEmptyTab("No Incoming Orders"),
          _buildPreparingTab(),
          _buildEmptyTab("No Ready Orders"),
        ],
      ),
    );
  }

  Widget _buildEmptyTab(String message) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(color: Colors.black54, fontSize: 16),
      ),
    );
  }

  Widget _buildPreparingTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      children: [
        _buildOrderCard(),
        const SizedBox(height: 15),
        _buildOrderCard(),
      ],
    );
  }

  Widget _buildOrderCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left side: order details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  "Pork liempo",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "2Kg for Jim sarmiento",
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  "14 minutes until pick up",
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Right side: ready button
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3FA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: const [
                Icon(Icons.check, color: Color(0xFF0045D8), size: 18),
                SizedBox(width: 5),
                Text(
                  "Ready",
                  style: TextStyle(
                    color: Color(0xFF0045D8),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.black45),
        ],
      ),
    );
  }
}
