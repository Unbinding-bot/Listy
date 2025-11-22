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
      FloatingActionButton(
        onPressed: () async {
            // 1. Show loading feedback (Optional, but good practice)
            ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Creating new list...')),
            );

            try {
                // 2. Await the async call to ensure it completes
                await dbService.createNewList("Untitled List");
      
                // 3. Show success feedback
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('List created successfully!')),
                );
        
            } catch (e) {
                // 4. Show error feedback, especially useful for debugging RLS failures
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error creating list: $e')),
                );
            }
        },
        child: const Icon(Icons.add),
        ),
    );
  }
}