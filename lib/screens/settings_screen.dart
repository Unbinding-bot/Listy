// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'auth_screen.dart';
import '../services/theme_service.dart';

class SettingsScreen extends StatelessWidget {
 const SettingsScreen({super.key});

 @override
 Widget build(BuildContext context) {
  final themeService = Provider.of<ThemeService>(context);
  final user = Supabase.instance.client.auth.currentUser;
  // Access the metadata we saved during sign up
  final username = user?.userMetadata?['username'] ?? "User";

  return Scaffold(
   appBar: AppBar(title: const Text("Settings")),
   body: ListView(
    children: [
     ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(username),
      subtitle: Text(user?.email ?? ""),
     ),
     // Dark Mode Toggle (NEW)
     ListTile(
      title: const Text('Dark Mode'),
      trailing: Switch(
       value: themeService.isDarkMode,
       onChanged: (newValue) {
        themeService.toggleDarkMode(newValue);
       },
      ),
      leading: Icon(themeService.isDarkMode ? Icons.dark_mode : Icons.light_mode),
      onTap: () {
        // Tapping the ListTile toggles the state
        themeService.toggleDarkMode(!themeService.isDarkMode);
      },
     ),
     
     const Divider(),

     // Color Selection (Using your existing list)
     Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(
       'Accent Color', 
       style: Theme.of(context).textTheme.titleMedium,
      ),
     ),
     
     Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0), // Padding applied here
      child: Wrap(
       spacing: 8.0,
       children: themeColors.map((color) {
        bool isSelected = themeService.themeColor == color;
        return GestureDetector(
         onTap: () => themeService.setThemeColor(color),
         child: CircleAvatar(
          backgroundColor: color,
          radius: isSelected ? 18 : 15,
          child: isSelected 
            ? const Icon(Icons.check, color: Colors.white) 
            : null,
         ),
        );
       }).toList(),
      ),
     ),
     
     const Divider(), // FIX: Comma added before this in the original file.
     
     ListTile(
      leading: const Icon(Icons.logout, color: Colors.red),
      title: const Text("Log Out", style: TextStyle(color: Colors.red)),
      onTap: () async {
       await Supabase.instance.client.auth.signOut();
       if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
         MaterialPageRoute(builder: (_) => const AuthScreen()), 
         (route) => false
        );
       }
      },
     )
    ],
   ),
  );
 }
 // Removed the unused _showThemeDialog method here.
}