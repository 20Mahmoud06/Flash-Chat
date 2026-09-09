import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flash_chat_app/services/otp/otp_notification_service.dart';

/// Exception thrown when OTP operations fail.
class OtpException implements Exception {
  final String message;
  OtpException(this.message);

  @override
  String toString() => message;
}

/// How long an OTP stays valid. Telegram-style: short, so users request a
/// fresh code quickly if they miss the window.
const Duration _otpTtl = Duration(minutes: 2);

/// OTP length delivered to the user.
const int _otpLength = 6;

/// Service for handling OTP (One-Time Password) operations.
///
/// This service:
/// 1. Generates a 6-digit code locally.
/// 2. Delivers it as a LOCAL notification on the same device (see
///    [OtpNotificationService]) instead of a remote SMS.
/// 3. Persists the code + expiry in Firestore (keyed by the session id), so
///    verification still works even if the app is killed and reopened.
///
/// Flow:
/// 1. [sendOtp] generates a code, shows the local notification, stores it,
///    returns an [otpId].
/// 2. The user reads the code from the notification.
/// 3. [verifyOtp] looks up the code in Firestore and compares.
/// 4. [resendOtp] generates a fresh code, shows it, and updates the stored one.
class OtpService {
  /// Firestore collection that holds active OTP sessions.
  static const String _collection = 'otp_verifications';

  /// Max wrong attempts before the code is invalidated.
  static const int _maxAttempts = 5;

  static const Duration _timeout = Duration(seconds: 20);

  final Random _rng = Random.secure();

  CollectionReference<Map<String, dynamic>> get _otpCol =>
      FirebaseFirestore.instance.collection(_collection);

  /// Generates a cryptographically random OTP string of [_otpLength] digits.
  String _generateCode() {
    final max = pow(10, _otpLength).toInt();
    final min = pow(10, _otpLength - 1).toInt();
    final raw = _rng.nextInt(max - min) + min;
    return raw.toString();
  }

  /// Generates a unique session id. Combined with the phone number, this is
  /// stored in Firestore and persisted locally so a killed app can resume.
  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final random = _rng.nextInt(0xFFFFFF).toRadixString(36).padLeft(6, '0');
    return 'otp_${timestamp}_$random';
  }

  /// Sends an OTP code to the specified phone number.
  ///
  /// [phone] The phone number in E.164 format (e.g., +201001234567).
  /// Returns a session id that must be passed to [verifyOtp] or [resendOtp].
  Future<String> sendOtp({required String phone}) async {
    final code = _generateCode();
    final sessionId = _generateSessionId();
    final expiresAt = DateTime.now().add(_otpTtl);

    try {
      await _deliverOtpCode(phone: phone, code: code);
      await _storeOtp(sessionId, phone, code, expiresAt);
      debugPrint('[OTP] Session started: $sessionId, expires: $expiresAt');
      return sessionId;
    } catch (e) {
      debugPrint('[OTP] Send error: $e');
      if (e is OtpException) rethrow;
      throw OtpException(
          'Could not send the code. Check your internet connection and try again.');
    }
  }

  /// Sends a new OTP for an existing session ([otpId] from [sendOtp]).
  /// The same [otpId] stays valid for [verifyOtp].
  Future<bool> resendOtp({required String otpId}) async {
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

      final phone = data['phone'] as String?;
      if (phone == null || phone.isEmpty) {
        throw OtpException(
            'Session expired. Please go back and request a new code.');
      }

      final newCode = _generateCode();
      final newExpiresAt = DateTime.now().add(_otpTtl);
      await _deliverOtpCode(phone: phone, code: newCode);

      await _otpCol.doc(otpId).update({
        'code': newCode,
        'expiresAt': newExpiresAt,
        'attempts': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('[OTP] Resend error: $e');
      if (e is OtpException) rethrow;
      throw OtpException(
          'Could not resend the code. Check your internet connection and try again.');
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
        debugPrint('[OTP] Session not found: $otpId');
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

      debugPrint('[OTP] Verifying session: $otpId (attempt $attempts)');
      final storedCode = (data['code'] as String?)?.trim() ?? '';
      final match = storedCode == code.trim();

      if (!match) {
        await _otpCol.doc(otpId).update({
          'attempts': attempts + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return false;
      }

      await _otpCol.doc(otpId).delete();
      return true;
    } catch (e) {
      debugPrint('[OTP] Verify error: $e');
      if (e is OtpException) rethrow;
      throw OtpException(
          'Could not verify the code. Check your internet connection and try again.');
    }
  }

  /// Delivers the OTP to the user as a local notification on this device.
  /// Throws an [OtpException] if the notification could not be delivered.
  Future<void> _deliverOtpCode({
    required String phone,
    required String code,
  }) async {
    debugPrint('[OTP] Showing local OTP notification (phone: $phone)');
    await _deliverOtp(code: code).timeout(_timeout);
  }

  /// Shows the OTP via [OtpNotificationService] and throws an
  /// [OtpException] when delivery fails.
  Future<void> _deliverOtp({required String code}) async {
    final delivered =
        await OtpNotificationService.instance.showOtp(code: code);
    if (!delivered) {
      throw OtpException(
          'Could not show the verification code. Please enable notifications for this app and try again.');
    }
  }

  /// Stores (or overwrites) an OTP session in Firestore. The doc is keyed by
  /// [otpId] so a local copy of the id let a killed app resume verification.
  Future<void> _storeOtp(
    String otpId,
    String phone,
    String code,
    DateTime expiresAt,
  ) async {
    await _otpCol.doc(otpId).set({
      'phone': phone,
      'code': code,
      'expiresAt': expiresAt,
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
