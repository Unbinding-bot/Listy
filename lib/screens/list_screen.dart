// lib/screens/list_screen.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart'; // Note the relative import

class SharedListsScreen extends StatelessWidget {
  const SharedListsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dbService = DatabaseService();

    return Scaffold(
      appBar: AppBar(title: const Text("My Shared Lists")),
      body: StreamBuilder(
        stream: dbService.getMyLists(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Error loading lists"));
          if (snapshot.connectionState == ConnectionState.waiting) {
             return const Center(child: CircularProgressIndicator());
          }
          
          var docs = snapshot.data!.docs;
          
          if (docs.isEmpty) return const Center(child: Text("No lists yet"));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data() as Map<String, dynamic>;
              String listId = docs[index].id;

              return ListTile(
                title: Text(data['name']),
                subtitle: Text("Shared with ${data['members'].length} people"),
                onTap: () {
                  Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (_) => ItemsScreen(listId: listId))
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
    final dbService = DatabaseService();

    return Scaffold(
      appBar: AppBar(title: const Text("Items")),
      body: StreamBuilder(
        stream: dbService.getListItems(listId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox();
          var tasks = snapshot.data!.docs;

          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              var task = tasks[index].data() as Map<String, dynamic>;
              
              return CheckboxListTile(
                title: Text(task['name']),
                value: task['completed'],
                onChanged: (val) {
                  dbService.toggleTask(listId, tasks[index].id, task['completed']);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add_task),
        onPressed: () => dbService.addTask(listId, "New Task"),
      ),
    );
  }
}