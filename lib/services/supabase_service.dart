import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rxdart/rxdart.dart'; // REQUIRED: Add this dependency to your pubspec.yaml

class SupabaseService {
  final _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  // Global helper to get the current user's ID
  String? get currentUserId => currentUser?.id;

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
    return {'id': listId.toString(), 'name': listName, 'owner_id': currentUserId};
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

  // NEW: Get the current user's role for this specific list
  // Returns 'owner', 'member', or null
  Future<String?> getCurrentUserRole(int listId) async {
    final userId = currentUserId;
    if (userId == null) return null;

    try {
      final response = await _client
        .from('list_members')
        .select('role')
        .eq('list_id', listId)
        .eq('user_id', userId)
        .single();
      
      return response['role'] as String?;
    } on PostgrestException catch (e) {
      // PostgrestException for 'single' when no rows found (expected if not a member)
      if (e.code == 'PGRST116') {
        return null;
      }
      rethrow;
    }
  }

  // Method to fetch the current list of members with profiles (NOT real-time)
  // This uses a complex join query and is safe to use in a FutureBuilder.
  // It resolves the 'supabase' vs '_client' issue.
  Future<List<Map<String, dynamic>>> getListMembersWithProfiles(int listId) async {
    final response = await _client
        .from('list_members')
        // We only care about the user_id for the join, so we select the nested profiles
        .select('profiles!inner(id, username, email), user_id') 
        .eq('list_id', listId)
        .order('user_id') // Order by ID to make it deterministic
        .execute();

    if (response.error != null) {
      throw Exception('Error fetching list members: ${response.error!.message}');
    }

    final List<dynamic> memberData = response.data as List<dynamic>;

    // Map the list to extract the profile map directly
    return memberData
        .map((item) => (item as Map<String, dynamic>)['profiles'] as Map<String, dynamic>)
        .toList();
  }
  
  // FIXED: Real-time stream for list members using switchMap.
  // This resolves the 'select' method error on the stream builder.
  Stream<List<Map<String, dynamic>>> getListMembers(int listId) {
    // 1. Create a simple stream that listens for ANY change in the list_members table for this list.
    // We only select the user_id to minimize the payload of the notification.
    final streamOfChanges = _client
        .from('list_members')
        .stream(primaryKey: ['list_id', 'user_id'])
        .eq('list_id', listId)
        .select('user_id') // Use simple select or no select on the stream
        .order('user_id', ascending: true);
        
    // 2. Use rxdart's switchMap to convert the stream of change notifications 
    //    into a stream of the full profile list (by calling the Future function).
    return streamOfChanges.switchMap(
      (_) => Stream.fromFuture(
        getListMembersWithProfiles(listId),
      ),
    );
  }

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