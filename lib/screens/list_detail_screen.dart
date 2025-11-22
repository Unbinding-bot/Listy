// lib/screens/list_detail_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class ListDetailScreen extends StatefulWidget {
  final String listId;
  final String listName;
  const ListDetailScreen({super.key, required this.listId, required this.listName});

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  final _dbService = SupabaseService();
  late TextEditingController _titleController;
  final TextEditingController _newItemController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.listName);
  }

  @override
  void dispose() {
    // Update title when leaving the screen
    if (_titleController.text != widget.listName) {
      _dbService.updateListTitle(widget.listId, _titleController.text);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(icon: const Icon(Icons.person_add), onPressed: () {
            // Show Share Dialog logic here
          })
        ],
      ),
      body: Column(
        children: [
          // 1. Title Area (Editable)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: "Title",
              ),
              onSubmitted: (val) => _dbService.updateListTitle(widget.listId, val),
            ),
          ),
          
          // 2. List Items Area
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _dbService.getListItems(widget.listId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                final tasks = snapshot.data!;

                return ListView.builder(
                  itemCount: tasks.length + 1, // +1 for the "Add Item" row
                  itemBuilder: (context, index) {
                    // The last item is the "Add new" input row
                    if (index == tasks.length) {
                      return ListTile(
                        leading: const Icon(Icons.add),
                        title: TextField(
                          controller: _newItemController,
                          decoration: const InputDecoration(
                            hintText: "List item",
                            border: InputBorder.none,
                          ),
                          onSubmitted: (val) {
                            if (val.isNotEmpty) {
                              _dbService.addTask(widget.listId, val);
                              _newItemController.clear();
                            }
                          },
                        ),
                      );
                    }

                    // Actual Tasks
                    final task = tasks[index];
                    return CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      value: task['is_completed'],
                      title: Text(
                        task['title'],
                        style: TextStyle(
                          decoration: task['is_completed'] ? TextDecoration.lineThrough : null,
                          color: task['is_completed'] ? Colors.grey : Colors.black,
                        ),
                      ),
                      onChanged: (val) {
                        _dbService.toggleTask(task['id'].toString(), task['is_completed']);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}