import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// This script migrates all existing groups to include join timestamps
/// for existing members. Run this once to update the database.
Future<void> migrateAllGroups() async {
  try {
    final firestore = FirebaseFirestore.instance;
    final groupsSnapshot = await firestore.collection('groups').get();

    debugPrint('Found ${groupsSnapshot.docs.length} groups to migrate...');

    for (final groupDoc in groupsSnapshot.docs) {
      final data = groupDoc.data();
      final memberUids = List<String>.from(data['memberUids'] ?? []);

      // Check if already migrated
      if (data['memberJoinTimestamps'] != null) {
        debugPrint('Group ${groupDoc.id} already migrated, skipping...');
        continue;
      }

      // Create join timestamps for all existing members (set to group creation time)
      final groupCreatedAt = data['createdAt'] ?? Timestamp.now();
      final joinTimestamps = {
        for (var uid in memberUids) uid: groupCreatedAt
      };

      await firestore.collection('groups').doc(groupDoc.id).update({
        'memberJoinTimestamps': joinTimestamps,
      });

      debugPrint('Migrated group ${groupDoc.id} with ${memberUids.length} members');
    }

    debugPrint('Migration completed successfully!');
  } catch (e) {
    debugPrint('Error during migration: $e');
  }
}

void main() async {
  debugPrint('Starting group migration...');
  await migrateAllGroups();
  debugPrint('Migration script completed.');
}