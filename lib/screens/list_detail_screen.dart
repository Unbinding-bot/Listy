import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

// --- Placeholder for complex features (Keep this) ---
class DrawingScreen extends StatelessWidget {
  const DrawingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Drawing Tools")),
      body: const Center(child: Text("Drawing Canvas and Tools Go Here")),
    );
  }
}
// ----------------------------------------

class ListDetailScreen extends StatefulWidget {
  final String listId;
  final String listName;

  const ListDetailScreen({super.key, required this.listId, required this.listName});

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  final dbService = SupabaseService();
  final TextEditingController _addItemController = TextEditingController();
  final FocusNode _addItemFocusNode = FocusNode();

  // State for the item data (needed for ReorderableListView)
  List<Map<String, dynamic>> _items = [];
  
  // State for multi-selection
  final List<int> _selectedItemIds = [];
  bool get isSelecting => _selectedItemIds.isNotEmpty;

  // State for the bottom options bar (just an example for font size)
  double _currentFontSize = 16.0;
  
  // --- Initialization and Cleanup ---

  @override
  void initState() {
    super.initState();
    // Start listening to the stream immediately
    dbService.getItemsStream(int.parse(widget.listId)).listen((data) {
      if (mounted) {
        // Update the local list whenever Supabase emits new data
        setState(() {
          _items = data;
        });
      }
    });
  }

  @override
  void dispose() {
    _addItemController.dispose();
    _addItemFocusNode.dispose();
    super.dispose();
  }
  
  // --- Selection Management ---

  void _toggleSelection(int itemId) {
    setState(() {
      if (_selectedItemIds.contains(itemId)) {
        _selectedItemIds.remove(itemId);
      } else {
        _selectedItemIds.add(itemId);
        // Deselecting an item by long press on nothing is achieved by
        // checking the isSelecting flag on taps outside the list.
      }
    });
  }
  
  void _clearSelection() {
    setState(() {
      _selectedItemIds.clear();
    });
  }

  // --- Core Action Methods ---

  void _addNewItem(String title) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return;

    await dbService.addItem(int.parse(widget.listId), trimmedTitle);
    
    _addItemController.clear();
    _addItemFocusNode.requestFocus(); // Keep focus for rapid entry
  }

  Future<void> _deleteSelectedItems() async {
    final idsToDelete = List<int>.from(_selectedItemIds);
    _clearSelection(); // Clear selection immediately
    
    // Perform deletion for each selected ID
    for (final id in idsToDelete) {
      await dbService.deleteItem(id);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${idsToDelete.length} items deleted.')),
    );
  }
  
  Future<void> _updateSelectedItems(bool isCompleted) async {
    final idsToUpdate = List<int>.from(_selectedItemIds);
    // Note: Do not clear selection yet, allow user to continue bulk editing
    
    for (final id in idsToUpdate) {
      await dbService.updateItem(id, {'is_completed': isCompleted});
    }
  }

  // --- Reordering Logic (Placeholder - requires 'sort_order' column in DB) ---
  void _onReorder(int oldIndex, int newIndex) {
    // This handles local reordering immediately for smooth UX
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    
    // TODO: 
    // 1. Send bulk updates to Supabase to save the new 'sort_order' for all items involved.
  }


  // --- UI Builders ---

  Widget _buildNormalAppBar() {
    return AppBar(
      title: Text(widget.listName),
      actions: [
        IconButton(
          icon: const Icon(Icons.brush),
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const DrawingScreen()));
          },
        ),
        IconButton(
          icon: const Icon(Icons.person_add),
          onPressed: () {
            // TODO: Implement sharing/membership management
          },
        ),
      ],
    );
  }

  Widget _buildSelectionAppBar() {
    return AppBar(
      title: Text('${_selectedItemIds.length} Items Selected'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _clearSelection,
      ),
      actions: [
        // Check All / Uncheck All (Toggle completion status)
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: 'Check All / Uncheck All',
          onPressed: () {
            // Check if ALL selected items are completed
            final allCompleted = _selectedItemIds.every((id) => _items.firstWhere((item) => item['id'] == id)['is_completed'] == true);
            // If all are completed, uncheck them. Otherwise, check them.
            _updateSelectedItems(!allCompleted);
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          tooltip: 'Delete Selected',
          onPressed: _deleteSelectedItems,
        ),
      ],
    );
  }
  
  // Renders the bottom bar for formatting when in normal mode
  Widget _buildNormalBottomBar() {
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          // Font Size Button
          IconButton(
            icon: const Icon(Icons.format_size),
            onPressed: () {
              setState(() {
                _currentFontSize = _currentFontSize == 16.0 ? 20.0 : 16.0; 
              });
            },
            tooltip: 'Toggle Font Size',
          ),
          // Bold Button
          IconButton(
            icon: const Icon(Icons.format_bold),
            onPressed: () {}, // TODO: Implement bold style update
            tooltip: 'Bold',
          ),
          // Italic Button
          IconButton(
            icon: const Icon(Icons.format_italic),
            onPressed: () {}, // TODO: Implement italic style update
            tooltip: 'Italicize',
          ),
          // Color Picker/Palette Button
          IconButton(
            icon: const Icon(Icons.color_lens),
            onPressed: () {}, // TODO: Implement color picker dialog
            tooltip: 'Change Font Color/Highlight',
          ),
          // Disable Checkboxes Button (Checkbox with slash icon)
          IconButton(
            icon: const Icon(Icons.disabled_by_default_outlined), // Closest standard icon
            onPressed: () {
              // TODO: Implement logic to toggle checkbox visibility/functionality
            },
            tooltip: 'Hide Checkboxes',
          ),
        ],
      ),
    );
  }

  // Renders the bottom bar for bulk actions when in selection mode
  Widget _buildSelectionBottomBar() {
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          // Check All
          IconButton(
            icon: const Icon(Icons.check_box),
            onPressed: () => _updateSelectedItems(true),
            tooltip: 'Check All Selected',
          ),
          // Uncheck All
          IconButton(
            icon: const Icon(Icons.check_box_outline_blank),
            onPressed: () => _updateSelectedItems(false),
            tooltip: 'Uncheck All Selected',
          ),
          // Delete Selected
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteSelectedItems,
            tooltip: 'Delete Selected Items',
          ),
          // Move (Reordering is implicit with ReorderableListView, 
          // but this could initiate a move to *another list* if implemented)
          IconButton(
            icon: const Icon(Icons.move_up),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Drag items to reorder them.')),
              );
            },
            tooltip: 'Reorder/Move',
          ),
          // Deselect (Long press on nothing will deselect)
          IconButton(
            icon: const Icon(Icons.cancel),
            onPressed: _clearSelection,
            tooltip: 'Clear Selection',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: isSelecting ? _buildSelectionAppBar() : _buildNormalAppBar(),
      
      // Tap outside the list to deselect all items
      body: GestureDetector(
        onTap: isSelecting ? _clearSelection : null,
        child: Column(
          children: [
            // 1. The main list of items (Now ReorderableListView)
            Expanded(
              child: _items.isEmpty 
                  ? const Center(child: Text("Start by adding a new item below."))
                  : ReorderableListView.builder(
                      // IMPORTANT: ReorderableListView MUST be given an explicit list,
                      // not streamed data directly. We handle streaming in initState.
                      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                      itemCount: _items.length,
                      onReorder: _onReorder,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final itemId = item['id'] as int;
                        final isCompleted = item['is_completed'] as bool;
                        final isSelected = _selectedItemIds.contains(itemId);

                        // Wrap each item in a LongPress and Tap Detector
                        return GestureDetector(
                          key: ValueKey(itemId), // Required for ReorderableListView
                          onLongPress: () => _toggleSelection(itemId),
                          onTap: isSelecting ? () => _toggleSelection(itemId) : null, // Only toggle selection if mode is active

                          child: Container(
                            color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                children: [
                                  // LEFT SIDE: Selection/Checkbox Toggling Zone
                                  GestureDetector(
                                    onTap: isSelecting
                                        ? () => _toggleSelection(itemId) // If selecting, tap toggles selection
                                        : () async { // Otherwise, tap toggles completion
                                            await dbService.updateItem(
                                              itemId, 
                                              {'is_completed': !isCompleted},
                                            );
                                          },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      child: isSelecting
                                          ? Icon( // Show selection indicator
                                              isSelected ? Icons.check_circle : Icons.circle_outlined,
                                              color: Theme.of(context).colorScheme.primary,
                                            )
                                          : Icon( // Show completion checkbox
                                              isCompleted ? Icons.check_box : Icons.check_box_outline_blank,
                                              color: isCompleted ? Theme.of(context).colorScheme.primary : Colors.grey,
                                            ),
                                    ),
                                  ),

                                  // RIGHT SIDE: Editable Text Field Zone
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: item['title'] as String,
                                      enabled: !isSelecting, // Disable editing when selecting
                                      keyboardType: TextInputType.text,
                                      style: TextStyle(
                                        fontSize: _currentFontSize,
                                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                                        // Use Theme colors for better light/dark mode support
                                        color: isCompleted ? Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6) : Theme.of(context).textTheme.bodyMedium?.color, 
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      // On submit (deletion/update logic)
                                      onFieldSubmitted: (newTitle) async {
                                        final trimmedTitle = newTitle.trim();
                                        if (trimmedTitle.isEmpty) {
                                          await dbService.deleteItem(itemId);
                                        } else {
                                          await dbService.updateItem(
                                            itemId, 
                                            {'title': trimmedTitle},
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            
            // 2. Add New Item Input Field
            if (!isSelecting) // Hide input field when in selection mode
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _addItemController,
                  focusNode: _addItemFocusNode,
                  decoration: InputDecoration(
                    hintText: "New item...",
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => _addNewItem(_addItemController.text),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    _addNewItem(value);
                  },
                ),
              ),
          ],
        ),
      ),
      
      // 3. Bottom Options Bar for Styling/Tools
      bottomNavigationBar: isSelecting ? _buildSelectionBottomBar() : _buildNormalBottomBar(),
    );
  }
}