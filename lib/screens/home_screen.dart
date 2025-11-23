// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'list_detail_screen.dart';
import 'settings_screen.dart';

// 1. CONVERT TO STATEFUL WIDGET
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final dbService = SupabaseService();
  
  // State for tracking selected lists
  final List<int> _selectedListIds = [];

  // --- Selection Management Methods ---
  void _toggleSelection(int listId) {
    setState(() {
      if (_selectedListIds.contains(listId)) {
        _selectedListIds.remove(listId);
      } else {
        _selectedListIds.add(listId);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedListIds.clear();
    });
  }

  // --- Bulk Action Methods ---
  Future<void> _deleteSelectedLists() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Bulk Deletion"),
        content: Text("Are you sure you want to delete ${_selectedListIds.length} lists? This is irreversible."),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true), 
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final idsToDelete = List<int>.from(_selectedListIds);
      _clearSelection(); // Clear selection immediately
      
      // Perform deletion for each selected ID
      for (final id in idsToDelete) {
        // You might consider a bulk delete RPC in Supabase for performance
        await dbService.deleteList(id);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${idsToDelete.length} lists deleted.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSelecting = _selectedListIds.isNotEmpty;

    return Scaffold(
      // 2. DYNAMIC APP BAR (Handles Selection vs. Normal View)
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: isSelecting
                ? Text('${_selectedListIds.length} Selected')
                : const Text("My Lists"),
            floating: true,
            leading: isSelecting
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _clearSelection,
                  )
                : null,
            actions: isSelecting
                ? [
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: _deleteSelectedLists,
                    ),
                    // Reorder/Move Action Placeholder (Requires DB update for sort_order)
                    IconButton(
                      icon: const Icon(Icons.swap_vert),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Drag items to reorder them.')),
                        );
                        // TODO: Set a state flag to enable drag/drop UI
                      },
                    ),
                  ]
                : [
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
              // ... (Loading/Error handling remains the same) ...
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return SliverFillRemaining(
                    child: Center(child: Text('Error: ${snapshot.error}')));
              }
              
              final lists = snapshot.data ?? [];

              if (lists.isEmpty) {
                return const SliverFillRemaining(
                   child: Center(child: Text("No lists yet. Tap + to create one.")),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final list = lists[index];
                    final listId = list['id'] as int;
                    final listName = list['name'] as String;
                    final isSelected = _selectedListIds.contains(listId);
                    
                    // 3. SELECTION WRAPPER
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: GestureDetector(
                        // Long press starts selection or toggles item
                        onLongPress: () => _toggleSelection(listId),
                        // Tap toggles selection if active, or navigates if inactive
                        onTap: isSelecting
                            ? () => _toggleSelection(listId)
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ListDetailScreen(
                                      listId: listId.toString(), 
                                      listName: listName,
                                      ownerId: list['owner_id'] as String,
                                    ),
                                  ),
                                );
                              },
                        
                        child: Container(
                          decoration: BoxDecoration(
                            // Highlight selected cards
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          
                          // 4. DISMISSIBLE / CARD
                          child: Dismissible(
                            key: ValueKey(listId), 
                            direction: isSelecting ? DismissDirection.none : DismissDirection.endToStart, // Disable swipe-to-delete when selecting
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20.0),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            confirmDismiss: (direction) => showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Confirm Deletion"),
                                content: Text("Are you sure you want to delete '$listName'? This action is irreversible."),
                                actions: <Widget>[
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            ),
                            onDismissed: (direction) async {
                              await dbService.deleteList(listId);
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("'$listName' deleted.")),
                              );
                            },
                            
                            child: Card(
                              elevation: 0, // Remove elevation as Container handles highlight
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // List Title Row (includes selection indicator)
                                    Row(
                                      children: [
                                        if (isSelecting) 
                                          Padding(
                                            padding: const EdgeInsets.only(right: 8.0),
                                            child: Icon(
                                              isSelected ? Icons.check_circle : Icons.circle_outlined,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            listName, 
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 20,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    // Item Preview Section (Fetches real data)
                                    // *** FIX APPLIED: Removed Expanded widget here ***
                                    FutureBuilder<List<Map<String, dynamic>>>(
                                      future: dbService.getListItemsPreview(listId),
                                      builder: (context, itemSnapshot) {
                                        if (!itemSnapshot.hasData) {
                                          return const SizedBox(); 
                                        }
                                        
                                        final previewItems = itemSnapshot.data!;
                                        
                                        final previewText = previewItems
                                            .map((item) => item['title'].toString())
                                            .join(', ');
                                        
                                        // 5. EMPTY LIST PREVIEW FIX: Display "Empty List" placeholder
                                        if (previewText.isEmpty) {
                                            return Opacity(
                                              opacity: 0.5,
                                              child: Text(
                                                'Empty List',
                                                style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                                                maxLines: 1, 
                                              ),
                                            );
                                        }
                                        
                                        return Opacity(
                                          opacity: 0.7,
                                          child: Text(
                                            previewText,
                                            style: const TextStyle(fontSize: 14),
                                            maxLines: 3, 
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      },
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
          // If selecting, the FAB should do nothing or clear selection
          if (isSelecting) {
            _clearSelection();
            return;
          }
          
          // Normal list creation and instant navigation
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Creating new list...')),
          );
          try {
            // Note: The new list will have the default name "Untitled List"
            final newList = await dbService.createNewList("Untitled List");
            
            if (context.mounted) {
              // Navigate to the newly created list
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ListDetailScreen(
                    listId: newList['id'].toString(), 
                    listName: newList['name'],
                    ownerId: newlist['owner_id'] as String,
                  ),
                ),
              );
            }
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('List created successfully!')),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error creating list: $e')),
            );
          }
        },
        child: isSelecting ? const Icon(Icons.close) : const Icon(Icons.add),
      ),
    );
  }
}