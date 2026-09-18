import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Typed exception surfaced to UI layer.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.fieldErrors});
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? fieldErrors;

  @override
  String toString() => message;
}

/// Maps Supabase/Postgrest errors to the friendly [ApiException].
ApiException mapSupabaseError(Object e) {
  if (e is ApiException) return e;
  if (e is PostgrestException) {
    // friendly messages for common constraint/auth failures
    var msg = e.message;
    if (e.code == '23505' || msg.contains('duplicate key')) {
      msg = 'That record already exists.';
    } else if (e.code == '42501' || msg.contains('row-level security')) {
      msg = 'You do not have permission for this action.';
    } else if (e.code == 'PGRST301' || msg.contains('JWT')) {
      msg = 'Session expired. Please sign in again.';
    }
    return ApiException(msg, statusCode: int.tryParse(e.code ?? '') ?? 400);
  }
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    var msg = e.message;
    if (m.contains('invalid login')) {
      msg = 'Wrong phone number or password.';
    } else if (m.contains('already registered')) {
      msg = 'An account with this phone already exists. Try logging in.';
    } else if (m.contains('password should be')) {
      msg = 'Password should be at least 6 characters.';
    }
    return ApiException(msg, statusCode: e.statusCode != null ? int.tryParse(e.statusCode!) ?? 400 : 400);
  }
  if (e is FormatException) return ApiException(e.message);
  return ApiException('Network error — check your connection.',
      statusCode: 0);
}

/// Session/token compatibility layer for the Supabase backend.
///
/// The old Dio/JWT client stored access+refresh tokens manually; Supabase
/// manages session persistence itself, so these methods either no-op or
/// delegate to the Supabase auth session. Screens and providers keep using
/// the same call sites (loadTokens / hasTokens / clearTokens).
class ApiClient {
  ApiClient._();
  static final ApiClient I = ApiClient._();

  SupabaseClient get _sb => Supabase.instance.client;

  bool get hasTokens => _sb.auth.currentSession != null;

  Future<void> loadTokens() async {
    // Supabase restores the persisted session during Supabase.initialize().
    // Give the recovery a beat on cold web boots.
    for (var i = 0; i < 12 && _sb.auth.currentSession == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> saveTokens(String access, String refresh) async {
    // no-op — kept for call-site compatibility
  }

  Future<void> clearTokens() async {
    try {
      await _sb.auth.signOut();
    } catch (_) {}
  }

  // keep debug import used (web boots log connection issues)
  void debugLog(String msg) {
    if (kDebugMode) debugPrint('[velo] $msg');
  }
}
