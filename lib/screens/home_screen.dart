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
      // The body contains the CustomScrollView with the SliverAppBar
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text("My Lists"),
            floating: true,
            actions: [
              // User Profile/Settings Button
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          
          // The List of Lists (StreamBuilder)
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: dbService.getMyLists(),
            builder: (context, snapshot) {
              // Show loading or error state
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return SliverFillRemaining(
                    child: Center(child: Text('Error: ${snapshot.error}')));
              }
              
              final lists = snapshot.data ?? [];

              // Show empty list message
              if (lists.isEmpty) {
                return const SliverFillRemaining(
                   child: Center(child: Text("No lists yet. Tap + to create one.")),
                );
              }

              // Display the lists
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final list = lists[index];
                    final listId = list['id'] as int;
                    final listName = list['name'] as String;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: Dismissible(
                        key: ValueKey(listId), // Unique key for Dismissible
                        direction: DismissDirection.endToStart, // Swipe right-to-left
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20.0),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        
                        // Confirmation dialog before deleting
                        confirmDismiss: (direction) {
                          return showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Confirm Deletion"),
                              content: Text("Are you sure you want to delete '$listName'? This action is irreversible."),
                              actions: <Widget>[
                                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(true), 
                                  child: const Text("Delete", style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                        },
                        
                        // Perform deletion if confirmed
                        onDismissed: (direction) async {
                          await dbService.deleteList(listId);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("'$listName' deleted.")),
                          );
                        },
                        
                        // Dynamic List Card Preview
                        child: Card(
                          elevation: 2,
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ListDetailScreen(
                                    listId: listId.toString(), 
                                    listName: listName,
                                  ),
                                ),
                              );
                            },
                            child: ConstrainedBox( // Constrains the size for the preview
                              constraints: const BoxConstraints(
                                minHeight: 80,
                                maxHeight: 150, 
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // List Title
                                    Text(
                                      listName, 
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),

                                    // Item Preview Placeholder (To be updated with actual item data)
                                    const Expanded(
                                      child: Opacity(
                                        opacity: 0.7,
                                        child: Text(
                                          'Items: Buy milk, Pay bills, Call mom, Exercise...',
                                          style: TextStyle(fontSize: 14),
                                          maxLines: 3, 
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
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
      
      // Floating Action Button for creating new list
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Show loading feedback
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Creating new list...')),
          );

          try {
            // Call the RPC function via the service
            await dbService.createNewList("Untitled List");
            
            // Show success feedback
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('List created successfully!')),
            );
          } catch (e) {
            // Show error feedback for RLS or other failures
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