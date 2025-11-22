// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'list_detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dbService = SupabaseService();

    return Scaffold(
      // Special "Sliver" App Bar for that scrolling effect
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text("My Lists"),
            floating: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          // The List of Lists
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: dbService.getMyLists(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SliverFillRemaining(child: SizedBox());
              final lists = snapshot.data!;

              if (lists.isEmpty) {
                 return const SliverFillRemaining(
                   child: Center(child: Text("No lists yet. Tap + to create one.")),
                 );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final list = lists[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text(list['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ListDetailScreen(
                                listId: list['id'].toString(), 
                                listName: list['name']
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                  childCount: lists.length,
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => dbService.createNewList("Untitled List"),
        child: const Icon(Icons.add),
      ),
    );
  }
}