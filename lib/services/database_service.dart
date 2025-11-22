// lib/services/database_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  // Helper to get current user ID
  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  // 1. CREATE A LIST
  Future<void> createNewList(String listName) async {
    if (currentUserId == null) return;

    await _db.collection('lists').add({
      'name': listName,
      'ownerId': currentUserId,
      'createdAt': FieldValue.serverTimestamp(),
      'members': [currentUserId], // Add self to members
    });
  }

  // 2. READ LISTS (Stream)
  Stream<QuerySnapshot> getMyLists() {
    if (currentUserId == null) return const Stream.empty();

    return _db
        .collection('lists')
        .where('members', arrayContains: currentUserId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // 3. ADD ITEM
  Future<void> addTask(String listId, String taskName) async {
    await _db.collection('lists').doc(listId).collection('items').add({
      'name': taskName,
      'completed': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // 4. TOGGLE ITEM
  Future<void> toggleTask(String listId, String itemId, bool currentVal) async {
    await _db
        .collection('lists')
        .doc(listId)
        .collection('items')
        .doc(itemId)
        .update({'completed': !currentVal});
  }
  
  // 5. READ ITEMS (Stream)
  Stream<QuerySnapshot> getListItems(String listId) {
    return _db
        .collection('lists')
        .doc(listId)
        .collection('items')
        .orderBy('createdAt')
        .snapshots();
  }
}