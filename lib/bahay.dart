import 'package:caps_finals/profile.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pages/home_page.dart';
import 'pages/category_page.dart';
// 👈 NEW: Import the Profile Page
import 'profile.dart'; 


void main() {
  runApp(const Bahay());
}

class Bahay extends StatelessWidget {
  const Bahay({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shop UI',
      theme: ThemeData(
        textTheme: GoogleFonts.poppinsTextTheme(),
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  // All pages are now included in the list to match the 4 BottomNavigationBarItems
  final List<Widget> _pages = const [
    HomePage(),                       // Index 0: Home
    CategoryPage(),                   // Index 1: Categories
    Center(child: Text('Favourite Page Placeholder')), // Index 2: Favourite
    Profile(),                    // 👈 Index 3: Profile Page
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.amber[800],
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Categories'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite_border_rounded), label: 'Favourite'),
          // Using a more suitable profile icon here
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}