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
          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text("Change Theme Color"),
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: themeService.themeColor, // Show current color
                shape: BoxShape.circle,
              ),
            ),
            onTap: () {
              // Open a dialog for color selection
              _showThemeDialog(context, themeService); 
            },
          ),
          const Divider(),
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
  void _showThemeDialog(BuildContext context, ThemeService themeService) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Select App Color"),
          content: Wrap(
            spacing: 10,
            children: themeColors.map((color) {
              return GestureDetector(
                onTap: () {
                  themeService.setThemeColor(color);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: themeService.themeColor == color 
                        ? Border.all(color: Colors.black, width: 3) // Highlight selected
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}