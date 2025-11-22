import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

// --- Placeholder for complex features ---
// We will define these later as they require new models and state management
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
  
  // State for the bottom options bar (just an example for font size)
  double _currentFontSize = 16.0;

  @override
  void dispose() {
    _addItemController.dispose();
    _addItemFocusNode.dispose();
    super.dispose();
  }

  // Helper function to add a new item and focus the input
  void _addNewItem(String title) async {
    if (title.trim().isEmpty) return;
    
    // We assume the service has an addItem function that takes listId and title
    await dbService.addItem(int.parse(widget.listId), title.trim());
    
    _addItemController.clear();
    _addItemFocusNode.requestFocus(); // Keep focus for rapid entry
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.listName),
        actions: [
          // Placeholder for the Drawing Tool Button
          IconButton(
            icon: const Icon(Icons.brush),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DrawingScreen()));
            },
          ),
          // Placeholder for Sharing/Membership
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              // TODO: Implement sharing/membership management
            },
          ),
        ],
      ),
      
      body: Column(
        children: [
          // 1. The main list of items (StreamBuilder)
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              // Assuming SupabaseService has a getItemsStream function
              stream: dbService.getItemsStream(int.parse(widget.listId)),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data!;

                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final itemId = item['id'] as int;
                    final isCompleted = item['is_completed'] as bool;
                    
                    // The core item structure with split interaction zones
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          // LEFT SIDE: Checkbox Toggling Zone
                          GestureDetector(
                            onTap: () async {
                              await dbService.updateItem(
                                itemId, 
                                {'is_completed': !isCompleted},
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Icon(
                                isCompleted ? Icons.check_box : Icons.check_box_outline_blank,
                                color: isCompleted ? Theme.of(context).colorScheme.primary : Colors.grey,
                              ),
                            ),
                          ),

                          // RIGHT SIDE: Editable Text Field Zone
                          Expanded(
                            child: TextFormField(
                              initialValue: item['title'] as String,
                              keyboardType: TextInputType.text, // For regular text
                              style: TextStyle(
                                fontSize: _currentFontSize, // Dynamic Font Size
                                decoration: isCompleted ? TextDecoration.lineThrough : null,
                                color: isCompleted ? Colors.grey : Colors.black,
                                // TODO: Apply other dynamic styles (bold, italic, font color) here
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                              // On submit (e.g., when focus leaves or "Done" is pressed)
                              onFieldSubmitted: (newTitle) async {
                                await dbService.updateItem(
                                  itemId, 
                                  {'title': newTitle},
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          // 2. Add New Item Input Field
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
              // Use the keyboard's "New Line" button to create a new item
              onSubmitted: (value) {
                _addNewItem(value);
              },
            ),
          ),
        ],
      ),
      
      // 3. Bottom Options Bar for Styling/Tools
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            // Font Size Increase Button
            IconButton(
              icon: const Icon(Icons.format_size),
              onPressed: () {
                setState(() {
                  _currentFontSize = _currentFontSize == 16.0 ? 20.0 : 16.0; // Toggle example
                  // TODO: More complex implementation with a slider/dialog
                });
              },
              tooltip: 'Increase Font Size',
            ),
            // Bold Button
            IconButton(
              icon: const Icon(Icons.format_bold),
              onPressed: () {
                // TODO: Implement bold style update
              },
              tooltip: 'Bold',
            ),
            // Italic Button
            IconButton(
              icon: const Icon(Icons.format_italic),
              onPressed: () {
                // TODO: Implement italic style update
              },
              tooltip: 'Italicize',
            ),
            // Color Picker/Palette Button
            IconButton(
              icon: const Icon(Icons.color_lens),
              onPressed: () {
                // TODO: Implement color picker dialog (Hex input, presets)
              },
              tooltip: 'Change Font Color/Highlight',
            ),
            // Disable Checkboxes Button
            IconButton(
              icon: const Icon(Icons.check_box_outline_blank),
              onPressed: () {
                // TODO: Implement logic to toggle checkbox visibility/functionality
              },
              tooltip: 'Toggle Checkboxes',
            ),
          ],
        ),
      ),
    );
  }
}