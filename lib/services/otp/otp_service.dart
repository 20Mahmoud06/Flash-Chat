import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/config/env.dart';
import 'package:http/http.dart' as http;

/// Exception thrown when OTP operations fail.
class OtpException implements Exception {
  final String message;
  OtpException(this.message);

  @override
  String toString() => message;
}

/// Read-only snapshot of an OTP session stored in Firestore. The UI resumes
/// its resend countdown from [nextResendAt] so the cooldown survives widget
/// rebuilds, leaving/re-entering the screen, app backgrounding and app
/// restarts.
class OtpSessionStatus {
  /// When the current code stops being valid.
  final DateTime? expiresAt;

  /// Earliest moment a resend may be requested.
  final DateTime? nextResendAt;

  /// Number of successful resends so far.
  final int resendCount;

  const OtpSessionStatus({
    this.expiresAt,
    this.nextResendAt,
    this.resendCount = 0,
  });

  /// Whole seconds remaining until [nextResendAt] (0 when already elapsed).
  int get secondsUntilNextResend {
    final next = nextResendAt;
    if (next == null) return 0;
    final seconds = next.difference(DateTime.now()).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }
}

/// How long an OTP stays valid. Short, so users request a fresh code quickly
/// if they miss the window.
const Duration _otpTtl = Duration(minutes: 2);

/// OTP length delivered to the user.
const int _otpLength = 6;

/// Service for handling OTP (One-Time Password) operations.
///
/// This service:
/// 1. Generates a 6-digit code locally.
/// 2. Emails it to the signed-in user's verified account email using the
///    Brevo Transactional Email API (TEMP DEVELOPMENT PROTOTYPE — the Brevo
///    call will move to a secure backend like Cloud Functions before release).
/// 3. Persists a hash of the code + expiry + resend state in Firestore
///    (keyed by the session id), so verification still works even if the app
///    is killed and reopened.
///
/// Delivery only happens through email — never through a local notification
/// and never through an in-app display of the code.
///
/// Flow:
/// 1. [sendOtp] generates a code, emails it, stores it, returns an [otpId].
/// 2. The user reads the code from their email.
/// 3. [verifyOtp] looks up the session in Firestore and compares the hash.
/// 4. [resendOtp] generates a fresh code, emails it, and replaces the stored
///    code (the old one becomes invalid).
class OtpService {
  /// Firestore collection that holds active OTP sessions.
  static const String _collection = 'otp_verifications';

  /// Max wrong attempts before the code is invalidated.
  static const int _maxAttempts = 5;

  /// Max successful resends before further resends are blocked client-side
  /// (server-side enforcement comes later).
  static const int _maxResends = 3;

  static const Duration _timeout = Duration(seconds: 20);

  /// Resend cooldown applied for each successive resend count:
  /// count 0 (after the initial send) → 30 s,
  /// count 1 → 2 minutes,
  /// count 2 → 5 minutes.
  /// Once count reaches [maxResends], resends are blocked.
  static const List<Duration> _resendCooldowns = [
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

  final Random _rng = Random.secure();

  CollectionReference<Map<String, dynamic>> get _otpCol =>
      FirebaseFirestore.instance.collection(_collection);

  /// Generates a cryptographically random OTP string of [_otpLength] digits,
  /// preserving leading zeroes (e.g. `028451`).
  String _generateCode() {
    final raw = _rng.nextInt(pow(10, _otpLength).toInt());
    return raw.toString().padLeft(_otpLength, '0');
  }

  /// One-way hash used instead of storing the plaintext code.
  String _hashCode(String code) =>
      sha256.convert(utf8.encode(code)).toString();

  /// Generates a unique session id. Combined with the phone number, this is
  /// stored in Firestore and persisted locally so a killed app can resume.
  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final random = _rng.nextInt(0xFFFFFF).toRadixString(36).padLeft(6, '0');
    return 'otp_${timestamp}_$random';
  }

  /// The email account the OTP is delivered to: the already-authenticated
  /// Firebase account. Throws when no email is available.
  String _recipientEmail() {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw OtpException(
          'We could not find your email address. Please sign in again and try.');
    }
    return email;
  }

  /// Sends an OTP code to the signed-in user's email.
  ///
  /// [phone] The phone number in E.164 format (e.g., +201001234567) — used to
  /// bind the Firestore session; the code is delivered by email.
  /// Returns a session id that must be passed to [verifyOtp] or [resendOtp].
  Future<String> sendOtp({required String phone}) async {
    final code = _generateCode();
    final sessionId = _generateSessionId();
    final now = DateTime.now();
    final expiresAt = now.add(_otpTtl);

    try {
      // Deliver BEFORE persisting: a failed send must never leave an active
      // (undelivered) OTP session behind.
      await _sendEmail(code: code);
      await _storeOtp(
        sessionId,
        phone: phone,
        code: code,
        expiresAt: expiresAt,
        nextResendAt: now.add(_resendCooldowns.first),
        resendCount: 0,
      );
      return sessionId;
    } on OtpException {
      rethrow;
    } catch (_) {
      throw OtpException('Email could not be sent. Please try again.');
    }
  }

  /// Sends a new OTP for an existing session ([otpId] from [sendOtp]).
  /// The same [otpId] stays valid for [verifyOtp].
  ///
  /// A successful resend:
  /// - generates a brand-new code (the old one becomes invalid),
  /// - resets the wrong-attempt counter,
  /// - resets the expiration to 2 minutes,
  /// - advances the resend cooldown (30 s → 2 min → 5 min) and saves it to
  ///   Firestore so the UI countdown survives app restarts.
  Future<bool> resendOtp({required String otpId}) async {
    try {
      final doc = await _otpCol.doc(otpId).get();
      if (!doc.exists) {
        throw OtpException(
            'Session expired. Please go back and request a new code.');
      }
      final data = doc.data()!;
      final now = DateTime.now();

      final expiresAt = _readTimestamp(data['expiresAt']);
      if (expiresAt == null || now.isAfter(expiresAt)) {
        await _otpCol.doc(otpId).delete();
        throw OtpException(
            'Session expired. Please go back and request a new code.');
      }

      final phone = data['phone'] as String?;
      if (phone == null || phone.isEmpty) {
        throw OtpException(
            'Session expired. Please go back and request a new code.');
      }

      final resendCount = (data['resendCount'] as num?)?.toInt() ?? 0;
      if (resendCount >= _maxResends) {
        throw OtpException(
            'Too many resend attempts. Please try again later.');
      }

      final nextResendAt = _readTimestamp(data['nextResendAt']);
      if (nextResendAt != null && now.isBefore(nextResendAt)) {
        throw OtpException(
            'Please wait a moment before requesting a new code.');
      }

      final newCode = _generateCode();
      await _sendEmail(code: newCode);

      final newResendCount = resendCount + 1;
      final nextCooldown = newResendCount < _resendCooldowns.length
          ? _resendCooldowns[newResendCount]
          : _resendCooldowns.last;

      await _otpCol.doc(otpId).update({
        'otpHash': _hashCode(newCode),
        'expiresAt': now.add(_otpTtl),
        'nextResendAt': now.add(nextCooldown),
        'resendCount': newResendCount,
        'attempts': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on OtpException {
      rethrow;
    } on FirebaseException {
      // The session doc could not be read (expired/missing/permission).
      // That is a stale-session problem, not a delivery problem.
      throw OtpException(
          'Session unavailable. Please go back and request a new code.');
    } catch (_) {
      throw OtpException('Email could not be sent. Please try again.');
    }
  }

  /// Verifies an OTP code against the stored Firestore session.
  ///
  /// [otpId] The session id returned by [sendOtp].
  /// [code] The OTP code entered by the user.
  /// Returns true if the code is valid, false otherwise (wrong code).
  Future<bool> verifyOtp({
    required String otpId,
    required String code,
  }) async {
    try {
      final doc = await _otpCol.doc(otpId).get();
      if (!doc.exists) {
        throw OtpException(
            'Session expired. Please go back and request a new code.');
      }
      final data = doc.data()!;

      final expiresAt = _readTimestamp(data['expiresAt']);
      if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
        await _otpCol.doc(otpId).delete();
        throw OtpException(
            'Session expired. Please go back and request a new code.');
      }

      final attempts = (data['attempts'] as num?)?.toInt() ?? 0;
      if (attempts >= _maxAttempts) {
        await _otpCol.doc(otpId).delete();
        throw OtpException(
            'Too many wrong attempts. Please request a new code.');
      }

      final storedHash = (data['otpHash'] as String?)?.trim() ?? '';
      final match = storedHash.isNotEmpty && storedHash == _hashCode(code.trim());

      if (!match) {
        await _otpCol.doc(otpId).update({
          'attempts': attempts + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return false;
      }

      await _otpCol.doc(otpId).delete();
      return true;
    } on OtpException {
      rethrow;
    } catch (_) {
      throw OtpException(
          'Could not verify the code. Check your internet connection and try again.');
    }
  }

  /// Loads the persisted session state (expiration + resend cooldown + resend
  /// count) so an existing screen can resume its countdown from Firestore
  /// instead of restarting a fresh timer.
  Future<OtpSessionStatus> getOtpStatus({required String otpId}) async {
    final doc = await _otpCol.doc(otpId).get();
    if (!doc.exists) {
      throw OtpException(
          'Session expired. Please go back and request a new code.');
    }
    return _statusFromData(doc.data()!);
  }

  OtpSessionStatus _statusFromData(Map<String, dynamic> data) {
    return OtpSessionStatus(
      expiresAt: _readTimestamp(data['expiresAt']),
      nextResendAt: _readTimestamp(data['nextResendAt']),
      resendCount: (data['resendCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Sends the code through the Brevo Transactional Email API.
  ///
  /// Throws an [OtpException] whenever the email could not be sent (offline,
  /// timeout, Brevo 4xx/5xx). No raw Brevo response is ever exposed.
  Future<void> _sendEmail({required String code}) async {
    final email = _recipientEmail();

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('https://api.brevo.com/v3/smtp/email'),
            headers: {
              'accept': 'application/json',
              'api-key': AppEnv.brevoApiKey,
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'sender': {
                'name': 'Flash Chat',
                'email': 'flashchat.team@gmail.com',
              },
              'to': [
                {'email': email}
              ],
              'subject': 'Your Flash Chat verification code',
              'htmlContent': _htmlContent(code),
              'textContent': _plainTextContent(code),
            }),
          )
          .timeout(_timeout);
    } catch (_) {
      throw OtpException('Email could not be sent. Please try again.');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw OtpException('Email could not be sent. Please try again.');
  }

  /// Clean HTML version of the FlashChat OTP email. The code is visually
  /// prominent and no internal technical information is exposed.
  String _htmlContent(String code) => '''
<!DOCTYPE html>
<html lang="en">
<body style="margin:0; padding:0; background-color:#f4f7fb; font-family:Arial, Helvetica, sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f7fb; padding:24px 0;">
    <tr>
      <td align="center">
        <table width="480" cellpadding="0" cellspacing="0" style="background-color:#ffffff; border-radius:12px; overflow:hidden; border:1px solid #e3ebf6;">
          <tr>
            <td style="background-color:#03a9f4; padding:22px; text-align:center;">
              <span style="color:#ffffff; font-size:22px; font-weight:bold;">Flash Chat</span>
            </td>
          </tr>
          <tr>
            <td style="padding:32px 28px;">
              <p style="margin:0 0 16px; color:#333333; font-size:15px; line-height:1.6;">Hello,</p>
              <p style="margin:0 0 22px; color:#333333; font-size:15px; line-height:1.6;">Your Flash Chat verification code is:</p>
              <table width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td align="center" style="background-color:#eaf6ff; border-radius:8px; padding:18px;">
                    <span style="font-size:34px; font-weight:bold; letter-spacing:8px; color:#03a9f4;">$code</span>
                  </td>
                </tr>
              </table>
              <p style="margin:24px 0 6px; color:#555555; font-size:13px; line-height:1.5;">This code expires in 2 minutes.</p>
              <p style="margin:0 0 24px; color:#555555; font-size:13px; line-height:1.5;">If you didn't request this code, you can safely ignore this email.</p>
              <p style="margin:0; color:#999999; font-size:12px; line-height:1.5;">Thanks,<br/>Flash Chat app team</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
''';

  /// Plain-text fallback version of the same email.
  String _plainTextContent(String code) => '''
Hello,

Your Flash Chat verification code is:

$code

This code expires in 2 minutes.

If you didn't request this code, you can safely ignore this email.

Thanks,
Flash Chat app team
''';

  /// Stores (or overwrites) an OTP session in Firestore. The doc is keyed by
  /// [otpId] so a local copy of the id lets a killed app resume verification.
  /// The doc is bound to the signed-in creator's uid so Firestore rules can
  /// restrict read/update/delete to that same account (prevent signup-hijack).
  Future<void> _storeOtp(
    String otpId, {
    required String phone,
    required String code,
    required DateTime expiresAt,
    required DateTime nextResendAt,
    required int resendCount,
  }) async {
    await _otpCol.doc(otpId).set({
      'uid': FirebaseAuth.instance.currentUser?.uid ?? '',
      'phone': phone,
      'otpHash': _hashCode(code),
      'expiresAt': expiresAt,
      'nextResendAt': nextResendAt,
      'resendCount': resendCount,
      'attempts': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reads a timestamp field that may be a DateTime or a Firestore Timestamp.
  DateTime? _readTimestamp(dynamic value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    return null;
  }

  /// Helper method to convert error responses to user-friendly messages.
  static String otpErrorMessage(dynamic error) {
    if (error is OtpException) {
      return error.message;
    } else if (error is String) {
      return error;
    } else {
      return 'An error occurred. Please try again.';
    }
  }
}