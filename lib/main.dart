import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bahay.dart';
import 'pages/login_page.dart';
import 'utils/marketplace_ui.dart';

const String kSupabaseUrl = 'https://mnnnmdlvjvwyxhadeinc.supabase.co';
const String kSupabaseAnonKey =
  'sb_publishable_VsO4euO_9SsyIrLFy-bFmg_T8q331ll';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String envUrl = kSupabaseUrl;
  String envAnon = kSupabaseAnonKey;

  if (!kIsWeb) {
    try {
      await dotenv.load(fileName: '.env');
      envUrl = dotenv.env['SUPABASE_URL'] ?? kSupabaseUrl;
      envAnon = dotenv.env['SUPABASE_ANON_KEY'] ?? kSupabaseAnonKey;
    } catch (_) {
      // Fall back to hardcoded constants if .env is missing
    }
  }

  await Supabase.initialize(url: envUrl, anonKey: envAnon);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickCart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: MarketplaceUi.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: MarketplaceUi.primary,
          secondary: MarketplaceUi.accent,
          surface: Colors.white,
        ),
        textTheme: MarketplaceUi.textTheme(
          ThemeData(brightness: Brightness.light).textTheme,
        ),
        scaffoldBackgroundColor: MarketplaceUi.surface,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: MarketplaceUi.textStrong,
          surfaceTintColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          hintStyle: const TextStyle(color: MarketplaceUi.textSubtle),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: MarketplaceUi.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: MarketplaceUi.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: MarketplaceUi.primary,
              width: 1.4,
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: MarketplaceUi.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: MarketplaceUi.primary,
            side: const BorderSide(color: MarketplaceUi.line),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          selectedColor: MarketplaceUi.primary.withValues(alpha: 0.12),
          side: const BorderSide(color: MarketplaceUi.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          labelStyle: const TextStyle(
            color: MarketplaceUi.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: MarketplaceUi.textStrong,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const LoginPage(),
      routes: {'/home': (context) => const Bahay()},
    );
  }
}
