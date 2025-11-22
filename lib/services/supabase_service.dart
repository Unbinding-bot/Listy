// lib/services/supabase_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  // 1. CREATE A LIST
  // We insert the list, then immediately insert a row into 'list_members'
  Future<void> createNewList(String listName) async {
    if (currentUserId == null) return;

    // Step 1: Create List and get the new ID
    final listData = await _client
        .from('lists')
        .insert({'name': listName, 'owner_id': currentUserId})
        .select()
        .single();

    // Step 2: Add self as a member
    await _client.from('list_members').insert({
      'list_id': listData['id'],
      'user_id': currentUserId,
    });
  }

  // 2. SHARE A LIST
  // Adds another user's ID to the 'list_members' table
  Future<void> shareList(String listId, String newMemberId) async {
    await _client.from('list_members').insert({
      'list_id': listId,
      'user_id': newMemberId,
    });
  }

  // 3. READ LISTS (Real-time Stream)
  // We select lists where the ID exists in the 'list_members' table for this user
  Stream<List<Map<String, dynamic>>> getMyLists() {
    return _client
        .from('lists')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => data);
    // Note: RLS (Security Rules) on the server will filter this automatically
    // to only show lists we are members of.
  }

  // 3.5 LIST NAME
  Future<void> updateListTitle(String listId, String newTitle) async {
    await _client.from('lists').update({'name': newTitle}).eq('id', listId);
  }

  // 4. ADD ITEM
  Future<void> addTask(String listId, String taskName) async {
    await _client.from('items').insert({
      'list_id': listId,
      'title': taskName,
      'is_completed': false,
    });
  }

  // 5. TOGGLE ITEM
  Future<void> toggleTask(String itemId, bool currentStatus) async {
    await _client.from('items').update({
      'is_completed': !currentStatus
    }).eq('id', itemId);
  }

  // 6. READ ITEMS (Real-time Stream)
  Stream<List<Map<String, dynamic>>> getListItems(String listId) {
    return _client
        .from('items')
        .stream(primaryKey: ['id'])
        .eq('list_id', listId)
        .order('created_at')
        .map((data) => data);
  }
}