import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  // -------------------------------------------------------------------
  // LISTS MANAGEMENT
  // -------------------------------------------------------------------

  // Stream to fetch all lists owned by or shared with the current user
  Stream<List<Map<String, dynamic>>> getMyLists() {
    final currentUserId = currentUser?.id;
    if (currentUserId == null) {
      // Return an empty stream if the user is not logged in
      return Stream.value([]);
    }
    
    // We use the postgrest-style filtering/selection logic
    return _client
        .from('lists')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        // RLS policy "Members can view list details" handles filtering by membership
        .execute(); 
  }

  // RPC to safely create a list and add the creator as a member (Fixes RLS recursion)
  Future<Map<String, dynamic>> createNewList(String listName) async {
    final currentUserId = currentUser?.id;
    if (currentUserId == null) {
      throw Exception('User not logged in.');
    }

    // Calls the 'create_list_and_add_member' SQL function
    final response = await _client.rpc(
      'create_list_and_add_member',
      params: {
        'list_name': listName,
      },
    );

    // The RPC function returns a single JSON object (e.g., {'id': 1234})
    final listId = response['id'];
    return {'id': listId.toString(), 'name': listName};
  }
  //delete
  Future<void> deleteList(int listId) async {
    // RLS policy handles security (only owner/member can delete)
    await _client.from('lists')
        .delete()
        .eq('id', listId);
  }


  // -------------------------------------------------------------------
  // ITEMS MANAGEMENT (NEW FUNCTIONS TO FIX ERRORS)
  // -------------------------------------------------------------------

  // Function to add a new item to a list
  Future<void> addItem(int listId, String title) async {
    final currentUserId = currentUser?.id;
    if (currentUserId == null) {
      throw Exception('User not logged in.');
    }

    // RLS policy "Members can modify and view items" handles security
    await _client.from('items').insert({
      'list_id': listId,
      'title': title,
      'is_completed': false,
    });
  }

  // Stream to fetch items for a specific list
  Stream<List<Map<String, dynamic>>> getItemsStream(int listId) {
    return _client
        .from('items')
        .stream(primaryKey: ['id'])
        .eq('list_id', listId)
        .order('created_at', ascending: true) // Sort items by creation time
        .execute();
  }

  // Function to update an item's fields (e.g., title, is_completed, formatting)
  Future<void> updateItem(int itemId, Map<String, dynamic> updates) async {
    final currentUserId = currentUser?.id;
    if (currentUserId == null) {
      throw Exception('User not logged in.');
    }

    // RLS policy "Members can modify and view items" handles security
    await _client.from('items')
        .update(updates)
        .eq('id', itemId);
  }
  Future<void> deleteItem(int itemId) async {
  final currentUserId = currentUser?.id;
  if (currentUserId == null) {
    throw Exception('User not logged in.');
  }

  // RLS policy "Members can modify and view items" handles security
  await _client.from('items')
      .delete()
      .eq('id', itemId);
  }
  // List Items Preview
  Future<List<Map<String, dynamic>>> getListItemsPreview(int listId) async {
  final data = await _client
      .from('items')
      .select('title')
      .eq('list_id', listId)
      .limit(3) // Get the top 3 items
      .order('created_at', ascending: true);
  
  return data as List<Map<String, dynamic>>;
  }
  Future<void> bulkUpdateItemSortOrder(List<Map<String, dynamic>> items) async {
    // The items list will contain {'id': itemId, 'sort_order': newSortOrder} objects.
    await _client
        .from('items')
        .upsert(items); // upsert is efficient for bulk updates on primary keys
  }
  Stream<List<Map<String, dynamic>>> getItemsStream(int listId) {
  return _client.from('items')
      .stream(primaryKey: ['id'])
      .eq('list_id', listId)
      // IMPORTANT: Sort by sort_order first, then use created_at as a tie-breaker
      .order('sort_order', ascending: true) 
      .order('created_at', ascending: true)
      .map((data) => data as List<Map<String, dynamic>>);
}
}