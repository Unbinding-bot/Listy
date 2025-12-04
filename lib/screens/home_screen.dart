// lib/screens/home_screen.dart
// Fixes:
// - Make drag handle actually start reorder by using ReorderableDragStartListener when isReorderable
// - Ensure long-press selection only applies when not reordering (keeps existing behavior)
// - Keep everything else as in your merged file (animated diffs, FAB create flow, etc.)

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'list_detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final dbService = SupabaseService();

  // Animated Sliver list state key
  final GlobalKey<SliverAnimatedListState> _listsAnimatedKey = GlobalKey<SliverAnimatedListState>();

  // Local cache of lists (kept in authoritative order)
  List<Map<String, dynamic>> _lists = [];
  bool _listsLoaded = false;

  // Stream subscription to the lists stream
  StreamSubscription<List<Map<String, dynamic>>>? _listsSub;

  // State for tracking selected lists (multi-select mode)
  final List<int> _selectedListIds = [];

  // State for tracking reordering mode
  bool _isReordering = false;

  @override
  void initState() {
    super.initState();
    // Subscribe to the lists stream and apply minimal diffs to Animated Sliver
    _listsSub = dbService.getMyLists().listen((snapshot) {
      _applyListsDiffs(snapshot);
    }, onError: (e) {
      // handle/log if needed
    });
  }

  @override
  void dispose() {
    _listsSub?.cancel();
    super.dispose();
  }

  // Compute and apply minimal diffs between _lists (current) and authoritative snapshot (newLists).
  void _applyListsDiffs(List<Map<String, dynamic>> newLists) {
    final oldIds = _lists.map((l) => l['id']?.toString()).toList();
    final newIds = newLists.map((l) => l['id']?.toString()).toList();

    if (!_listsLoaded) {
      setState(() {
        _lists = List<Map<String, dynamic>>.from(newLists);
        _listsLoaded = true;
      });
      
      if (_lists.isNotEmpty) {
        
        for (int i = 0; i < _lists.length; i++) {
          _listsAnimatedKey.currentState?.insertItem(i, duration: Duration.zero);
        }
      }
      return;
    }

    final removedIds = <String>[];
    for (final id in oldIds) {
      if (id != null && !newIds.contains(id)) removedIds.add(id);
    }

    for (final rid in removedIds) {
      final idx = _lists.indexWhere((l) => l['id']?.toString() == rid);
      if (idx != -1) {
        final removed = _lists.removeAt(idx);
        _listsAnimatedKey.currentState?.removeItem(
          idx,
          (context, animation) => _buildListTileAnimated(removed, animation, removing: true),
          duration: const Duration(milliseconds: 300),
        );
      }
    }

    final updatedIds = <String>[];
    for (final nl in newLists) {
      final nid = nl['id']?.toString();
      if (nid == null) continue;
      final oldIndex = _lists.indexWhere((l) => l['id']?.toString() == nid);
      if (oldIndex != -1) {
        final old = _lists[oldIndex];
        if (old['name'] != nl['name']) {
          _lists[oldIndex] = nl;
          updatedIds.add(nid);
        }
      }
    }

    for (int i = 0; i < newLists.length; i++) {
      final nl = newLists[i];
      final nid = nl['id']?.toString();
      if (nid == null) continue;
      final exists = _lists.any((l) => l['id']?.toString() == nid);
      if (!exists) {
        int insertIndex = _lists.length;
        for (int j = i + 1; j < newLists.length; j++) {
          final nextId = newLists[j]['id']?.toString();
          final existingIndex = _lists.indexWhere((l) => l['id']?.toString() == nextId);
          if (existingIndex != -1) {
            insertIndex = existingIndex;
            break;
          }
        }
        _lists.insert(insertIndex, nl);
        _listsAnimatedKey.currentState?.insertItem(insertIndex, duration: const Duration(milliseconds: 300));
      }
    }

    _lists.sort((a, b) {
      final ia = newLists.indexWhere((e) => e['id'] == a['id']);
      final ib = newLists.indexWhere((e) => e['id'] == b['id']);
      return ia.compareTo(ib);
    });

    if (updatedIds.isNotEmpty) setState(() {});
  }

  Widget _buildListCardContent(Map<String, dynamic> listRow, {int? index, bool isReorderable = false}) {
    final listId = listRow['id'] as int;
    final listName = listRow['name'] as String;
    final isSelected = _selectedListIds.contains(listId);
    final isSelecting = _selectedListIds.isNotEmpty;

    // Drag handle (when reordering) - wrapped in ReorderableDragStartListener so drag actually starts
    final Widget dragHandle = isReorderable
        ? ReorderableDragStartListener(
            index: index ?? 0,
            child: const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: Icon(Icons.drag_handle, color: Colors.grey),
            ),
          )
        : const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: GestureDetector(
        onLongPress: isReorderable ? null : () => _toggleSelection(listId),
        onTap: isSelecting
            ? () => _toggleSelection(listId)
            : () {
                final ownerId = (listRow['owner_id'] as String?) ?? '';
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
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.15) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Dismissible(
            key: ValueKey('dismiss-$listId'),
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
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("'$listName' deleted.")));
              }
            },
            child: Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    if (isSelecting)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: Theme.of(context).colorScheme.primary),
                      ),

                    // Reorder handle (now a proper drag start listener when isReorderable)
                    if (_isReordering && isReorderable) dragHandle,

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(listName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Theme.of(context).colorScheme.primary), maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: dbService.getListItemsPreview(listId),
                            builder: (context, itemSnapshot) {
                              if (!itemSnapshot.hasData) return const SizedBox();
                              final previewItems = itemSnapshot.data!;
                              final previewText = previewItems.map((item) => item['title'].toString()).join(', ');
                              final contentText = previewText.isEmpty ? 'Empty List' : previewText;
                              final fontStyle = previewText.isEmpty ? FontStyle.italic : FontStyle.normal;
                              final opacity = previewText.isEmpty ? 0.5 : 0.7;
                              return Opacity(opacity: opacity, child: Text(contentText, style: TextStyle(fontSize: 14, fontStyle: fontStyle), maxLines: 3, overflow: TextOverflow.ellipsis));
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
  }

  Widget _buildListTileAnimated(Map<String, dynamic> listRow, Animation<double> animation, {bool removing = false}) {
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: 0.0,
      child: FadeTransition(opacity: animation, child: _buildListCardContent(listRow, index: _lists.indexOf(listRow), isReorderable: _isReordering)),
    );
  }

  void _toggleSelection(int listId) {
    if (_isReordering) return;
    setState(() {
      if (_selectedListIds.contains(listId)) _selectedListIds.remove(listId);
      else _selectedListIds.add(listId);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedListIds.clear();
    });
  }

  void _toggleReordering() {
    setState(() {
      _isReordering = !_isReordering;
      if (_isReordering) _clearSelection();
    });
  }

  Future<void> _deleteSelectedLists() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Bulk Deletion"),
        content: Text("Are you sure you want to delete ${_selectedListIds.length} lists? This is irreversible."),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      final idsToDelete = List<int>.from(_selectedListIds);
      _clearSelection();
      for (final id in idsToDelete) await dbService.deleteList(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${idsToDelete.length} lists deleted.')));
    }
  }

  Future<void> _onReorder(List<Map<String, dynamic>> listsSnapshot, int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final reorderedList = List<Map<String, dynamic>>.from(_lists);
    final listToMove = reorderedList.removeAt(oldIndex);
    reorderedList.insert(newIndex, listToMove);

    final updates = reorderedList.asMap().entries.map((entry) {
      final newPosition = entry.key + 1;
      return {'id': entry.value['id'] as int, 'sort_order': newPosition};
    }).toList();

    try {
      // await dbService.updateListOrder(updates); // implement if desired
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('List order updated.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving new order: $e')));
    }

    _toggleReordering();
  }

  Future<void> _createAndOpenNewList() async {
    if (_selectedListIds.isNotEmpty) {
      _clearSelection();
      return;
    }

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Creating new list...')));
    try {
      final newList = await dbService.createNewList("Untitled List");
      final newListId = newList['id']?.toString() ?? '0';
      final newListName = (newList['name'] as String?) ?? 'Untitled List';
      final returnedOwnerId = newList['owner_id']?.toString();
      final newOwnerId = (returnedOwnerId != null && returnedOwnerId.isNotEmpty) ? returnedOwnerId : (dbService.currentUser?.id ?? '');

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ListDetailScreen(listId: newListId, listName: newListName, ownerId: newOwnerId),
        ),
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('List created and opened.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create list: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSelecting = _selectedListIds.isNotEmpty;
    final titleText = isSelecting ? '${_selectedListIds.length} Selected' : (_isReordering ? 'Reorder Lists' : 'My Lists');

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(titleText),
            floating: true,
            leading: isSelecting || _isReordering
                ? IconButton(icon: const Icon(Icons.close), onPressed: isSelecting ? _clearSelection : _toggleReordering)
                : null,
            actions: isSelecting
                ? [IconButton(icon: const Icon(Icons.delete), onPressed: _deleteSelectedLists)]
                : [
                    IconButton(
                      icon: Icon(_isReordering ? Icons.done : Icons.swap_vert),
                      onPressed: _isReordering
                          ? () {
                              _toggleReordering();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reordering cancelled.')));
                            }
                          : _toggleReordering,
                    ),
                    IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
                  ],
          ),

          if (_isReordering)
            SliverReorderableList(
              itemCount: _lists.length,
              itemBuilder: (context, index) {
                final list = _lists[index];
                return KeyedSubtree(
                  key: ValueKey(list['id']),
                  child: _buildListCardContent(list, index: index, isReorderable: true),
                );
              },
              onReorder: (oldIndex, newIndex) => _onReorder(_lists, oldIndex, newIndex),
            )
          else
            SliverAnimatedList(
              key: _listsAnimatedKey,
              initialItemCount: _lists.length,
              itemBuilder: (context, index, animation) => _buildListTileAnimated(_lists[index], animation),
            ),

          if (_listsLoaded && _lists.isEmpty) const SliverFillRemaining(child: Center(child: Text("No lists yet. Tap + to create one."))),
        ],
      ),

      floatingActionButton: FloatingActionButton(onPressed: _isReordering ? null : _createAndOpenNewList, child: isSelecting || _isReordering ? const Icon(Icons.close) : const Icon(Icons.add)),
    );
  }
}