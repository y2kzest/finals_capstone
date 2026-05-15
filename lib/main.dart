import 'dart:async';

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

  // Snapshot the URL on web BEFORE Supabase.initialize() — the SDK exchanges
  // the recovery code for a session and then strips the auth params via
  // history.replaceState, so by the time the first frame renders the URL is
  // already clean. Without this snapshot we'd lose the only signal that the
  // user arrived here via a password-reset link.
  bool initialRecoveryLanding = false;
  if (kIsWeb) {
    final uri = Uri.base;
    initialRecoveryLanding =
        uri.queryParameters['type'] == 'recovery' ||
        uri.fragment.contains('type=recovery');
  }

  await Supabase.initialize(url: envUrl, anonKey: envAnon);

  runApp(MyApp(initialRecoveryLanding: initialRecoveryLanding));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.initialRecoveryLanding = false});

  /// True when the app was launched via a Supabase password-recovery URL on
  /// web. We use this to open the "Set new password" dialog on first frame
  /// even if the SDK consumed the URL params before our auth listener was
  /// attached (broadcast streams don't replay past events).
  final bool initialRecoveryLanding;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    // Global password-recovery handler — when the user taps the reset link
    // in their email, route them to LoginPage with the reset dialog opened
    // no matter what page they were last on.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _navKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const LoginPage(startWithResetDialog: true),
          ),
          (_) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickCart',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
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
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _FadeSlidePageTransitionsBuilder(),
            TargetPlatform.iOS: _FadeSlidePageTransitionsBuilder(),
            TargetPlatform.windows: _FadeSlidePageTransitionsBuilder(),
            TargetPlatform.macOS: _FadeSlidePageTransitionsBuilder(),
            TargetPlatform.linux: _FadeSlidePageTransitionsBuilder(),
            TargetPlatform.fuchsia: _FadeSlidePageTransitionsBuilder(),
          },
        ),
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
      home: LoginPage(
        startWithResetDialog: widget.initialRecoveryLanding,
      ),
      routes: {'/home': (context) => const Bahay()},
    );
  }
}

class _FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
