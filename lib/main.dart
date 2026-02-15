import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/auth_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ilrjpswhkgoesxmixnne.supabase.co',
    anonKey: 'sb_publishable_s0c8AxKmsyybrkQvgidavA_v7FA_hYO',
  );

  // Initialize AuthManager early
  AuthManager();

  runApp(const FineGlazeApp());
}

class FineGlazeApp extends StatelessWidget {
  const FineGlazeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FineGlaze',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A1A),
          primary: const Color(0xFF1A1A1A),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          iconTheme: IconThemeData(color: Color(0xFF1A1A1A)),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
          ),
          bodyLarge: TextStyle(color: Color(0xFF4A4A4A), fontSize: 16),
          bodyMedium: TextStyle(color: Color(0xFF6A6A6A), fontSize: 14),
        ),
      ),
      home: ListenableBuilder(
        listenable: AuthManager(),
        builder: (context, _) {
          final auth = AuthManager();
          
          if (auth.session == null) {
            return const LoginPage();
          }

          if (auth.isInitializing) {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(height: 16),
                    Text('SYNCHRONIZING SECURE ACCESS', 
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0, color: Colors.grey)),
                  ],
                ),
              ),
            );
          }

          return const DashboardPage();
        },
      ),
    );
  }
}
