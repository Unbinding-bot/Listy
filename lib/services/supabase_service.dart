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
 // ITEMS MANAGEMENT
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

 // Stream to fetch items for a specific list (Uses sort_order for reordering)
 Stream<List<Map<String, dynamic>>> getItemsStream(int listId) {
  return _client.from('items')
    .stream(primaryKey: ['id'])
    .eq('list_id', listId)
    // IMPORTANT: Sort by sort_order first, then use created_at as a tie-breaker
    .order('sort_order', ascending: true) 
    .order('created_at', ascending: true)
    .map((data) => data as List<Map<String, dynamic>>);
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

 // -------------------------------------------------------------------
 // SHARING/MEMBERSHIP MANAGEMENT
 // -------------------------------------------------------------------

 Future<void> addListMember(int listId, String memberEmail) async {
  final currentUserId = currentUser?.id;
  if (currentUserId == null) {
   throw Exception('User not logged in.');
  }

  // 1. Find the target user's ID by their email
  final users = await _client
    .from('users')
    .select('id')
    .eq('email', memberEmail)
    .limit(1);

  if (users.isEmpty) {
   throw Exception('User with email $memberEmail not found.');
  }

  final memberId = users.first['id'] as String;

  // 2. Insert the new membership record
  await _client.from('list_members').upsert({
   'list_id': listId,
   'user_id': memberId,
   'role': 'member', 
   'added_by': currentUserId,
  });
 }

 /// Fetches all members for a specific list, joining with user data.
 Future<List<Map<String, dynamic>>> getListMembers(int listId) async {
  final currentUserId = currentUser?.id;
  if (currentUserId == null) {
   throw Exception('User not logged in.');
  }
  
  // Selects list_members data and joins with user details ('users!inner(id, user_metadata)')
  final data = await _client
    .from('list_members')
    .select('role, added_at, user_id, users:user_id!inner(user_metadata, email)')
    .eq('list_id', listId);

  return data as List<Map<String, dynamic>>;
 }

 /// Removes a member from a list.
 Future<void> removeListMember(int listId, String memberUserId) async {
  final currentUserId = currentUser?.id;
  if (currentUserId == null) {
   throw Exception('User not logged in.');
  }

  await _client
    .from('list_members')
    .delete()
    .eq('list_id', listId)
    .eq('user_id', memberUserId);
 }
 
 /// Promotes a member to owner. 
 Future<void> transferOwnership(int listId, String newOwnerId) async {
  final currentUserId = currentUser?.id;
  if (currentUserId == null) {
   throw Exception('User not logged in.');
  }
  
  // Update the new owner's role to 'owner'
  await _client
   .from('list_members')
   .update({'role': 'owner'})
   .eq('list_id', listId)
   .eq('user_id', newOwnerId);

  // Demote the current user to a regular 'member' (if they were the previous owner)
  await _client
   .from('list_members')
   .update({'role': 'owner'})
   .eq('list_id', listId)
   .eq('user_id', currentUserId);
 }
}