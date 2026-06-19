import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'pages/dashboard_page.dart';
import 'pages/command_page.dart';
import 'pages/devices_page.dart';
import 'pages/admin_page.dart';
import 'pages/loginRegister_page.dart';
import 'pages/home_page.dart';
import 'theme/app_theme.dart';
import 'services/backend_service.dart';
import 'providers/backend_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("FIREBASE INITIALIZED");
  } catch (e) {
    print("FIREBASE ERROR: $e");
  }
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: GrowWiserApp()));
}

class GrowWiserApp extends ConsumerWidget {
  const GrowWiserApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    ref.watch(mqttAutoSubscriptionProvider);
    
    return MaterialApp(
      title: 'Grow Wiser',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      // App always opens on LandingScreen — the slide gesture decides
      // where to go next based on auth state.
      home: const LandingScreen(),
      routes: {
        '/home': (context) => const DashboardPage(),
        '/command': (context) => const CommandPage(),
        '/devices': (context) => const DevicesPage(),
        '/admin': (context) => const AdminPage(),
        '/login': (context) => const AuthPage(),
        '/landing': (context) => const LandingScreen(),
        // NEW: a lightweight router route the slide gesture targets
        '/continue': (context) => const _PostSlideRouter(),
      },
    );
  }
}

// ── POST-SLIDE ROUTER ─────────────────────────────────────────────────────
// Decides where the slide gesture sends the user:
//   - not logged in  → AuthPage (login/register)
//   - logged in, user role  → DashboardPage
//   - logged in, admin role → AdminPage
class _PostSlideRouter extends StatelessWidget {
  const _PostSlideRouter();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: BackendService().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashLoading();
        }

        final user = snapshot.data;

        if (user == null) {
          return const AuthPage();
        }

        return const _RoleRouter();
      },
    );
  }
}

// ── ROLE ROUTER ───────────────────────────────────────────────────────────
class _RoleRouter extends StatefulWidget {
  const _RoleRouter();

  @override
  State<_RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<_RoleRouter> {
  bool _loading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    final admin = await BackendService().isAdmin();
    if (mounted) {
      setState(() {
        _isAdmin = admin;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _SplashLoading();
    return _isAdmin ? const AdminPage() : const DashboardPage();
  }
}

// ── SPLASH LOADING ────────────────────────────────────────────────────────
class _SplashLoading extends StatefulWidget {
  const _SplashLoading();

  @override
  State<_SplashLoading> createState() => _SplashLoadingState();
}

class _SplashLoadingState extends State<_SplashLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/logo_yellowfont.png',
                  width: 180,
                ),
                const SizedBox(height: 32),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Color(0xFFE4F27A),
                    strokeWidth: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}