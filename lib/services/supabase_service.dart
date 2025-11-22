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
  Future<void> createNewList(String listName) async {
    final currentUserId = currentUser?.id;
    if (currentUserId == null) {
      throw Exception('User not logged in.');
    }

    // Calls the 'create_list_and_add_member' SQL function
    await _client.rpc(
      'create_list_and_add_member',
      params: {
        'list_name': listName,
      },
    );
  }

  // Function to delete a list (RLS ensures only owner can do this)
  Future<void> deleteList(int listId) async {
    await _client
        .from('lists')
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
}