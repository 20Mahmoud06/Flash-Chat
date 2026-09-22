import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/features/auth/services/phone_registry.dart';
import 'package:flutter/foundation.dart';

/// One-time migration that makes phone uniqueness reliable for existing
/// accounts:
///
/// 1. Normalizes every stored `phoneNumber` to canonical E.164
///    (e.g. `+20 100 123 4567` → `+201001234567`). Values that already
///    start with `+` are safe to re-format; anything else is kept digits-only
///    and skipped because the country cannot be derived.
/// 2. Backfills the `phoneNumbers/{digits}` registry with a claim for every
///    live (non-deleted) user. If two users share one number, the first one
///    keeps the claim and the duplicate is logged for manual review.
///
/// Run once after deploying the new build: `dart run lib/tools/migrate_phone_numbers.dart`.
Future<void> migratePhoneNumbers() async {
  try {
    final firestore = FirebaseFirestore.instance;
    final usersSnapshot = await firestore.collection('users').get();

    debugPrint('Found ${usersSnapshot.docs.length} users to migrate...');

    for (final userDoc in usersSnapshot.docs) {
      final data = userDoc.data();
      final rawPhone = data['phoneNumber'] as String? ?? '';
      if (rawPhone.isEmpty) continue;

      final digits = PhoneRegistry.normalizeDigits(rawPhone);
      if (digits.isEmpty) {
        debugPrint('User ${userDoc.id}: empty phone, skipping.');
        continue;
      }

      final canonical = rawPhone.startsWith('+')
          ? '+$digits'
          : digits;
      if (canonical != rawPhone) {
        await firestore.collection('users').doc(userDoc.id).update({
          'phoneNumber': canonical,
        });
        debugPrint(
            'User ${userDoc.id}: normalized "$rawPhone" -> "$canonical"');
      }

      final isDeleted = data['isDeleted'] == true;
      if (isDeleted) {
        debugPrint('User ${userDoc.id}: tombstoned, no registry claim.');
        continue;
      }

      final claimRef = PhoneRegistry.instance.claimRef(canonical);
      final claim = await claimRef.get();
      if (claim.exists) {
        final owner = claim.data()?['uid'] as String?;
        if (owner != null && owner != userDoc.id) {
          final ownerExists = await firestore
              .collection('users')
              .doc(owner)
              .get()
              .then((d) => d.exists && d.data()?['isDeleted'] != true);
          if (ownerExists) {
            debugPrint('WARNING: ${userDoc.id} duplicates phone of '
                '$owner ($digits); keeping $owner.');
            continue;
          }
        }
      }

      await claimRef.set({
        'uid': userDoc.id,
        'claimedAt': Timestamp.now(),
      });
      debugPrint('User ${userDoc.id}: claimed $digits.');
    }

    debugPrint('Phone migration completed successfully!');
  } catch (e) {
    debugPrint('Error during migration: $e');
  }
}

void main() async {
  debugPrint('Starting phone-number migration...');
  await migratePhoneNumbers();
  debugPrint('Migration script completed.');
}