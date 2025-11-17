import 'package:flutter/material.dart';
import 'categorylist.dart';

class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  String? selectedCategory; // null = show grid; not null = show CategoryList

  @override
  Widget build(BuildContext context) {
    // When user selects a category
    if (selectedCategory != null) {
      return CategoryListPage(
        category: selectedCategory!,
        onBack: () => setState(() => selectedCategory = null),
      );
    }

    // Default category grid
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A4DBE),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Hey, *****",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    "Shop",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    "By Category",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Category Grid with IMAGES
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                CategoryCard(
                  title: "Fishes",
                  imagePath: "assets/img/categories/fishesh.jpg",
                  onTap: () => setState(() => selectedCategory = "Fishes"),
                ),
                CategoryCard(
                  title: "Meats",
                  imagePath: "assets/img/categories/meats.jpg",
                  onTap: () => setState(() => selectedCategory = "Meats"),
                ),
                CategoryCard(
                  title: "Vegetables",
                  imagePath: "assets/img/categories/vege.jpg",
                  onTap: () => setState(() => selectedCategory = "Vegetables"),
                ),
                CategoryCard(
                  title: "Fruits",
                  imagePath: "assets/img/categories/fruits.jpg",
                  onTap: () => setState(() => selectedCategory = "Fruits"),
                ),
                CategoryCard(
                  title: "Services",
                  imagePath: "assets/img/categories/services.jpg",
                  onTap: () => setState(() => selectedCategory = "Services"),
                ),
                CategoryCard(
                  title: "Snacks",
                  imagePath: "assets/img/categories/snacks.png",
                  onTap: () => setState(() => selectedCategory = "Snacks"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryCard extends StatelessWidget {
  final String title;
  final String imagePath;
  final VoidCallback? onTap;

  const CategoryCard({
    super.key,
    required this.title,
    required this.imagePath,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Category Image
            Container(
              height: 70,
              width: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                ),
              ),
            ),

            const SizedBox(height: 10),

            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),

            const Text(
              "Detail",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
