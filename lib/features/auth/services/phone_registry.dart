import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/country_codes.dart';

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

  /// Every registry document that could reserve the same physical number as
  /// [phone]. Legacy claims were written with the digits of whatever phone
  /// string was used back then (e.g. `01554302546` for an Egypt number that
  /// is now entered as `+201554302546`), so the claim check must look at all
  /// of them instead of only the current canonical form.
  List<DocumentReference<Map<String, dynamic>>> claimRefs(String phone) =>
      equivalentForms(phone)
          .map(normalizeDigits)
          .where((digits) => digits.isNotEmpty)
          .map((digits) => _db.collection(_registryCollection).doc(digits))
          .toSet()
          .toList();

  /// Every stored string form that can represent the SAME physical number
  /// as [phone]. Legacy accounts (created before strict E.164 storage) may
  /// hold any of these, so uniqueness checks have to compare against all of
  /// them:
  ///
  /// * E.164: `+201554302546`
  /// * bare digits: `201554302546`
  /// * national with trunk zero: `01554302546`
  /// * E.164 with a kept leading zero: `+2001554302546`
  /// * local number only: `1554302546`
  static List<String> equivalentForms(String phone) {
    final e164 = toE164(phone);
    final digits = normalizeDigits(phone);
    if (digits.isEmpty) return const [];

    final forms = <String>{e164, digits};

    // Prefer the most specific dialing code first (e.g. +1268 before +1 so
    // a Bahamas number is not matched as a NANP +1 number).
    final orderedCountries = List.of(CountryCodes.countries)
      ..sort((a, b) => b.code.length.compareTo(a.code.length));

    // Find the country whose dialing code is the prefix of the E.164 digits
    // (with a national-number length that fits that country) and derive the
    // national / trunk-zero representations from the remaining local part.
    CountryCode? matched;
    for (final country in orderedCountries) {
      final cc = country.code.replaceAll('+', '');
      if (cc.isEmpty ||
          digits.length <= cc.length ||
          !digits.startsWith(cc)) {
        continue;
      }
      final (minLen, maxLen) = CountryCodes.phoneNumberLength(country);
      final local = digits.substring(cc.length);
      if (local.length >= minLen && local.length <= maxLen) {
        matched = country;
        break;
      }
    }

    if (matched != null) {
      final cc = matched.code.replaceAll('+', '');
      final local = digits.substring(cc.length);
      forms.add(local); // 1554302546
      if (!local.startsWith('0')) {
        final withTrunk = '0$local'; // 01554302546
        forms.add(withTrunk);
        forms.add('+$cc$withTrunk'); // +2001554302546
        forms.add('$cc$withTrunk'); // 2001554302546
      }
    }

    // If [phone] itself already carries a trunk zero right after the dialing
    // code (legacy "+2001..." passed in directly), also derive the canonical
    // E.164 so both forms are matched.
    for (final country in orderedCountries) {
      final cc = country.code.replaceAll('+', '');
      if (cc.isEmpty || digits.length <= cc.length) continue;
      if (digits.startsWith('$cc' '0')) {
        final withoutZero = digits.substring(cc.length); // starts with 0
        final canonical = '$cc${withoutZero.substring(1)}';
        if (canonical.isNotEmpty) {
          forms.add('+$canonical');
          forms.add(canonical);
        }
        break;
      }
    }

    return forms.toList();
  }

  /// True when [phone] is taken by a live (non-deleted) user other than
  /// [excludeUid]. Checks the registry first, then the users collection as
  /// a fallback for accounts created before the registry existed.
  Future<bool> isPhoneInUse(String phone, {String? excludeUid}) async {
    final forms = equivalentForms(phone);
    if (forms.isEmpty) return false;

    for (final registryRef in claimRefs(phone)) {
      final claim = await registryRef.get();
      if (claim.exists) {
        final owner = claim.data()?['uid'] as String?;
        if (owner != null && owner.isNotEmpty && owner != excludeUid) {
          final ownerSnap = await _db.collection('users').doc(owner).get();
          if (ownerSnap.exists && ownerSnap.data()?['isDeleted'] != true) {
            return true;
          }
        }
      }
    }

    final legacy = await _db
        .collection('users')
        .where('phoneNumber', whereIn: forms)
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