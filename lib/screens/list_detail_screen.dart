
```dart name=lib/screens/list_detail_screen.dart url=https://github.com/Unbinding-bot/Listy/blob/main/lib/screens/list_detail_screen.dart
// lib/screens/list_detail_screen.dart
// Fixes applied:
// - Single input box (moved into bottom bar) — removed duplicate input in body
// - Restored size/font controls and formatting buttons (font family & color quick menu)
// - Preserves animated incremental sync behavior for members & items (from prior merge)
// - Ensures bottom bars (normal vs selection) show the expected controls

import 'dart:async';
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
  final String ownerId;

  const ListDetailScreen({
    super.key,
    required this.listId,
    required this.listName,
    required this.ownerId,
  });

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> with TickerProviderStateMixin {
  final dbService = SupabaseService();
  final TextEditingController _addItemController = TextEditingController();
  final FocusNode _addItemFocusNode = FocusNode();

  List<Map<String, dynamic>> _items = [];
  final List<int> _selectedItemIds = [];
  bool get isSelecting => _selectedItemIds.isNotEmpty;

  double _currentFontSize = 16.0;
  bool _isBoldSelected = false;
  bool _isItalicSelected = false;
  String _selectedFontFamily = 'Default';
  Color _selectedFontColor = Colors.black;

  late String _localListName;
  String _currentUserId = '';
  bool _isCurrentUserOwner = false;

  final GlobalKey<AnimatedListState> _membersListKey = GlobalKey<AnimatedListState>();
  List<Map<String, dynamic>> _members = [];
  bool _membersLoaded = false;
  Timer? _refreshTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _itemsSub;

  bool _idsEqual(dynamic a, dynamic b) => a != null && b != null && a.toString() == b.toString();

  @override
  void initState() {
    super.initState();
    _localListName = widget.listName;
    _currentUserId = dbService.currentUser?.id ?? '';
    _isCurrentUserOwner = _idsEqual(widget.ownerId, _currentUserId);

    // items realtime
    _itemsSub = dbService.getItemsStream(int.parse(widget.listId)).listen((data) {
      _applyItemDiffs(data);
    });

    _initOwnershipAndName();

    // members polling (keeps lightweight)
    _refreshMembers();
    _refreshRole();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshMembers();
      _refreshRole();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _itemsSub?.cancel();
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
        _localListName = listRow?['name'] ?? widget.listName;
        _currentUserId = dbService.currentUser?.id ?? '';
        _isCurrentUserOwner = (role == 'owner') || _idsEqual(widget.ownerId, _currentUserId);
      });

      if (_isCurrentUserOwner &&
          (_localListName.trim().isEmpty || _localListName.toLowerCase().contains('untitled'))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showEditTitleDialog();
        });
      }
    } catch (_) {}
  }

  // Minimal diffs for items
  void _applyItemDiffs(List<Map<String, dynamic>> newSnapshot) {
    if (!mounted) return;
    final oldById = {for (var it in _items) it['id']: it};
    final newById = {for (var it in newSnapshot) it['id']: it};

    final removedIds = oldById.keys.where((id) => !newById.containsKey(id)).toList();
    final addedIds = newSnapshot.map((e) => e['id']).where((id) => !oldById.containsKey(id)).toList();
    final updatedIds = newById.keys.where((id) {
      if (!oldById.containsKey(id)) return false;
      final old = oldById[id]!;
      final neu = newById[id]!;
      return old['title'] != neu['title'] ||
          (old['is_completed'] ?? false) != (neu['is_completed'] ?? false) ||
          (old['is_bold'] ?? false) != (neu['is_bold'] ?? false) ||
          (old['is_italic'] ?? false) != (neu['is_italic'] ?? false) ||
          (old['text_color'] ?? '') != (neu['text_color'] ?? '') ||
          (old['sort_order'] ?? 0) != (neu['sort_order'] ?? 0);
    }).toList();

    if (removedIds.isEmpty && addedIds.isEmpty && updatedIds.isEmpty) return;

    setState(() {
      if (removedIds.isNotEmpty) _items.removeWhere((it) => removedIds.contains(it['id']));
      for (final id in updatedIds) {
        final idx = _items.indexWhere((it) => it['id'] == id);
        if (idx != -1) _items[idx] = newById[id]!;
      }
      for (final newItem in newSnapshot) {
        final id = newItem['id'];
        if (!oldById.containsKey(id)) {
          final idxInNew = newSnapshot.indexWhere((e) => e['id'] == id);
          int insertIndex = _items.length;
          for (int j = idxInNew + 1; j < newSnapshot.length; j++) {
            final nextId = newSnapshot[j]['id'];
            final existingIndex = _items.indexWhere((it) => it['id'] == nextId);
            if (existingIndex != -1) {
              insertIndex = existingIndex;
              break;
            }
          }
          _items.insert(insertIndex, newItem);
        }
      }
      _items.sort((a, b) {
        final ia = newSnapshot.indexWhere((e) => e['id'] == a['id']);
        final ib = newSnapshot.indexWhere((e) => e['id'] == b['id']);
        return ia.compareTo(ib);
      });
    });
  }

  Future<void> _refreshMembers() async {
    try {
      final newMembers = await dbService.getListMembersWithProfilesAndRoles(int.parse(widget.listId));
      if (!mounted) return;

      final oldIds = _members.map((m) => m['id']?.toString()).toList();
      final newIds = newMembers.map((m) => m['id']?.toString()).toList();

      final removedIds = oldIds.where((id) => id != null && !newIds.contains(id)).toList().cast<String>();
      for (final rid in removedIds) {
        final idx = _members.indexWhere((m) => _idsEqual(m['id'], rid));
        if (idx != -1) {
          final removed = _members.removeAt(idx);
          _membersListKey.currentState?.removeItem(idx, (ctx, anim) => _buildMemberTileAnimated(removed, anim, removing: true), duration: const Duration(milliseconds: 300));
        }
      }

      for (final nm in newMembers) {
        final id = nm['id']?.toString();
        if (id == null) continue;
        final idx = _members.indexWhere((m) => _idsEqual(m['id'], id));
        if (idx != -1) {
          final old = _members[idx];
          if (old['username'] != nm['username'] || old['role'] != nm['role'] || old['email'] != nm['email']) {
            _members[idx] = nm;
            setState(() {});
          }
        }
      }

      for (int i = 0; i < newMembers.length; i++) {
        final nm = newMembers[i];
        final id = nm['id']?.toString();
        if (id == null) continue;
        if (!_members.any((m) => _idsEqual(m['id'], id))) {
          final insertIndex = _determineInsertIndexForMember(newMembers, id);
          _members.insert(insertIndex, nm);
          _membersListKey.currentState?.insertItem(insertIndex, duration: const Duration(milliseconds: 300));
        }
      }

      if (!_membersLoaded) setState(() => _membersLoaded = true);
      else setState(() {});
    } catch (_) {}
  }

  int _determineInsertIndexForMember(List<Map<String, dynamic>> authoritativeList, String memberId) {
    final idxInAuth = authoritativeList.indexWhere((m) => _idsEqual(m['id'], memberId));
    if (idxInAuth == -1) return _members.length;
    for (int i = idxInAuth + 1; i < authoritativeList.length; i++) {
      final nextId = authoritativeList[i]['id']?.toString();
      final existingIndex = _members.indexWhere((m) => _idsEqual(m['id'], nextId));
      if (existingIndex != -1) return existingIndex;
    }
    return _members.length;
  }

  Future<void> _refreshRole() async {
    try {
      final role = await dbService.getCurrentUserRole(int.parse(widget.listId));
      if (!mounted) return;
      setState(() {
        _currentUserId = dbService.currentUser?.id ?? '';
        _isCurrentUserOwner = (role == 'owner') || _idsEqual(widget.ownerId, _currentUserId);
      });
    } catch (_) {}
  }

  // --- Selection helpers ---
  void _updateFormattingBarState() {
    if (_selectedItemIds.isEmpty) {
      setState(() {
        _isBoldSelected = false;
        _isItalicSelected = false;
      });
      return;
    }
    final selectedItems = _items.where((item) => _selectedItemIds.contains(item['id'])).toList();
    if (selectedItems.isEmpty) return;
    final allBold = selectedItems.every((item) => item['is_bold'] == true);
    final allItalic = selectedItems.every((item) => item['is_italic'] == true);
    setState(() {
      _isBoldSelected = allBold;
      _isItalicSelected = allItalic;
    });
  }

  void _toggleSelection(int itemId) {
    setState(() {
      if (_selectedItemIds.contains(itemId)) _selectedItemIds.remove(itemId);
      else _selectedItemIds.add(itemId);
      _updateFormattingBarState();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedItemIds.clear();
      _updateFormattingBarState();
    });
  }

  // --- CRUD helpers ---
  Future<void> _addNewItem(String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    try {
      await dbService.addItem(int.parse(widget.listId), t);
      _addItemController.clear();
      _addItemFocusNode.requestFocus();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add item: $e')));
    }
  }

  Future<void> _deleteSelectedItems() async {
    final ids = List<int>.from(_selectedItemIds);
    _clearSelection();
    for (final id in ids) await dbService.deleteItem(id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${ids.length} items deleted.')));
  }

  Future<void> _updateSelectedItems(bool isCompleted) async {
    final ids = List<int>.from(_selectedItemIds);
    for (final id in ids) await dbService.updateItem(id, {'is_completed': isCompleted});
  }

  Future<void> _updateSelectedItemsStyle(Map<String, dynamic> styleUpdate) async {
    final ids = List<int>.from(_selectedItemIds);
    if (ids.isEmpty) return;
    for (final id in ids) await dbService.updateItem(id, styleUpdate);
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final it = _items.removeAt(oldIndex);
      _items.insert(newIndex, it);
    });
    final updates = <Map<String, dynamic>>[];
    for (int i = 0; i < _items.length; i++) updates.add({'id': _items[i]['id'], 'sort_order': i});
    try {
      await dbService.bulkUpdateItemSortOrder(updates);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save new order: $e')));
    }
  }

  // --- Members UI helpers ---
  Widget _buildMemberTileAnimated(Map<String, dynamic> member, Animation<double> animation, {bool removing = false}) {
    final username = member['username'] as String? ?? 'Unknown';
    final role = member['role'] as String? ?? 'member';
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: 0.0,
      child: FadeTransition(
        opacity: animation,
        child: ListTile(title: Text(username), subtitle: Text(role == 'owner' ? 'Owner' : 'Member')),
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final id = member['id']?.toString() ?? '';
    final username = member['username'] as String? ?? 'Unknown';
    final role = member['role'] as String? ?? 'member';
    final isSelf = _idsEqual(id, dbService.currentUser?.id);
    final isOwner = role == 'owner';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: ListTile(
        key: ValueKey(id + (member['role'] ?? '') + (member['username'] ?? '')),
        title: Text(username + (isSelf ? ' (You)' : '')),
        subtitle: Text(isOwner ? 'Owner' : 'Member'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isCurrentUserOwner && !isOwner)
              IconButton(icon: const Icon(Icons.star_border, color: Colors.amber), onPressed: () => _showOwnerTransferConfirmation(id, username)),
            if ((_isCurrentUserOwner && !isOwner) || (isSelf && !isOwner))
              IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => _removeMember(id, username)),
          ],
        ),
      ),
    );
  }

  Future<void> _addMember(String email) async {
    final t = email.trim();
    if (t.isEmpty) return;
    try {
      await dbService.addListMember(int.parse(widget.listId), t);
      await _refreshMembers();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Member added: $t')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add member: $e')));
    }
  }

  Future<void> _removeMember(String userId, String username) async {
    try {
      await dbService.removeListMember(int.parse(widget.listId), userId);
      await _refreshMembers();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$username removed from list.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to remove member: $e')));
    }
  }

  void _showOwnerTransferConfirmation(String userId, String username) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Ownership'),
        content: Text.rich(TextSpan(
          text: 'Are you sure you want to make ',
          children: [TextSpan(text: username, style: const TextStyle(fontWeight: FontWeight.bold)), const TextSpan(text: ' the new list owner? This action is '), const TextSpan(text: 'not reversible', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)), const TextSpan(text: ' and you will be demoted to a regular member.')],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () async { Navigator.pop(context); await _transferOwnership(userId, username); }, child: const Text('Transfer Ownership', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Future<void> _transferOwnership(String userId, String username) async {
    try {
      await dbService.transferOwnership(int.parse(widget.listId), userId);
      await _refreshMembers();
      await _refreshRole();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ownership transferred to $username!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to transfer ownership: $e')));
    }
  }

  // --- AppBars / bottom bars ---
  AppBar _buildSelectionAppBar() {
    return AppBar(
      title: Text('${_selectedItemIds.length} Items Selected'),
      leading: IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection),
      actions: [
        IconButton(icon: const Icon(Icons.select_all), tooltip: 'Check All / Uncheck All', onPressed: () {
          final allCompleted = _selectedItemIds.every((id) => _items.firstWhere((item) => item['id'] == id)['is_completed'] == true);
          _updateSelectedItems(!allCompleted);
        }),
        IconButton(icon: const Icon(Icons.delete), tooltip: 'Delete Selected', onPressed: _deleteSelectedItems),
      ],
    );
  }

  Widget _buildNormalAppBar() {
    return AppBar(
      title: GestureDetector(onTap: _isCurrentUserOwner ? _showEditTitleDialog : null, child: Text(_localListName, style: TextStyle(decoration: _isCurrentUserOwner ? TextDecoration.underline : null, decorationStyle: TextDecorationStyle.dashed))),
      actions: [
        IconButton(icon: const Icon(Icons.brush), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DrawingScreen()))),
        IconButton(icon: const Icon(Icons.people), onPressed: _showMembersDialog),
        IconButton(icon: const Icon(Icons.share), onPressed: _showShareDialog),
      ],
    );
  }

  // Normal bottom bar now contains the single input + size/font controls
  Widget _buildNormalBottomBar() {
    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(children: [
          // Font family selector
          PopupMenuButton<String>(
            tooltip: 'Font Family',
            initialValue: _selectedFontFamily,
            onSelected: (v) => setState(() => _selectedFontFamily = v),
            itemBuilder: (ctx) => ['Default', 'Serif', 'Monospace', 'Sans'].map((f) => PopupMenuItem(value: f, child: Text(f))).toList(),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: Icon(Icons.font_download)),
          ),

          // Font size toggle
          IconButton(
            icon: const Icon(Icons.format_size),
            onPressed: () => setState(() => _currentFontSize = _currentFontSize == 16.0 ? 20.0 : 16.0),
            tooltip: 'Toggle Font Size',
          ),

          // Color quick menu
          PopupMenuButton<Color>(
            tooltip: 'Font Color',
            onSelected: (c) => setState(() => _selectedFontColor = c),
            itemBuilder: (ctx) => [
              PopupMenuItem(value: Colors.black, child: Row(children: [const Icon(Icons.circle, color: Colors.black), const SizedBox(width: 8), const Text('Black')])),
              PopupMenuItem(value: Colors.red, child: Row(children: [const Icon(Icons.circle, color: Colors.red), const SizedBox(width: 8), const Text('Red')])),
              PopupMenuItem(value: Colors.blue, child: Row(children: [const Icon(Icons.circle, color: Colors.blue), const SizedBox(width: 8), const Text('Blue')])),
            ],
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: Icon(Icons.color_lens, color: _selectedFontColor)),
          ),

          // Expanded input for new item (single source of truth)
          Expanded(
            child: TextField(
              controller: _addItemController,
              focusNode: _addItemFocusNode,
              decoration: InputDecoration(
                hintText: "New item...",
                suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: () => _addNewItem(_addItemController.text)),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) => _addNewItem(v),
            ),
          ),

          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ]),
      ),
    );
  }

  // Selection bottom bar (formatting + bulk actions)
  Widget _buildSelectionBottomBar() {
    final isSingle = _selectedItemIds.length == 1;
    final actions = isSingle
        ? <Widget>[
            IconButton(icon: Icon(Icons.format_bold, color: _isBoldSelected ? Theme.of(context).colorScheme.primary : Colors.grey), onPressed: () async {
              final newState = !_isBoldSelected;
              await _updateSelectedItemsStyle({'is_bold': newState});
              _updateFormattingBarState();
            }),
            IconButton(icon: Icon(Icons.format_italic, color: _isItalicSelected ? Theme.of(context).colorScheme.primary : Colors.grey), onPressed: () async {
              final newState = !_isItalicSelected;
              await _updateSelectedItemsStyle({'is_italic': newState});
              _updateFormattingBarState();
            }),
            PopupMenuButton<String>(
              icon: const Icon(Icons.font_download),
              onSelected: (f) async {
                await _updateSelectedItemsStyle({'font_family': f});
              },
              itemBuilder: (ctx) => ['Default', 'Serif', 'Monospace', 'Sans'].map((f) => PopupMenuItem(value: f, child: Text(f))).toList(),
            ),
            PopupMenuButton<Color>(
              icon: const Icon(Icons.color_lens),
              onSelected: (c) async {
                final hex = c.value.toRadixString(16).padLeft(8, '0').substring(2); // 'RRGGBB'
                await _updateSelectedItemsStyle({'text_color': hex});
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(value: Colors.black, child: Row(children: [const Icon(Icons.circle, color: Colors.black), const SizedBox(width: 8), const Text('Black')])),
                PopupMenuItem(value: Colors.red, child: Row(children: [const Icon(Icons.circle, color: Colors.red), const SizedBox(width: 8), const Text('Red')])),
                PopupMenuItem(value: Colors.blue, child: Row(children: [const Icon(Icons.circle, color: Colors.blue), const SizedBox(width: 8), const Text('Blue')])),
              ],
            ),
          ]
        : <Widget>[
            IconButton(icon: const Icon(Icons.check_box), onPressed: () => _updateSelectedItems(true)),
            IconButton(icon: const Icon(Icons.check_box_outline_blank), onPressed: () => _updateSelectedItems(false)),
            IconButton(icon: const Icon(Icons.delete), onPressed: _deleteSelectedItems),
          ];

    return BottomAppBar(
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        ...actions,
        IconButton(icon: const Icon(Icons.cancel), onPressed: _clearSelection),
      ]),
    );
  }

  // Item row with AnimatedSwitcher for subtle updates
  Widget _buildItemRow(Map<String, dynamic> item) {
    final itemId = item['id'] as int;
    final isCompleted = item['is_completed'] as bool? ?? false;
    final isBold = item['is_bold'] as bool? ?? false;
    final isItalic = item['is_italic'] as bool? ?? false;
    final colorHex = item['text_color'] as String?;
    final itemColor = _hexToColor(colorHex);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: SizeTransition(sizeFactor: anim, axisAlignment: 0.0, child: child)),
      child: Container(
        key: ValueKey('item-${itemId}-${item['title']}-${item['is_completed']}'),
        color: _selectedItemIds.contains(itemId) ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          child: Row(children: [
            GestureDetector(
              onTap: _selectedItemIds.isNotEmpty ? () => _toggleSelection(itemId) : () async => await dbService.updateItem(itemId, {'is_completed': !isCompleted}),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Icon(isCompleted ? Icons.check_box : Icons.check_box_outline_blank, color: isCompleted ? Theme.of(context).colorScheme.primary : Colors.grey)),
            ),
            Expanded(
              child: TextFormField(
                initialValue: item['title'] as String,
                enabled: _selectedItemIds.isEmpty,
                keyboardType: TextInputType.text,
                style: TextStyle(fontSize: _currentFontSize, decoration: isCompleted ? TextDecoration.lineThrough : null, color: isCompleted ? itemColor.withOpacity(0.6) : itemColor, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontStyle: isItalic ? FontStyle.italic : FontStyle.normal, fontFamily: _selectedFontFamily == 'Default' ? null : _selectedFontFamily),
                decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero),
                onFieldSubmitted: (newTitle) async {
                  final trimmed = newTitle.trim();
                  if (trimmed.isEmpty) await dbService.deleteItem(itemId);
                  else await dbService.updateItem(itemId, {'title': trimmed});
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: (isSelecting ? _buildSelectionAppBar() : _buildNormalAppBar()) as PreferredSizeWidget,
      body: GestureDetector(
        onTap: isSelecting ? _clearSelection : null,
        child: Column(children: [
          Expanded(
            child: _items.isEmpty ? const Center(child: Text("Start by adding a new item below.")) : ReorderableListView.builder(
              padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
              itemCount: _items.length,
              onReorder: _onReorder,
              itemBuilder: (context, index) {
                final item = _items[index];
                final itemId = item['id'] as int;
                return GestureDetector(
                  key: ValueKey(itemId),
                  onLongPress: () => _toggleSelection(itemId),
                  onTap: isSelecting ? () => _toggleSelection(itemId) : null,
                  child: _buildItemRow(item),
                );
              },
            ),
          ),
        ]),
      ),
      bottomNavigationBar: isSelecting ? _buildSelectionBottomBar() : _buildNormalBottomBar(),
    );
  }

  Color _hexToColor(String? hex) {
    final defaultColor = Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;
    if (hex == null || hex.isEmpty) return defaultColor;
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return defaultColor;
    try {
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return defaultColor;
    }
  }
}

// yk this goes to show how much I like you and how much I want to do fun stuff with you
// haha lol you probably wont be reading this though