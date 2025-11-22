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
              // Show a loading indicator if no data yet
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              // Show nothing if snapshot has no data (or an error)
              if (!snapshot.hasData || snapshot.hasError) {
                return const SliverFillRemaining(child: SizedBox());
              }
              
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
                        title: Text(
                          list['name'], 
                          style: const TextStyle(fontWeight: FontWeight.bold)
                        ),
                        // ADDED: A trailing icon to clearly define the list item border
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
        onPressed: () async {
          // Check if the widget is still mounted before showing the snackbar
          if (!context.mounted) return;
          
          // 1. Show loading feedback
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Creating new list...')),
          );

          try {
            // 2. Await the async call and CAPTURE the result map
            final newListData = await dbService.createNewList("Untitled List");
            
            if (!context.mounted) return;
            
            // Remove the loading snackbar
            ScaffoldMessenger.of(context).removeCurrentSnackBar(); 
            
            // 3. Navigate immediately to the detail screen for instant editing
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ListDetailScreen(
                  listId: newListData['id'].toString(), // Use the returned ID
                  listName: newListData['name'],      // Use the returned name
                ),
              ),
            );

          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            // 4. Show error feedback
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