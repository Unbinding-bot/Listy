// lib/screens/list_detail_screen.dart
// Merged and updated ListDetailScreen:
// - Uses authoritative list data fetched from the DB after creation/opening
// - Normalizes ID comparisons to avoid int/string mismatches
// - Uses role lookup to determine if current user is owner (allows editing, adding members)
// - Automatically prompts to edit the title when a newly-created "Untitled" list opens and the current user is the owner
// - Preserves existing UI/formatting/reorder/item logic from your original file

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
  final String ownerId; // <--- initial/optional ownerId passed from parent (may be optimistic)

  const ListDetailScreen({
    super.key,
    required this.listId,
    required this.listName,
    required this.ownerId,
  });

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

  // NEW: Formatting states for the SELECTED items (used for the bottom bar UI)
  bool _isBoldSelected = false;
  bool _isItalicSelected = false;

  // Local variable to allow the listName in the AppBar to change
  late String _localListName;

  // Authoritative owner id loaded from DB (string)
  String _authoritativeOwnerId = '';

  // Track current user id and whether they are owner (derived from role or ownerId)
  String _currentUserId = '';
  bool _isCurrentUserOwner = false;

  // Helper: normalize and compare IDs safely
  bool _idsEqual(dynamic a, dynamic b) {
    if (a == null || b == null) return false;
    return a.toString() == b.toString();
  }

  // --- Initialization and Cleanup ---
  @override
  void initState() {
    super.initState();
    _localListName = widget.listName; // Initialize local name from widget

    // capture current user id (if available)
    _currentUserId = dbService.currentUser?.id ?? '';

    // Start listening to the stream immediately
    dbService.getItemsStream(int.parse(widget.listId)).listen((data) {
      if (mounted) {
        // Update the local list whenever Supabase emits new data
        setState(() {
          _items = data;
        });
      }
    });

    // Fetch authoritative list owner and the current user's role for this list
    _initOwnershipAndName();
  }

  @override
  void dispose() {
    _addItemController.dispose();
    _addItemFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initOwnershipAndName() async {
    try {
      final listRow = await dbService.getListById(int.parse(widget.listId));
      final role = await dbService.getCurrentUserRole(int.parse(widget.listId));

      if (!mounted) return;

      setState(() {
        // If DB returned values use them, otherwise keep the widget-provided fallback
        _authoritativeOwnerId = listRow?['owner_id']?.toString() ?? widget.ownerId;
        _localListName = listRow?['name'] ?? widget.listName;
        _currentUserId = dbService.currentUser?.id ?? '';
        _isCurrentUserOwner = (role == 'owner') || _idsEqual(_authoritativeOwnerId, _currentUserId);
      });

      // If the list looks newly-created/untitled and the current user is owner,
      // prompt them to rename it. Use post-frame callback so dialogs open safely.
      if (_isCurrentUserOwner &&
          (_localListName.trim().isEmpty || _localListName.toLowerCase().contains('untitled'))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showEditTitleDialog();
        });
      }
    } catch (_) {
      // swallow errors; UI will continue using widget-provided fallback values
    }
  }

  // --- Selection Management ---

  void _updateFormattingBarState() {
    if (_selectedItemIds.isEmpty) {
      setState(() {
        _isBoldSelected = false;
        _isItalicSelected = false;
      });
      return;
    }

    // Get the items corresponding to selected IDs
    final selectedItems = _items.where((item) => _selectedItemIds.contains(item['id'])).toList();

    if (selectedItems.isEmpty) return;

    // Check if ALL selected items share the property (for UI state)
    final allBold = selectedItems.every((item) => item['is_bold'] == true);
    final allItalic = selectedItems.every((item) => item['is_italic'] == true);

    setState(() {
      _isBoldSelected = allBold;
      _isItalicSelected = allItalic;
    });
  }

  void _toggleSelection(int itemId) {
    setState(() {
      if (_selectedItemIds.contains(itemId)) {
        _selectedItemIds.remove(itemId);
      } else {
        _selectedItemIds.add(itemId);
      }
      _updateFormattingBarState();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedItemIds.clear();
      _updateFormattingBarState();
    });
  }

  // --- Core Action Methods ---

  Future<void> _addNewItem(String title) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return;

    try {
      await dbService.addItem(int.parse(widget.listId), trimmedTitle);
      _addItemController.clear();
      _addItemFocusNode.requestFocus(); // Keep focus for rapid entry
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add item: ${e.toString()}')));
      }
    }
  }

  Future<void> _deleteSelectedItems() async {
    final idsToDelete = List<int>.from(_selectedItemIds);
    _clearSelection(); // Clear selection and update formatting state immediately

    // Perform deletion for each selected ID
    for (final id in idsToDelete) {
      await dbService.deleteItem(id);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${idsToDelete.length} items deleted.')),
      );
    }
  }

  Future<void> _updateSelectedItems(bool isCompleted) async {
    final idsToUpdate = List<int>.from(_selectedItemIds);

    for (final id in idsToUpdate) {
      await dbService.updateItem(id, {'is_completed': isCompleted});
    }
    // Re-fetch or rely on the stream to update UI
  }

  // NEW: Update selected items with a styling property
  Future<void> _updateSelectedItemsStyle(Map<String, dynamic> styleUpdate) async {
    final idsToUpdate = List<int>.from(_selectedItemIds);
    if (idsToUpdate.isEmpty) return;

    // Perform bulk update on the database
    for (final id in idsToUpdate) {
      await dbService.updateItem(id, styleUpdate);
    }
  }

  // --- Reordering Logic (Requires 'sort_order' column in DB) ---
  void _onReorder(int oldIndex, int newIndex) async {
    // 1. Handle local reordering immediately for smooth UX
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });

    // 2. Prepare the bulk update for Supabase
    final List<Map<String, dynamic>> updates = [];
    for (int i = 0; i < _items.length; i++) {
      updates.add({
        'id': _items[i]['id'],
        'sort_order': i, // Use the current list index as the new sort_order
      });
    }

    // 3. Send bulk updates to Supabase
    try {
      await dbService.bulkUpdateItemSortOrder(updates);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save new order: $e')),
        );
      }
    }
  }

  // Helper function to convert Hex String to Color
  Color _hexToColor(String? hex) {
    // Get the theme's default text color (handles dark/light mode)
    final defaultColor = Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;

    if (hex == null || hex.isEmpty) {
      return defaultColor; // Use theme default if no color is set
    }

    hex = hex.replaceFirst('#', '');
    // Ensure it has 6 or 8 digits, prepend FF if only 6 are present
    if (hex.length == 6) {
      hex = 'FF$hex';
    } else if (hex.length != 8) {
      return defaultColor; // Use theme default if hex is invalid
    }
    try {
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return defaultColor;
    }
  }

  // --- List Name Update Methods (New) ---

  Future<void> _updateListName(String newName) async {
    final trimmedName = newName.trim();
    // Check if the name has changed and is not empty
    if (trimmedName.isEmpty || trimmedName == _localListName) return;

    try {
      // Database call to update the list name
      await dbService.updateListName(int.parse(widget.listId), trimmedName);

      // Update the local state
      setState(() {
        _localListName = trimmedName;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('List name updated successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update list name: ${e.toString()}')),
        );
      }
    }
  }

  // Dialog to handle name editing
  void _showEditTitleDialog() {
    final titleController = TextEditingController(text: _localListName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit List Name'),
          content: TextField(
            controller: titleController,
            decoration: const InputDecoration(hintText: "Enter new list name"),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _updateListName(titleController.text); // Call the update function
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // --- Members Dialog & Sharing ---

  // Dialog to prompt for email and call addListMember
  void _showShareDialog() {
    final shareController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Share "${_localListName}"'),
          content: TextField(
            controller: shareController,
            decoration: const InputDecoration(
              hintText: "Enter user's email address",
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _addMember(shareController.text);
              },
              child: const Text('Share'),
            ),
          ],
        );
      },
    );
  }

  // Dialog to view, add, and remove members - uses authoritative owner id if available
  void _showMembersDialog() {
    final String listOwnerId = _authoritativeOwnerId.isNotEmpty ? _authoritativeOwnerId : widget.ownerId;
    final currentUserId = dbService.currentUser?.id;
    final bool isCurrentUserOwner = _isCurrentUserOwner || _idsEqual(currentUserId, listOwnerId);

    // Use a unique key to force the FutureBuilder to rebuild every time the dialog is shown
    final dialogKey = UniqueKey();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          key: dialogKey,
          title: const Text('List Members'),
          content: SizedBox(
            width: double.maxFinite,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              // The function should return a List<Map<String, dynamic>> where each Map is a user's profile
              future: dbService.getListMembersWithProfiles(int.parse(widget.listId)),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                // snapshot.data is a List of PROFILES (id, username)
                final profiles = snapshot.data ?? [];
                final currentUserId = dbService.currentUser?.id;

                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final memberProfile = profiles[index];

                    // Safely access username from the profiles table structure
                    final memberUserId = memberProfile['id']?.toString() ?? '';
                    final username = memberProfile['username'] as String? ?? 'Unknown User';

                    // Determine role by comparing the member's ID with the list's ownerId
                    final isOwner = _idsEqual(memberUserId, listOwnerId);
                    final isSelf = _idsEqual(memberUserId, currentUserId);

                    return ListTile(
                      title: Text(username + (isSelf ? ' (You)' : '')),
                      // Display the role based on the new logic
                      subtitle: Text(isOwner ? 'Owner' : 'Member'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Owner Transfer Button (Only visible if current user is owner and the target is not the owner)
                          if (isCurrentUserOwner && !isOwner)
                            IconButton(
                              icon: const Icon(Icons.star_border, color: Colors.amber),
                              onPressed: () => _showOwnerTransferConfirmation(memberUserId, username),
                              tooltip: 'Make Owner',
                            ),

                          // Remove Member/Leave List Button
                          // Owner can remove others OR non-owner can remove themselves
                          if ((isCurrentUserOwner && !isOwner) || (isSelf && !isOwner))
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                              onPressed: () => _removeMember(memberUserId, username),
                              tooltip: isSelf ? 'Leave List' : 'Remove Member',
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            // Only show 'Add Member' button if the current user is the owner
            if (isCurrentUserOwner)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); // Close members dialog
                  _showAddMemberDialog(); // Open add member dialog
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Member'),
              ),
          ],
        );
      },
    ); // Removed the .then((_) => setState({})); since the unique key will force a rebuild when the dialog opens.
  }

  // Helper dialog for adding a member
  void _showAddMemberDialog() {
    final shareController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add Member to "${_localListName}"'),
          content: TextField(
            controller: shareController,
            decoration: const InputDecoration(
              hintText: "Enter user's email address",
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                // Close the add dialog
                Navigator.pop(context);
                // Call add member
                await _addMember(shareController.text);
                // Re-open the members dialog to show the updated list
                _showMembersDialog();
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addMember(String email) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) return;

    try {
      await dbService.addListMember(int.parse(widget.listId), trimmedEmail);
      // No need to call setState here as the dialog will be manually reopened after this Future completes
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Member added: $trimmedEmail')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add member: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _removeMember(String userId, String username) async {
    try {
      await dbService.removeListMember(int.parse(widget.listId), userId);

      if (mounted) {
        // Only try to re-open the members dialog if the current user didn't remove themselves
        if (userId != dbService.currentUser?.id) {
          // Close the current dialog instance
          Navigator.pop(context);
          // Re-open the members dialog to show the updated list
          _showMembersDialog();
        } else {
          // If the user removed themselves, the list stream listener will handle navigation back
          // No need to explicitly close the dialog here, as navigation will handle it.
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$username removed from list.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove member: ${e.toString()}')),
        );
      }
    }
  }

  void _showOwnerTransferConfirmation(String userId, String username) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Transfer Ownership'),
          content: Text.rich(
            TextSpan(
              text: 'Are you sure you want to make ',
              children: [
                TextSpan(
                  text: username,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' the new list owner? This action is '),
                const TextSpan(
                  text: 'not reversible',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
                const TextSpan(text: ' and you will be demoted to a regular member.'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(context); // Close confirmation dialog
                await _transferOwnership(userId, username);
                // Re-open the members dialog to show the updated owner status
                _showMembersDialog();
              },
              child: const Text('Transfer Ownership', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _transferOwnership(String userId, String username) async {
    try {
      await dbService.transferOwnership(int.parse(widget.listId), userId);
      // The list stream listener in the home screen will handle the change of ownership
      // and might trigger a refresh or redraw of this screen if the list is still valid for the current user.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ownership transferred to $username!')),
        );
        // Important: Refresh authoritative owner/role state
        await _initOwnershipAndName();
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to transfer ownership: ${e.toString()}')),
        );
      }
    }
  }

  // --- UI Builders ---

  AppBar _buildSelectionAppBar() {
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
            final allCompleted = _selectedItemIds.every(
                (id) => _items.firstWhere((item) => item['id'] == id)['is_completed'] == true);
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

  Widget _buildNormalAppBar() {
    return AppBar(
      title: GestureDetector(
        onTap: _isCurrentUserOwner ? _showEditTitleDialog : null, // Only allow owner to edit
        child: Text(
          _localListName, // <--- Using local name
          style: TextStyle(
            // Optional: change style to indicate editable/non-editable
            decoration: _isCurrentUserOwner ? TextDecoration.underline : null,
            decorationStyle: TextDecorationStyle.dashed,
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.brush),
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const DrawingScreen()));
          },
        ),
        IconButton(
          icon: const Icon(Icons.people),
          onPressed: _showMembersDialog,
        ),
        IconButton(
          icon: const Icon(Icons.share),
          onPressed: _showShareDialog,
        ),
      ],
    );
  }

  // Renders the bottom bar for formatting when in normal mode (SIMPLIFIED)
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
          // Disable Checkboxes Button (Checkbox with slash icon)
          IconButton(
            icon: const Icon(Icons.disabled_by_default_outlined),
            onPressed: () {
              // TODO: Implement logic to toggle checkbox visibility/functionality
            },
            tooltip: 'Hide Checkboxes',
          ),
          const Spacer(), // Pushes buttons to the left
        ],
      ),
    );
  }

  // Renders the bottom bar for bulk actions OR single item formatting
  Widget _buildSelectionBottomBar() {
    final isSingleItemSelected = _selectedItemIds.length == 1;

    // Group bulk actions and single-item formatting
    final actions = isSingleItemSelected
        ? <Widget>[
            // 1. BOLD TOGGLE
            IconButton(
              icon: Icon(Icons.format_bold,
                  color: _isBoldSelected ? Theme.of(context).colorScheme.primary : Colors.grey),
              onPressed: () async {
                final newState = !_isBoldSelected;
                await _updateSelectedItemsStyle({'is_bold': newState});
                _updateFormattingBarState(); // Refresh UI state
              },
              tooltip: 'Bold',
            ),
            // 2. ITALIC TOGGLE
            IconButton(
              icon: Icon(Icons.format_italic,
                  color: _isItalicSelected ? Theme.of(context).colorScheme.primary : Colors.grey),
              onPressed: () async {
                final newState = !_isItalicSelected;
                await _updateSelectedItemsStyle({'is_italic': newState});
                _updateFormattingBarState(); // Refresh UI state
              },
              tooltip: 'Italicize',
            ),
            // 3. COLOR PICKER (Placeholder Toggling between Black and Red)
            IconButton(
              icon: const Icon(Icons.color_lens),
              onPressed: () async {
                final currentItem = _items.firstWhere((item) => item['id'] == _selectedItemIds.first);
                final currentColorHex = currentItem['text_color'] as String? ?? '000000';
                // Toggle color between '000000' (black) and 'FF0000' (red) for demo
                final newColorHex = currentColorHex.toUpperCase() == '000000' ? 'FF0000' : '000000';
                await _updateSelectedItemsStyle({'text_color': newColorHex});
                // The stream will handle the UI refresh.
              },
              tooltip: 'Change Font Color/Highlight (Demo)',
            ),
          ]
        : <Widget>[
            // Bulk actions when multiple items are selected
            IconButton(
              icon: const Icon(Icons.check_box),
              onPressed: () => _updateSelectedItems(true),
              tooltip: 'Check All Selected',
            ),
            IconButton(
              icon: const Icon(Icons.check_box_outline_blank),
              onPressed: () => _updateSelectedItems(false),
              tooltip: 'Uncheck All Selected',
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteSelectedItems,
              tooltip: 'Delete Selected Items',
            ),
          ];

    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          ...actions,
          // Always include the clear selection button
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
      // FIX: AppBar return types are now explicitly AppBar, resolving the previous error.
      appBar: (isSelecting ? _buildSelectionAppBar() : _buildNormalAppBar()) as PreferredSizeWidget,

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
                      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                      itemCount: _items.length,
                      onReorder: _onReorder,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final itemId = item['id'] as int;
                        final isCompleted = item['is_completed'] as bool? ?? false;
                        final isSelected = _selectedItemIds.contains(itemId);

                        // NEW: Read styling properties
                        final isBold = item['is_bold'] as bool? ?? false;
                        final isItalic = item['is_italic'] as bool? ?? false;
                        // Default color to theme if 'text_color' is missing or null
                        final colorHex = item['text_color'] as String?;
                        final itemColor = _hexToColor(colorHex);

                        // Wrap each item in a LongPress and Tap Detector
                        return GestureDetector(
                          key: ValueKey(itemId), // Required for ReorderableListView
                          onLongPress: () => _toggleSelection(itemId),
                          onTap: isSelecting ? () => _toggleSelection(itemId) : null, // Only toggle selection if mode is active

                          child: Container(
                            color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                              child: Row(
                                children: [
                                  // LEFT SIDE: Selection/Checkbox Toggling Zone
                                  GestureDetector(
                                    onTap: isSelecting
                                        ? () => _toggleSelection(itemId) // If selecting, tap toggles selection
                                        : () async {
                                            // Otherwise, tap toggles completion
                                            await dbService.updateItem(itemId, {'is_completed': !isCompleted});
                                          },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      child: isSelecting
                                          ? Icon(
                                              // Show selection indicator
                                              isSelected ? Icons.check_circle : Icons.circle_outlined,
                                              color: Theme.of(context).colorScheme.primary,
                                            )
                                          : Icon(
                                              // Show completion checkbox
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
                                        color: isCompleted ? itemColor.withOpacity(0.6) : itemColor,
                                        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                                        fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
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
                                          await dbService.updateItem(itemId, {'title': trimmedTitle});
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


//yk this goes to show how much I like you and how much I want to do fun stuff with you
//haha lol you probably wont be reading this though
