import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bahay.dart';
import 'pages/login_page.dart';

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
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2A4BA0),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F6FC),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const LoginPage(),
      routes: {'/home': (context) => const Bahay()},
    );
  }
}
