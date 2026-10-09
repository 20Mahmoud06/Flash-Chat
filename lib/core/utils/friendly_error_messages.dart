import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

/// Maps an exception thrown during a user-facing operation to a clear,
/// human-readable message the average user can act on. Raw platform or
/// library error text is never shown.
///
/// Known failure types get a message that matches the problem (wrong
/// password, email already in use, no internet, etc.). Friendly messages
/// that the app itself throws as plain [Exception]s are preserved, and
/// anything else falls back to [fallback].
String friendlyErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Incorrect password. Please try again.';
      case 'user-not-found':
        return 'No account was found with this email. Please sign up first.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'email-already-in-use':
        return 'This email is already in use. Try signing in instead.';
      case 'weak-password':
        return 'Your password is too weak. Please use at least 6 characters.';
      case 'network-request-failed':
        return 'No internet connection. Please check your connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'requires-recent-login':
        return 'For security, please sign in again and retry.';
      case 'operation-not-allowed':
        return 'This sign-in method is not available right now.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email. Try a different sign-in method.';
      case 'invalid-verification-code':
        return 'The verification code is incorrect. Please try again.';
      case 'provider-already-linked':
        return 'This sign-in method is already linked to your account.';
      default:
        return 'Something went wrong during sign in. Please try again.';
    }
  }

  if (error is FirebaseException) {
    switch (error.code) {
      case 'network-request-failed':
      case 'unavailable':
        return 'No internet connection. Please check your connection and try again.';
      case 'permission-denied':
        return 'You do not have permission to perform this action.';
      case 'not-found':
        return 'This could not be found. It may have been deleted.';
      case 'already-exists':
        return 'This already exists. Please try something different.';
      case 'resource-exhausted':
        return 'Too many requests. Please try again later.';
      case 'deadline-exceeded':
        return 'The request took too long. Please try again.';
      case 'aborted':
      case 'failed-precondition':
        return 'This could not be completed right now. Please try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  if (error is SocketException) {
    return 'No internet connection. Please check your connection and try again.';
  }

  if (error is TimeoutException) {
    return 'The request took too long. Please check your connection and try again.';
  }

  // Friendly messages thrown deliberately by app code (e.g.
  // "This phone number is already registered.") are safe to show as-is.
  if (error is Exception) {
    final message = error.toString();
    const prefix = 'Exception: ';
    final clean =
        message.startsWith(prefix) ? message.substring(prefix.length) : message;
    if (clean.trim().isNotEmpty) return clean;
  }

  return fallback;
}