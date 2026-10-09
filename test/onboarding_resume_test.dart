import 'dart:convert';

import 'package:flash_chat_app/core/utils/country_codes.dart';
import 'package:flash_chat_app/features/auth/cubit/auth_state.dart';
import 'package:flash_chat_app/features/auth/services/pending_signup_service.dart';
import 'package:flash_chat_app/services/otp/otp_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract tests for the onboarding-resume data layer.
///
/// Cold-start routing is decided by the cloud `onboardingPending` marker, not
/// by the on-phone draft: the profile document is written BEFORE the code is
/// sent, so a user waiting on a code already looks "profile complete". If these
/// rules drift, users either get stranded on the auth screen, land in an empty
/// Home, or established accounts get forced back through onboarding.
void main() {
  group('resolveSessionDestination', () {
    test('a finished account goes home', () {
      expect(
        resolveSessionDestination(
          docExists: true,
          profileComplete: true,
          onboardingPending: false,
        ),
        SessionDestination.home,
      );
    });

    test(
        'an account that quit while waiting for its code goes to resume, '
        'not to an empty Home', () {
      // The regression that motivated the marker: the profile (name, phone) is
      // already in Firestore at this point, so `profileComplete` alone would
      // send this user Home with an unverified phone number.
      expect(
        resolveSessionDestination(
          docExists: true,
          profileComplete: true,
          onboardingPending: true,
        ),
        SessionDestination.needsProfile,
      );
    });

    test('an account that quit on the profile screen goes to resume', () {
      // Push services have created the name-less shell document, but the marker
      // is set, so this must not be mistaken for a legacy account.
      expect(
        resolveSessionDestination(
          docExists: true,
          profileComplete: false,
          onboardingPending: true,
        ),
        SessionDestination.needsProfile,
      );
    });

    test('an auth account with no document at all goes to resume', () {
      expect(
        resolveSessionDestination(
          docExists: false,
          profileComplete: false,
          onboardingPending: false,
        ),
        SessionDestination.needsProfile,
      );
    });

    test('a legacy account without a name still goes home', () {
      // Established pre-OTP account: an existing document proves the account is
      // real, so it must not be locked back into onboarding.
      expect(
        resolveSessionDestination(
          docExists: true,
          profileComplete: false,
          onboardingPending: false,
        ),
        SessionDestination.home,
      );
    });

    test('the marker never overrides into Home', () {
      for (final docExists in [true, false]) {
        for (final profileComplete in [true, false]) {
          expect(
            resolveSessionDestination(
              docExists: docExists,
              profileComplete: profileComplete,
              onboardingPending: true,
            ),
            SessionDestination.needsProfile,
            reason: 'docExists=$docExists profileComplete=$profileComplete',
          );
        }
      }
    });

    test('a uid-scoped draft rescues an account whose marker write failed', () {
      // The marker is written best-effort at sign-up, so it can be lost to an
      // offline or denied write. Without the draft fallback this account landed
      // in an empty Home — the original bug.
      expect(
        resolveSessionDestination(
          docExists: true,
          profileComplete: false,
          onboardingPending: false,
          hasLocalDraft: true,
        ),
        SessionDestination.needsProfile,
      );
    });

    test('a draft cannot drag a completed account back out of Home', () {
      // A completed profile wins over a leftover draft: the profile step
      // re-asserts the marker in the same transaction, so the OTP case never
      // depends on the draft.
      expect(
        resolveSessionDestination(
          docExists: true,
          profileComplete: true,
          onboardingPending: false,
          hasLocalDraft: true,
        ),
        SessionDestination.home,
      );
    });

    test('with nothing to go on, a nameless legacy account still goes home',
        () {
      expect(
        resolveSessionDestination(
          docExists: true,
          profileComplete: false,
          onboardingPending: false,
        ),
        SessionDestination.home,
      );
    });
  });

  group('PendingSignup', () {
    test('a brand-new account starts on the profile step', () {
      const draft = PendingSignup.atProfile(uid: 'uid-1');
      expect(draft.uid, 'uid-1');
      expect(draft.step, PendingSignupStep.profile);
      expect(draft.otpId, isEmpty);
      // Usable: the profile step needs no other data.
      expect(draft.isUsable, isTrue);
    });

    test('advancing to the OTP step keeps the identity and phone', () {
      const draft = PendingSignup.atProfile(
        uid: 'uid-1',
        firstName: 'Ada',
        lastName: 'Lovelace',
      );
      final otp = draft.withOtp(
        otpId: 'otp_123',
        phoneNumber: '+201001234567',
        countryCode: '+20',
      );

      expect(otp.step, PendingSignupStep.otp);
      expect(otp.uid, 'uid-1');
      expect(otp.firstName, 'Ada');
      expect(otp.lastName, 'Lovelace');
      expect(otp.phoneNumber, '+201001234567');
      expect(otp.countryCode, '+20');
      expect(otp.otpId, 'otp_123');
      expect(otp.isUsable, isTrue);
    });

    test('an OTP draft missing its phone or session is rejected', () {
      const noPhone = PendingSignup(
        uid: 'uid-1',
        step: PendingSignupStep.otp,
        firstName: '',
        lastName: '',
        phoneNumber: '',
        countryCode: '+20',
        otpId: 'otp_123',
      );
      const noSession = PendingSignup(
        uid: 'uid-1',
        step: PendingSignupStep.otp,
        firstName: '',
        lastName: '',
        phoneNumber: '+201001234567',
        countryCode: '+20',
        otpId: '',
      );

      // Without a phone number there is nothing to re-request a code for.
      expect(noPhone.isUsable, isFalse);
      // Without a session id there is no code to enter.
      expect(noSession.isUsable, isFalse);
    });

    test('survives a storage round trip', () {
      const draft = PendingSignup(
        uid: 'uid-1',
        step: PendingSignupStep.otp,
        firstName: 'Ada',
        lastName: 'Lovelace',
        phoneNumber: '+201001234567',
        countryCode: '+20',
        otpId: 'otp_123',
      );

      final restored = PendingSignup.fromJson(
        jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>,
      );

      expect(restored.uid, 'uid-1');
      expect(restored.step, PendingSignupStep.otp);
      expect(restored.firstName, 'Ada');
      expect(restored.lastName, 'Lovelace');
      expect(restored.phoneNumber, '+201001234567');
      expect(restored.countryCode, '+20');
      expect(restored.otpId, 'otp_123');
    });

    test('a draft written by an older build is read as the OTP step', () {
      // Before the step existed, a draft was only ever written once a code
      // had been sent, and it carried no uid.
      final restored = PendingSignup.fromJson({
        'firstName': 'Ada',
        'lastName': 'Lovelace',
        'phoneNumber': '+201001234567',
        'countryCode': '+20',
        'otpId': 'otp_123',
      });

      expect(restored.step, PendingSignupStep.otp);
      expect(restored.uid, isEmpty);
      expect(restored.isUsable, isTrue);
    });

    test('a profile step survives a round trip with empty OTP fields', () {
      const draft = PendingSignup.atProfile(uid: 'uid-1', firstName: 'Ada');
      final restored = PendingSignup.fromJson(
        jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>,
      );

      expect(restored.step, PendingSignupStep.profile);
      expect(restored.isUsable, isTrue);
    });

    test('a draft is not an OTP draft just because it exists', () {
      // The auth screen must branch on the STEP, not on the draft merely
      // existing: a draft written when the account was created is non-null
      // but has no phone number and no session, so treating it as
      // "waiting for a code" would ask for a code that was never sent.
      const fresh = PendingSignup.atProfile(uid: 'uid-1');
      expect(fresh, isNotNull);
      expect(fresh.step, isNot(PendingSignupStep.otp));
      expect(fresh.otpId, isEmpty);
      expect(fresh.phoneNumber, isEmpty);

      const atOtp = PendingSignup(
        uid: 'uid-1',
        step: PendingSignupStep.otp,
        firstName: '',
        lastName: '',
        phoneNumber: '+201001234567',
        countryCode: '+20',
        otpId: 'otp_123',
      );
      expect(atOtp.step, PendingSignupStep.otp);
      expect(atOtp.otpId, isNotEmpty);
    });
  });

  group('OtpSessionStatus.isExpired', () {
    test('a session with an expiry in the future is alive', () {
      final status = OtpSessionStatus(
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      );
      expect(status.isExpired, isFalse);
    });

    test('a session whose expiry has passed is expired', () {
      final status = OtpSessionStatus(
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(status.isExpired, isTrue);
    });

    test('a session with no expiry cannot be trusted', () {
      // The Home resume button must request a new code rather than offer an
      // input that is guaranteed to fail.
      expect(const OtpSessionStatus().isExpired, isTrue);
    });
  });

  group('CountryCodes.countryForPhone', () {
    // Restoring the stored number into the profile form is what stops a user
    // retyping — and mistyping — information they already saved. Picking the
    // WRONG country would rewrite the number as a different, valid-looking
    // international number, which is exactly the corruption to avoid.
    test('restores the country of a stored E.164 number', () {
      expect(CountryCodes.countryForPhone('+201001234567')?.code, '+20');
    });

    test('refuses to guess when the plus sign is missing', () {
      // "201001234567" would look like a +20 number, but a bare digit string is
      // ambiguous and must not be allowed to silently rewrite a stored number.
      expect(CountryCodes.countryForPhone('201001234567'), isNull);
    });

    test('prefers the longest matching dial code', () {
      // "+1" also prefixes every "+1..." number, so a short match must not
      // shadow the real one.
      final found = CountryCodes.countryForPhone('+447911123456');
      expect(found, isNotNull);
      expect(found!.code, '+44');
    });

    test('a bare national number is not mistaken for a +1 number', () {
      // The regression this guards: "1012345678" is a valid Egyptian national
      // number AND starts with the digits "1", so a naive prefix match picked
      // the USA and would have rewritten the saved number as a US one.
      expect(CountryCodes.countryForPhone('1012345678'), isNull);
    });

    test('empty or digit-less input yields no country', () {
      expect(CountryCodes.countryForPhone(''), isNull);
      expect(CountryCodes.countryForPhone('+'), isNull);
    });

    test('a dial code with no subscriber digits yields no country', () {
      expect(CountryCodes.countryForPhone('+20'), isNull);
    });
  });
}
