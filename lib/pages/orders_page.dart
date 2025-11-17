import 'package:flutter/material.dart';

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = [
      {"name": "Bananas/Saging", "price": "₱00.00", "id": "#765433", "status": "Pick up"},
      {"name": "Bangus", "price": "₱00.00", "id": "#765433", "status": "Success"},
      {"name": "T-Shirt", "price": "₱00.00", "id": "#765433", "status": "Success"},
      {"name": "Liempo Cut", "price": "₱00.00", "id": "#765433", "status": "Success"},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      "Orders",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),

              const SizedBox(height: 12),

              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListView.separated(
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => Divider(color: Colors.grey[300]),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      bool isPickup = order["status"] == "Pick up";

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          
                          Container(
                            height: 50,
                            width: 50,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.image_outlined, color: Colors.grey),
                          ),

                          const SizedBox(width: 10),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(order["name"]!,
                                    style: const TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w500)),

                                Text(order["price"]!,
                                    style: const TextStyle(
                                        fontSize: 13, color: Colors.black87)),
                                
                                if (!isPickup)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      "11/07/2025",
                                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    ),
                                  )
                              ],
                            ),
                          ),

                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "ID: ${order["id"]}",
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 6),

                              isPickup
                                  ? ElevatedButton(
                                      onPressed: () {},
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1A4DBE),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                      ),
                                      child: const Text("Pick up", style: TextStyle(fontSize: 12)),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEAF1FF),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        "Success",
                                        style: TextStyle(
                                            color: Color(0xFF1A4DBE),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                            ],
                          )
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
