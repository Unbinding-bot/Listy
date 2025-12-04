// lib/services/supabase_services.dart
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
      return Stream.value(<Map<String, dynamic>>[]);
    }

    // FIX: Removed .execute() as it is deprecated for stream builders.
    return _client
        .from('lists')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((event) => (event as List<dynamic>).cast<Map<String, dynamic>>());
    // RLS policy "Members can view list details" handles filtering by membership
  }

  // RPC to safely create a list and add the creator as a member (Fixes RLS recursion)
  Future<Map<String, dynamic>> createNewList(String listName) async {
    final currentUserId = currentUser?.id;
    if (currentUserId == null) {
      throw Exception('User not logged in.');
    }

    // Calls the DB RPC which inserts into lists and list_members
    final response = await _client.rpc(
      'create_list_and_add_member',
      params: {'list_name': listName},
    );

    final listId = response['id'];
    if (listId == null) {
      throw Exception('Failed to create list.');
    }

    // Fetch the authoritative row (id + name). Schema does not include owner_id on lists,
    // so we return currentUserId as owner_id for convenience.
    final listRow = await _client.from('lists').select('id, name').eq('id', listId).maybeSingle();

    return {
      'id': listRow?['id']?.toString() ?? listId.toString(),
      'name': listRow?['name'] ?? listName,
      // Your schema uses list_members for ownership; return creator id as owner_id for UI convenience.
      'owner_id': currentUserId,
    };
  }

  /// Fetch list row by id (authoritative name)
  Future<Map<String, dynamic>?> getListById(int listId) async {
    final response = await _client.from('lists').select('id, name').eq('id', listId).maybeSingle();
    if (response == null) return null;
    return {
      'id': response['id']?.toString(),
      'name': response['name'],
    };
  }

  // NEW: Function to update list name
  Future<void> updateListName(int listId, String newName) async {
    final currentUserId = currentUser?.id;
    if (currentUserId == null) {
      throw Exception('User not logged in.');
    }

    await _client.from('lists').update({'name': newName}).eq('id', listId);
    // RLS policy should ensure only owners/members can perform this update
  }

  //delete
  Future<void> deleteList(int listId) async {
    // RLS policy handles security (only owner/member can delete)
    await _client.from('lists').delete().eq('id', listId);
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
    return _client
        .from('items')
        .stream(primaryKey: ['id'])
        .eq('list_id', listId)
        // IMPORTANT: Sort by sort_order first, then use created_at as a tie-breaker
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true)
        .map((data) => (data as List<dynamic>).cast<Map<String, dynamic>>());
  }

  Stream<List<Map<String, dynamic>>> getListItems(int listId) => getItemsStream(listId);

  // Function to update an item's fields (e.g., title, is_completed, formatting)
  Future<void> updateItem(int itemId, Map<String, dynamic> updates) async {
    final currentUserId = currentUser?.id;
    if (currentUserId == null) {
      throw Exception('User not logged in.');
    }

    // RLS policy "Members can modify and view items" handles security
    await _client.from('items').update(updates).eq('id', itemId);
  }

  Future<void> deleteItem(int itemId) async {
    final currentUserId = currentUser?.id;
    if (currentUserId == null) {
      throw Exception('User not logged in.');
    }

    // RLS policy "Members can modify and view items" handles security
    await _client.from('items').delete().eq('id', itemId);
  }

  // List Items Preview
  Future<List<Map<String, dynamic>>> getListItemsPreview(int listId) async {
    // FIX: Removed .execute()
    final data = await _client.from('items').select('title').eq('list_id', listId).limit(3).order('created_at', ascending: true);

    return (data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> bulkUpdateItemSortOrder(List<Map<String, dynamic>> items) async {
    // The items list will contain {'id': itemId, 'sort_order': newSortOrder} objects.
    await _client.from('items').upsert(items); // upsert is efficient for bulk updates on primary keys
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
      // FIX: Removed .execute()
      final response = await _client.from('list_members').select('role').eq('list_id', listId).eq('user_id', userId).maybeSingle();

      if (response == null) return null;
      return response['role'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Method to fetch the current list of members with profiles (NOT real-time)
  Future<List<Map<String, dynamic>>> getListMembersWithProfiles(int listId) async {
    // 1. Fetch all user_id UUIDs from the list_members table for the given list.
    final memberIdsResponse = await _client.from('list_members').select('user_id').eq('list_id', listId);

    // Extract the raw list of UUIDs (Strings)
    final memberUids = (memberIdsResponse as List).map((row) => row['user_id'] as String).toList();

    if (memberUids.isEmpty) {
      return [];
    }

    // 2. Fetch the profile data (username) directly from the profiles table
    // using the list of UIDs retrieved in step 1.
    final profiles = await _client.from('profiles').select('id, username').filter('id', 'in', memberUids.toList()); // Safely query all profiles whose ID is in the list

    // Return the list of profiles (e.g., [{'id': '...', 'username': 'user1'}, ...])
    return (profiles as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getListMembersWithProfilesAndRoles(int listId) async {
    try {
      // Preferred approach: select from list_members and include nested profile fields
      final response = await _client.from('list_members').select('role, user:profiles(id, username, email)').eq('list_id', listId);

      if (response == null) return <Map<String, dynamic>>[];

      final rows = response as List<dynamic>;
      final members = <Map<String, dynamic>>[];

      for (final raw in rows) {
        if (raw is! Map<String, dynamic>) continue;
        final role = raw['role'] as String?;
        final userObj = raw['user'] as Map<String, dynamic>? ?? <String, dynamic>{};
        members.add({
          'id': userObj['id']?.toString(),
          'username': userObj['username'] as String?,
          'email': userObj['email'] as String?,
          'role': role ?? 'member',
        });
      }
      return members;
    } catch (e, st) {
      // Print for debugging in dev; handle/log properly in production
      print('getListMembersWithProfilesAndRoles error: $e\n$st');
      return <Map<String, dynamic>>[];
    }
  }

  // FIXED: Real-time stream for list members using switchMap.
  Stream<List<Map<String, dynamic>>> getListMembers(int listId) {
    // 1. Create a simple stream that listens for ANY change in the list_members table for this list.
    final streamOfChanges = _client.from('list_members').stream(primaryKey: ['list_id', 'user_id']).eq('list_id', listId).order('user_id', ascending: true);

    // 2. Use rxdart's switchMap to convert the stream of change notifications 
    //    into a stream of the full profile list (by calling the Future function).
    return streamOfChanges.switchMap((_) => Stream.fromFuture(getListMembersWithProfiles(listId)));
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

    await _client.from('list_members').delete().eq('list_id', listId).eq('user_id', memberUserId);
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
        .eq('role', 'owner');

    // 2. Promote the new user to 'owner'
    await _client
        .from('list_members')
        .upsert([
          {'list_id': listId, 'user_id': newOwnerId, 'role': 'owner'}
        ], onConflict: 'list_id,user_id');
  }
}