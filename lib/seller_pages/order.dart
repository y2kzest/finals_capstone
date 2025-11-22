import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final supabase = Supabase.instance.client;

  RealtimeChannel? orderChannel; // <-- FIX: store the channel object

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // FIXED REALTIME SUBSCRIPTION
    orderChannel = supabase
        .channel('orders-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            setState(() {}); // auto refresh page when new order arrives
          },
        )
        .subscribe();
  }

  // -------------------------
  // FETCH ORDERS
  // -------------------------

  Future<List<dynamic>> fetchIncomingOrders() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final response = await supabase
        .from('orders')
        .select()
        .order('created_at', ascending: false);

    return response;
  }

  Future<List<dynamic>> fetchPreparingOrders() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    return await supabase
        .from('orders')
        .select()
        .order('created_at', ascending: false);
  }

  Future<List<dynamic>> fetchReadyOrders() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    return await supabase
        .from('orders')
        .select()
        .order('created_at', ascending: false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (orderChannel != null) {
      supabase.removeChannel(orderChannel!); // <-- FIXED
    }
    super.dispose();
  }

  // -------------------------
  // UI
  // -------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text("Orders"),
        backgroundColor: Colors.white,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          buildOrdersTab(fetchIncomingOrders, "No Incoming Orders"),
          buildOrdersTab(fetchPreparingOrders, "No Preparing Orders"),
          buildOrdersTab(fetchReadyOrders, "No Ready Orders"),
        ],
      ),
      bottomNavigationBar: TabBar(
        controller: _tabController,
        labelColor: Colors.blue,
        unselectedLabelColor: Colors.grey,
        tabs: const [
          Tab(text: "Incoming"),
          Tab(text: "Preparing"),
          Tab(text: "Ready"),
        ],
      ),
    );
  }

  Widget buildOrdersTab(Future<List<dynamic>> Function() query, String emptyMsg) {
    return FutureBuilder(
      future: query(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final orders = snapshot.data ?? [];

        if (orders.isEmpty) {
          return _buildEmptyTab(emptyMsg);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: orders.length,
          itemBuilder: (context, i) {
            final o = orders[i];

            return Container(
              margin: const EdgeInsets.only(bottom: 15),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o['product_name'],
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        Text("Qty: ${o['qty']}"),
                        Text("₱${o['price']}"),
                        Text(
                          o['created_at'],
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
}
