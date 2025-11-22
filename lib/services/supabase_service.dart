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

 // NEW: Function to update list name
  Future<void> updateListName(int listId, String newName) async {
    final currentUserId = currentUser?.id;
    if (currentUserId == null) {
      throw Exception('User not logged in.');
    }

    await _client.from('lists')
        .update({
          'name': newName,
        })
        .eq('id', listId);
        // RLS policy should ensure only owners/members can perform this update
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

 // -------------------------------------------------------------------
 // SHARING/MEMBERSHIP MANAGEMENT
 // -------------------------------------------------------------------

 /// Finds user by email and adds them as a list member using an RPC (Required due to RLS).
 Future<void> addListMember(int listId, String memberEmail) async {
  final currentUserId = currentUser?.id;
  if (currentUserId == null) {
   throw Exception('User not logged in.');
  }
  
  // 🔑 FIX: Use RPC to safely find the user by email and insert the member record.
  // The SQL function handles the lookup in auth.users and the insertion into list_members.
  final response = await _client.rpc(
   'add_member_by_email_and_list', // NEW SQL FUNCTION NAME
   params: {
    'list_id_in': listId,
    'member_email_in': memberEmail,
    'added_by_id_in': currentUserId,
   },
  );
  
  // Check the response from the SQL function for errors
  if (response is String && response == 'user_not_found') {
    throw Exception('User with email $memberEmail not found.');
  }

 }

 Future<List<Map<String, dynamic>>> getListMembersWithProfiles(int listId) async {
  // 1. Get all user_ids associated with the list from list_members table
  final memberIdsResponse = await _client
      .from('list_members')
      .select('user_id')
      .eq('list_id', listId);

  // Extract the raw list of UUIDs
  final memberUids = (memberIdsResponse as List)
      .map((row) => row['user_id'] as String)
      .toList();

  if (memberUids.isEmpty) {
    return [];
  }

  // 2. Now fetch the profile data for those specific UIDs
  final profiles = await _client
      .from('profiles')
      .select('id, username')
      .filter('id', 'in', memberUids); // Use the list of UIDs extracted above

  return (profiles as List).cast<Map<String, dynamic>>();
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
  
  // 1. Demote the current owner to a regular 'member'
  await _client
    .from('list_members')
    .update({'role': 'owner'}) 
    .eq('list_id', listId)
    .eq('user_id', currentUserId)
    .eq('role', 'owner'); // Ensure we only demote if they were an owner

  // 2. Promote the new user to 'owner'
  await _client
    .from('list_members')
    .update({'role': 'owner'})
    .eq('list_id', listId)
    .eq('user_id', newOwnerId);
 }
}