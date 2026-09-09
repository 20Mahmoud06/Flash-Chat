import 'package:cloud_firestore/cloud_firestore.dart';

/// Phone-number uniqueness helpers.
///
/// The canonical stored format is E.164 without separators (e.g.
/// `+201001234567`), so the same number typed with different spacing always
/// compares and sends identically.
///
/// Hard uniqueness is enforced with a small `phoneNumbers/{digits}`
/// registry: the claim is created inside the same Firestore transaction
/// that writes the user's profile, so two concurrent registrations of the
/// same number race each other and only one can commit.
class PhoneRegistry {
  PhoneRegistry._();
  static final PhoneRegistry instance = PhoneRegistry._();

  static const String _registryCollection = 'phoneNumbers';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Strips everything that is not a digit from [phone].
  static String normalizeDigits(String phone) =>
      phone.replaceAll(RegExp(r'\D'), '');

  /// Canonical E.164 form: `+` followed by the digits only.
  static String toE164(String phone) {
    final digits = normalizeDigits(phone);
    return digits.isEmpty ? phone : '+$digits';
  }

  /// The registry document that reserves [phone] (doc id = digits only).
  DocumentReference<Map<String, dynamic>> claimRef(String phone) =>
      _db.collection(_registryCollection).doc(normalizeDigits(phone));

  /// True when [phone] is taken by a live (non-deleted) user other than
  /// [excludeUid]. Checks the registry first, then the users collection as
  /// a fallback for accounts created before the registry existed.
  Future<bool> isPhoneInUse(String phone, {String? excludeUid}) async {
    final digits = normalizeDigits(phone);
    if (digits.isEmpty) return false;

    final claim = await claimRef(phone).get();
    if (claim.exists) {
      final owner = claim.data()?['uid'] as String?;
      if (owner != null && owner.isNotEmpty && owner != excludeUid) {
        final ownerSnap = await _db.collection('users').doc(owner).get();
        if (ownerSnap.exists && ownerSnap.data()?['isDeleted'] != true) {
          return true;
        }
      }
    }

    final legacy = await _db
        .collection('users')
        .where('phoneNumber', isEqualTo: toE164(phone))
        .limit(10)
        .get();
    return legacy.docs.any(
      (d) => d.id != excludeUid && d.data()['isDeleted'] != true,
    );
  }

  /// Releases the reservation for [phone] (used on account deletion so the
  /// number can be registered again).
  Future<void> release(String phone) async {
    final digits = normalizeDigits(phone);
    if (digits.isEmpty) return;
    try {
      await claimRef(phone).delete();
    } catch (_) {}
  }
}