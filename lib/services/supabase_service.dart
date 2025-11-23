import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rxdart/rxdart.dart'; // REQUIRED: Add this dependency to your pubspec.yaml
import 'package:postgrest/postgrest.dart'; // For PostgrestException

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
    final curUserId = currentUser?.id;
    if (curUserId == null) {
      // Return an empty stream if the user is not logged in
      return Stream.value(<List<Map<String, dynamic>>>[]);
    }

    // RLS policy "Members can view list details" handles filtering by membership
    return _client
        .from('lists')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((event) => (event as List<dynamic>).cast<Map<String, dynamic>>());
  }

  // RPC to safely create a list and add the creator as a member (Fixes RLS recursion)
  Future<Map<String, dynamic>> createNewList(String listName) async {
    final curUserId = currentUser?.id;
    if (curUserId == null) {
      throw Exception('User not logged in.');
    }

    // Calls the DB RPC which inserts into lists and list_members
    final response = await _client.rpc(
      'create_list_and_add_member',
      params: {'list_name': listName},
    );

    // The RPC returns JSON with 'id'
    final listId = response != null ? (response['id'] ?? response['create_list_and_add_member']) : null;
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
      'owner_id': curUserId,
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
    final cur = currentUser?.id;
    if (cur == null) throw Exception('User not logged in.');

    await _client.from('lists').update({'name': newName}).eq('id', listId);
    // RLS policy should ensure only owners can perform this update
  }

  // delete
  Future<void> deleteList(int listId) async {
    // RLS policy handles security (only owner/member can delete)
    await _client.from('lists').delete().eq('id', listId);
  }

  // -------------------------------------------------------------------
  // ITEMS MANAGEMENT
  // -------------------------------------------------------------------

  // Function to add a new item to a list
  Future<void> addItem(int listId, String title) async {
    final cur = currentUser?.id;
    if (cur == null) throw Exception('User not logged in.');

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
    final cur = currentUser?.id;
    if (cur == null) throw Exception('User not logged in.');

    // RLS policy "Members can modify and view items" handles security
    await _client.from('items').update(updates).eq('id', itemId);
  }

  Future<void> deleteItem(int itemId) async {
    final cur = currentUser?.id;
    if (cur == null) throw Exception('User not logged in.');

    // RLS policy "Members can modify and view items" handles security
    await _client.from('items').delete().eq('id', itemId);
  }

  // List Items Preview
  Future<List<Map<String, dynamic>>> getListItemsPreview(int listId) async {
    final data = await _client
        .from('items')
        .select('title')
        .eq('list_id', listId)
        .limit(3) // Get the top 3 items
        .order('created_at', ascending: true);

    if (data == null) return <Map<String, dynamic>>[];
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
      final response = await _client
          .from('list_members')
          .select('role')
          .eq('list_id', listId)
          .eq('user_id', userId)
          .maybeSingle();
      if (response == null) return null;
      return response['role'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Method to fetch the list of member user_ids for a given list
  Future<List<String>> _getMemberUserIds(int listId) async {
    final memberIdsResponse = await _client.from('list_members').select('user_id').eq('list_id', listId);
    if (memberIdsResponse == null) return [];
    final ids = (memberIdsResponse as List<dynamic>)
        .map((r) => r['user_id']?.toString())
        .whereType<String>()
        .toList();
    return ids;
  }

  /// Fetch profiles for a list of user IDs (helper)
  Future<List<Map<String, dynamic>>> _getProfilesForUserIds(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    // The 'in' filter format depends on client; many clients accept .filter('id', 'in', userIds)
    final profilesResp = await _client.from('profiles').select('id, username, email').filter('id', 'in', userIds);
    if (profilesResp == null) return [];
    return (profilesResp as List<dynamic>).cast<Map<String, dynamic>>();
  }

  // Method to fetch members' profiles (simple two-step approach)
  Future<List<Map<String, dynamic>>> getListMembersWithProfiles(int listId) async {
    final memberUids = await _getMemberUserIds(listId);
    if (memberUids.isEmpty) return [];
    final profiles = await _getProfilesForUserIds(memberUids);
    return profiles;
  }

  /// Fetch list members joined with profiles and include each member's role.
  /// Returns a List of maps: { 'id', 'username', 'email', 'role' }.
  Future<List<Map<String, dynamic>>> getListMembersWithProfilesAndRoles(int listId) async {
    try {
      // Preferred approach: select from list_members and include nested profile fields
      final response = await _client
          .from('list_members')
          .select('role, user:profiles(id, username, email)')
          .eq('list_id', listId);

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
    final streamOfChanges = _client
        .from('list_members')
        .stream(primaryKey: ['list_id', 'user_id'])
        .eq('list_id', listId)
        .order('user_id', ascending: true);

    // 2. Use rxdart's switchMap to convert the stream of change notifications
    //    into a stream of the full profile list (by calling the Future function).
    return streamOfChanges.switchMap((_) => Stream.fromFuture(getListMembersWithProfiles(listId)));
  }

  /// Finds user by email and adds them as a list member using an RPC (Required due to RLS).
  Future<void> addListMember(int listId, String memberEmail) async {
    final cur = currentUser?.id;
    if (cur == null) throw Exception('User not logged in.');

    // Use RPC to safely find the user by email and insert the member record.
    final response = await _client.rpc('add_member_by_email_and_list', params: {
      'list_id_in': listId,
      'member_email_in': memberEmail,
      'added_by_id_in': cur,
    });

    // The SQL function returns a text status; handle it if present
    final status = response;
    if (status is String) {
      if (status == 'user_not_found') throw Exception('User with email $memberEmail not found.');
      if (status == 'permission_denied') throw Exception('You do not have permission to add members.');
    } else if (status is Map && status.values.isNotEmpty) {
      // Some clients wrap the return in a map
      final val = status.values.first;
      if (val is String) {
        if (val == 'user_not_found') throw Exception('User with email $memberEmail not found.');
        if (val == 'permission_denied') throw Exception('You do not have permission to add members.');
      }
    }
  }

  /// Removes a member from a list.
  Future<void> removeListMember(int listId, String memberUserId) async {
    final cur = currentUser?.id;
    if (cur == null) throw Exception('User not logged in.');

    await _client.from('list_members').delete().eq('list_id', listId).eq('user_id', memberUserId);
  }

  /// Transfers ownership from the current owner to newOwnerId.
  Future<void> transferOwnership(int listId, String newOwnerId) async {
    final cur = currentUser?.id;
    if (cur == null) throw Exception('User not logged in.');

    // 1. Demote the current owner (if they are owner) to 'member'
    await _client
        .from('list_members')
        .update({'role': 'owner'})
        .eq('list_id', listId)
        .eq('user_id', cur)
        .eq('role', 'owner');

    // 2. Promote the new user to 'owner' using upsert to create or update
    await _client.from('list_members').upsert([
      {'list_id': listId, 'user_id': newOwnerId, 'role': 'owner'}
    ], onConflict: ['list_id', 'user_id']);
  }
}