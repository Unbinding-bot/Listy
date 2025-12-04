// lib/screens/list_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
//
class SharedListsScreen extends StatelessWidget {
  const SharedListsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dbService = SupabaseService();

    return Scaffold(
      appBar: AppBar(title: const Text("Supabase Lists")),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: dbService.getMyLists(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final lists = snapshot.data!;

          if (lists.isEmpty) return const Center(child: Text("No lists yet"));

          return ListView.builder(
            itemCount: lists.length,
            itemBuilder: (context, index) {
              final list = lists[index];
              return ListTile(
                title: Text(list['name']),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ItemsScreen(listId: list['id'].toString()),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => dbService.createNewList("New Trip Plan"),
      ),
    );
  }
}

class ItemsScreen extends StatelessWidget {
  final String listId;
  const ItemsScreen({super.key, required this.listId});

  @override
  Widget build(BuildContext context) {
    final dbService = SupabaseService();

    return Scaffold(
      appBar: AppBar(title: const Text("Items")),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: dbService.getListItems(listId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox();
          final tasks = snapshot.data!;

          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return CheckboxListTile(
                title: Text(task['title']),
                value: task['is_completed'],
                onChanged: (val) {
                  dbService.toggleTask(task['id'].toString(), task['is_completed']);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add_task),
        onPressed: () => dbService.addTask(listId, "Buy Milk"),
      ),
    );
  }
}