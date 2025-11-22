// lib/services/supabase_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  // 1. CREATE A LIST
  Future<Map<String, dynamic>> createNewList(String listName) async { // <-- Now returns Map
    if (currentUserId == null) throw Exception('User not logged in.');

    final result = await _client.rpc(
        'create_list_and_add_member',
        params: {'list_name': listName},
    );
  
    // The RPC returns a single JSON object.
    return result as Map<String, dynamic>; 
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

  //7 HAHAH 6 7 HHAH search userid by username
  Future<String?> findUserIdByUsername(String username) async {
    // Ensure the username is not null or empty before querying
    if (username.isEmpty) return null;

    try {
        final response = await _client
            .from('profiles')
            .select('id')
            .eq('username', username)
            .limit(1)
            .maybeSingle(); // Use maybeSingle to handle 0 or 1 result

        // If response is null (no user found) or the ID is missing, return null
        if (response == null || response['id'] == null) {
            return null;
        }
        return response['id'] as String;
    } catch (e) {
        // Log the error if necessary, but return null to indicate failure to find user
        print('Error finding user by username: $e');
        return null;
    }
  }
  Future<void> deleteList(int listId) async {
    // RLS (Row Level Security) will ensure only the owner can delete this.
    await _client
        .from('lists')
        .delete()
        .eq('id', listId);
  }
}