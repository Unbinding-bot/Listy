// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/theme_service.dart'; // Import the new service


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  usePathUrlStrategy();

  await Supabase.initialize(
    url: 'https://qnlpuganyeijxsgravrx.supabase.co',
    anonKey: 'sb_publishable_eCnoDW4i24rSyQj1ztsVbg_D7a59C-V',
  );

  runApp(
    // Wrap the app with the ThemeService
    ChangeNotifierProvider(
      create: (_) => ThemeService(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: themeService.themeColor,
      ),
      // Check if user is already logged in
      home: Supabase.instance.client.auth.currentUser == null
          ? const AuthScreen()
          : const HomeScreen(),
    );
  }
}