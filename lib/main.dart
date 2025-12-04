// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/theme_service.dart'; // Import the new service
//

ThemeData createDarkTheme(Color primaryColor) {
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: primaryColor,
      // You can derive secondary/accent colors here, or use constants
      secondary: primaryColor.withOpacity(0.7),
      background: const Color(0xFF121212),
      surface: const Color(0xFF1E1E1E),
    ),
    useMaterial3: true,
  );
}

ThemeData createLightTheme(Color primaryColor) {
  return ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: primaryColor,
      secondary: primaryColor.withOpacity(0.7),
      background: Colors.white,
      surface: Colors.white,
    ),
    useMaterial3: true,
  );
}


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
    // 1. Listen to changes in ThemeService (color AND dark mode)
    // The Provider.of<T>(context) must be inside the build method.
    final themeService = Provider.of<ThemeService>(context); 
    
    // 2. Dynamically create themes based on the current themeColor
    // These functions must be defined outside the class (as shown in the previous response)
    final lightTheme = createLightTheme(themeService.themeColor);
    final darkTheme = createDarkTheme(themeService.themeColor);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Listy',
      
      // Assign the dynamically created themes
      theme: lightTheme,
      darkTheme: darkTheme,
      
      // Set the themeMode based on the isDarkMode state
      themeMode: themeService.isDarkMode ? ThemeMode.dark : ThemeMode.light,

      
      // Check if user is already logged in
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange, // Listen for auth events
        builder: (context, snapshot) {
          final session = snapshot.data?.session;
          
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          // Check for a valid session
          if (session != null) {
            return const HomeScreen();
          }
          
          // No session found
          return const AuthScreen();
        },
      ),
    );
  }
}