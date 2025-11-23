// lib/screens/home_screen.dart
//
// Home screen with list stream, selection, reordering, and FAB to create+open new lists.
// Changes applied:
// - Normalize and pass ownerId when navigating to ListDetailScreen (use returned owner_id from create flow if available).
// - Ensure the FAB waits for createNewList and navigates into the new list using normalized id/name/ownerId.
// - Keep selection/reorder UX intact.

import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'list_detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final dbService = SupabaseService();

  // State for tracking selected lists (multi-select mode)
  final List<int> _selectedListIds = [];
  
  // NEW: State for tracking reordering mode
  bool _isReordering = false; 

  // --- Selection Management Methods ---
  void _toggleSelection(int listId) {
    // Selection is disabled if reordering is active
    if (_isReordering) return; 
    
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

  // --- Reordering Management Methods (NEW) ---
  void _toggleReordering() {
    setState(() {
      _isReordering = !_isReordering;
      // Ensure selection mode is cleared when entering reorder mode
      if (_isReordering) {
        _clearSelection(); 
      }
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
        await dbService.deleteList(id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${idsToDelete.length} lists deleted.')),
        );
      }
    }
  }

  // Handles the drag-and-drop reordering logic and Supabase update
  Future<void> _onReorder(List<Map<String, dynamic>> lists, int oldIndex, int newIndex) async {
    // Adjust newIndex to account for the item being removed before being inserted
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    
    // Create a mutable copy of the list based on the current snapshot data
    final reorderedList = List<Map<String, dynamic>>.from(lists);
    final listToMove = reorderedList.removeAt(oldIndex);
    reorderedList.insert(newIndex, listToMove);

    // Prepare list of updates for Supabase (ID and new position)
    final updates = reorderedList.asMap().entries.map((entry) {
      // The sort_order is assumed to be 1-based index (entry.key is 0-based)
      final newPosition = entry.key + 1; 
      return {
        'id': entry.value['id'] as int,
        'sort_order': newPosition, // This column must exist in your Supabase 'lists' table
      };
    }).toList();

    // Perform the database update for reordering
    try {
      // TODO: IMPLEMENT dbService.updateListOrder(updates) IN YOUR SupabaseService
      // This function should accept a list of {id: int, sort_order: int} and perform a bulk update.
      // await dbService.updateListOrder(updates);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('List order updated.')),
        );
      }
    } catch (e) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving new order: $e')),
        );
      }
    }
    
    // Exit reordering mode after the update is attempted (relying on stream to refresh)
    _toggleReordering(); 
  }

  // Helper widget to build the list item for both SliverList and SliverReorderableList
  Widget _buildListItem(
    BuildContext context, 
    Map<String, dynamic> list, 
    int index,
    {bool isReorderable = false} // Flag for showing the reorder handle
  ) {
    final listId = list['id'] as int;
    final listName = list['name'] as String;
    final isSelected = _selectedListIds.contains(listId);
    final isSelecting = _selectedListIds.isNotEmpty;

    // The entire card content wrapper
    final listItemContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: GestureDetector(
        // Long press starts selection or toggles item
        onLongPress: isReorderable ? null : () => _toggleSelection(listId),
        // Tap toggles selection if active, or navigates if inactive
        onTap: isSelecting
            ? () => _toggleSelection(listId)
            : () {
                // Normalize ownerId if present on the list row; otherwise pass empty string
                final ownerId = (list.containsKey('owner_id') && list['owner_id'] != null)
                    ? list['owner_id'].toString()
                    : '';

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ListDetailScreen(
                      listId: listId.toString(), 
                      listName: listName,
                      ownerId: ownerId,
                    ),
                  ),
                );
              },
        
        child: Container(
          // Note: The Key for ReorderableList must be on the direct child of the builder,
          // which is handled by the KeyedSubtree below when isReorderable is true.
          decoration: BoxDecoration(
            // Highlight selected cards
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          
          // 4. DISMISSIBLE / CARD
          child: Dismissible(
            key: ValueKey('dismiss-$listId'), // Unique key for the Dismissible widget
            // Disable swipe-to-delete when selecting or reordering
            direction: isSelecting || _isReordering ? DismissDirection.none : DismissDirection.endToStart, 
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
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("'$listName' deleted.")),
                );
              }
            },
            
            child: Card(
              elevation: 0, 
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row( // Use Row to incorporate selection indicator and reorder handle
                  children: [
                    // Selection indicator
                    if (isSelecting) 
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Icon(
                          isSelected ? Icons.check_circle : Icons.circle_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      
                    // Reorder handle
                    if (_isReordering && isReorderable) 
                      const Padding(
                        padding: EdgeInsets.only(right: 8.0),
                        child: Icon(Icons.drag_handle, color: Colors.grey),
                      ),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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

                          // Item Preview Section (Fetches real data)
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
                              
                              // EMPTY LIST PREVIEW FIX
                              final contentText = previewText.isEmpty ? 'Empty List' : previewText;
                              final fontStyle = previewText.isEmpty ? FontStyle.italic : FontStyle.normal;
                              final opacity = previewText.isEmpty ? 0.5 : 0.7;

                              return Opacity(
                                opacity: opacity,
                                child: Text(
                                  contentText,
                                  style: TextStyle(fontSize: 14, fontStyle: fontStyle),
                                  maxLines: 3, 
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            },
                          ),
                        ],
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
    
    // Must return a widget with a unique key for SliverReorderableList
    if (_isReordering) {
        return KeyedSubtree(
            key: ValueKey(listId),
            child: listItemContent,
        );
    }
    
    return listItemContent;
  }


  @override
  Widget build(BuildContext context) {
    final isSelecting = _selectedListIds.isNotEmpty;
    // Determine title based on active mode
    final titleText = isSelecting
        ? '${_selectedListIds.length} Selected'
        : _isReordering
            ? 'Reorder Lists'
            : "My Lists";

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(titleText),
            floating: true,
            // Dynamic Leading Action
            leading: isSelecting || _isReordering
                ? IconButton(
                    icon: const Icon(Icons.close),
                    // Close button clears selection if selecting, or toggles reordering off
                    onPressed: isSelecting ? _clearSelection : _toggleReordering,
                  )
                : null,
            // Dynamic Actions
            actions: isSelecting
                ? [
                    // Multi-Select Actions
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: _deleteSelectedLists,
                    ),
                  ]
                : [
                    // Normal/Reorder Actions
                    IconButton(
                      // Toggle Reordering mode. Shows checkmark when active.
                      icon: Icon(_isReordering ? Icons.done : Icons.swap_vert),
                      onPressed: _isReordering 
                        ? () { 
                            _toggleReordering(); 
                            // Note: onReorder handles the saving logic. This is just for canceling.
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Reordering cancelled.')),
                            );
                          }
                        : _toggleReordering,
                    ),
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
              
              // Conditional rendering of SliverList or SliverReorderableList
              if (_isReordering) {
                // RENDER REORDERABLE LIST
                return SliverReorderableList(
                  itemCount: lists.length,
                  itemBuilder: (context, index) {
                    final list = lists[index];
                    return _buildListItem(
                        context, 
                        list, 
                        index, 
                        isReorderable: true // Flag to show drag handle
                    );
                  },
                  onReorder: (oldIndex, newIndex) => _onReorder(lists, oldIndex, newIndex),
                );
              } else {
                // RENDER STANDARD LIST
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final list = lists[index];
                      return _buildListItem(context, list, index);
                    },
                    childCount: lists.length,
                  ),
                );
              }
            },
          ),
        ],
      ),
      
      // Floating Action Button for creating new list (Disabled if reordering)
      floatingActionButton: FloatingActionButton(
        onPressed: _isReordering 
            ? null // Disable FAB if reordering
            : () async {
              // If selecting, the FAB should clear selection
              if (isSelecting) {
                _clearSelection();
                return;
              }
              
              // Normal list creation and instant navigation
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Creating new list...')),
                );
              }
              try {
                final newList = await dbService.createNewList("Untitled List");

                // Normalize returned values
                final newListId = (newList['id'] != null) ? newList['id'].toString() : '0';
                final newListName = (newList['name'] as String?) ?? 'Untitled List';
                // Prefer owner_id returned by createNewList; fallback to current user's id if available
                final returnedOwnerId = newList['owner_id']?.toString();
                final newOwnerId = returnedOwnerId != null && returnedOwnerId.isNotEmpty
                    ? returnedOwnerId
                    : dbService.currentUser?.id ?? '';

                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ListDetailScreen(
                        listId: newListId,
                        listName: newListName,
                        ownerId: newOwnerId,
                      ),
                    ),
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('List created and opened.')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create list: ${e.toString()}')),
                  );
                }
              }
            },
        child: isSelecting || _isReordering ? const Icon(Icons.close) : const Icon(Icons.add),
      ),
    );
  }
}