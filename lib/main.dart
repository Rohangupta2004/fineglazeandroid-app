import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ilrjpswhkgoesxmixnne.supabase.co',
    anonKey: 'sb_publishable_s0c8AxKmsyybrkQvgidavA_v7FA_hYO',
  );

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A1A),
          primary: const Color(0xFF1A1A1A),
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      // Check if user is already logged in
      home: Supabase.instance.client.auth.currentSession != null
          ? const DashboardPage()
          : const LoginPage(),
    );
  }
}
