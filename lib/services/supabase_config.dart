import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'diagnostic_log_service.dart';

abstract interface class SupabaseAuthAdapter {
  String? get currentUserId;
  bool get hasSession;
  bool get hasValidSession;
  Future<String?> refreshSession();
  Future<String?> signInAnonymously();
}

class _SupabaseClientAuthAdapter implements SupabaseAuthAdapter {
  final SupabaseClient client;
  _SupabaseClientAuthAdapter(this.client);

  @override
  String? get currentUserId => client.auth.currentUser?.id;

  @override
  bool get hasSession => client.auth.currentSession != null;

  @override
  bool get hasValidSession {
    final session = client.auth.currentSession;
    return session != null && !session.isExpired;
  }

  @override
  Future<String?> refreshSession() async {
    final response = await client.auth.refreshSession();
    return response.session?.user.id;
  }

  @override
  Future<String?> signInAnonymously() async {
    final response = await client.auth.signInAnonymously();
    return response.session?.user.id;
  }
}

class SupabaseConfig {
  static const String url = 'https://cplqrewuoltiechxxtjk.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNwbHFyZXd1b2x0aWVjaHh4dGprIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEwNDg0MDMsImV4cCI6MjA5NjYyNDQwM30.iDypdQt1RpcpffUvtrg_Ykr2tJwdG3CasoHmruTbS-A';

  static SupabaseClient get client => Supabase.instance.client;
  static Future<bool>? _authenticationInFlight;
  static SupabaseAuthAdapter? _testAuthAdapter;
  static String? _knownUserId;
  static Duration _authWaitTimeout = const Duration(seconds: 15);
  static const _identityMarker = 'supabase_last_authenticated_user_id';
  static const _pendingApprovalMarker = 'supabase_pending_identity_approval';
  static bool _accountOperationActive = false;
  static bool _pendingApproval = false;
  static bool _identityStateLoaded = false;
  static String? _pendingEmail;
  static String? _pendingOriginalId;
  static String? _pendingSourceId;
  static bool _verificationStarted = false;
  static Future<void>? _identityStateLoad;
  static SupabaseAuthAdapter get _adapter =>
      _testAuthAdapter ?? _SupabaseClientAuthAdapter(client);

  static bool get isAuthenticated {
    return hasValidSession;
  }

  static bool get hasValidSession {
    try {
      return _identityStateLoaded &&
          !_accountOperationActive &&
          !_pendingApproval &&
          _knownUserId != null &&
          _adapter.hasValidSession &&
          _adapter.currentUserId == _knownUserId;
    } catch (_) {
      return false;
    }
  }

  static bool get rawHasValidSession {
    try {
      return _adapter.hasValidSession;
    } catch (_) {
      return false;
    }
  }

  static String? get currentUserIdOrNull {
    try {
      return hasValidSession ? _adapter.currentUserId : null;
    } catch (_) {
      return null;
    }
  }

  static String get currentUserId =>
      currentUserIdOrNull ?? (throw StateError('Not authenticated'));

  static Future<void> init() async {
    try {
      await Supabase.initialize(
        url: url,
        publishableKey: anonKey,
        // Email verification must pass through the explicit upload-consent
        // transaction; a received link must not silently replace the identity.
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      );
      await loadIdentityState();
    } catch (e) {
      debugPrint('[SupabaseConfig] Initialization error: $e');
    }
  }

  static Future<bool> signInAnonymously() {
    if (_accountOperationActive || _pendingApproval) {
      return Future<bool>.value(false);
    }
    final existing = _authenticationInFlight;
    final future = existing ?? _ensureAuthenticated();
    if (existing == null) {
      _authenticationInFlight = future;
      void release() {
        if (identical(_authenticationInFlight, future)) {
          _authenticationInFlight = null;
        }
      }

      unawaited(
        future.then<void>(
          (_) => release(),
          onError: (Object error, StackTrace stack) => release(),
        ),
      );
    }
    // A caller may stop waiting, but the SDK operation is not cancelled by
    // Future.timeout. Keep the underlying flight until it really settles.
    return future.timeout(
      _authWaitTimeout,
      onTimeout: () {
        unawaited(
          DiagnosticLogService.instance.record('cloud', 'auth_wait_timeout'),
        );
        return false;
      },
    );
  }

  static Future<bool> ensureAuthenticated() => signInAnonymously();

  static Future<bool> _ensureAuthenticated() async {
    try {
      await loadIdentityState();
      if (_accountOperationActive || _pendingApproval) return false;
      final adapter = _adapter;
      if (adapter.hasValidSession) {
        await _rememberIdentity(adapter.currentUserId);
        unawaited(DiagnosticLogService.instance.record('cloud', 'auth_valid'));
        return true;
      }

      // A present session belongs to an existing identity. Never replace it
      // with a fresh anonymous account when refresh fails.
      if (adapter.hasSession) {
        final originalUserId = adapter.currentUserId;
        if (originalUserId == null || originalUserId.isEmpty) return false;
        await _rememberIdentity(originalUserId);
        try {
          final refreshedUserId = await adapter.refreshSession();
          if (refreshedUserId == originalUserId &&
              adapter.currentUserId == originalUserId &&
              adapter.hasValidSession) {
            await _rememberIdentity(refreshedUserId);
            unawaited(
              DiagnosticLogService.instance.record('cloud', 'auth_refreshed'),
            );
            return true;
          }
        } catch (e) {
          debugPrint(
            '[Supabase Auth] Session refresh failed: ${e.runtimeType}',
          );
        }
        debugPrint(
          '[Supabase Auth] Existing identity blocked; no replacement anonymous user.',
        );
        unawaited(
          DiagnosticLogService.instance.record('cloud', 'auth_refresh_blocked'),
        );
        return false;
      }

      final identityState = await _hasPersistedIdentityOrLocalHistory();
      if (identityState != false) {
        debugPrint(
          '[Supabase Auth] Authentication blocked; restore the original identity.',
        );
        unawaited(
          DiagnosticLogService.instance.record('cloud', 'auth_restore_blocked'),
        );
        return false;
      }

      final userId = await adapter.signInAnonymously();
      if (userId == null ||
          userId.isEmpty ||
          !adapter.hasValidSession ||
          adapter.currentUserId != userId) {
        return false;
      }
      await _rememberIdentity(userId);
      unawaited(
        DiagnosticLogService.instance.record('cloud', 'auth_anonymous_created'),
      );
      return true;
    } catch (e) {
      debugPrint('[Supabase Auth] Authentication failed: ${e.runtimeType}');
      return false;
    }
  }

  static Future<void> loadIdentityState() {
    final existing = _identityStateLoad;
    if (existing != null) return existing;
    final future = SharedPreferences.getInstance().then((prefs) {
      _knownUserId ??= prefs.getString(_identityMarker);
      final rawPending = prefs.get(_pendingApprovalMarker);
      if (rawPending != null) {
        // Set the gate before parsing: damaged/legacy approval state must not
        // silently approve an SDK session left by an interrupted verification.
        _pendingApproval = true;
        if (rawPending is String) {
          final data = jsonDecode(rawPending) as Map;
          _pendingEmail = data['email'] as String?;
          _pendingOriginalId = data['originalUserId'] as String?;
          _pendingSourceId = data['sourceUserId'] as String?;
          _verificationStarted = data['verificationStarted'] == true;
        }
      }
      _identityStateLoaded = true;
    });
    _identityStateLoad = future;
    return future;
  }

  static String? get knownUserId => _knownUserId;
  static String? get pendingApprovalEmail => _pendingEmail;
  static String? get pendingApprovalOriginalId => _pendingOriginalId;
  static bool get authTransactionActive =>
      _accountOperationActive || _pendingApproval;
  static bool get hasPendingApproval => _pendingApproval;
  static bool get verificationStarted => _verificationStarted;

  /// Owns the entire underlying SDK operation, not a caller's timeout wrapper.
  /// Reserving this synchronously stops new automatic recovery; an older
  /// recovery is awaited before any interactive SDK call can start.
  static Future<T> runAccountOperation<T>(
    Future<T> Function() operation,
  ) async {
    if (_accountOperationActive) {
      throw StateError('Account operation in progress');
    }
    _accountOperationActive = true;
    try {
      await loadIdentityState();
      await _authenticationInFlight;
      if (!_pendingApproval &&
          _adapter.hasValidSession &&
          (_knownUserId == null || _adapter.currentUserId == _knownUserId)) {
        await _rememberIdentity(_adapter.currentUserId);
      }
      return await operation();
    } finally {
      _accountOperationActive = false;
    }
  }

  static Future<bool> beginAuthTransaction({
    required String email,
    String? originalUserId,
  }) async {
    if (!_accountOperationActive) return false;
    if (_pendingApproval) {
      if (_pendingEmail != email || _pendingOriginalId != originalUserId) {
        return false;
      }
      return _persistPendingApproval();
    }
    _pendingApproval = true;
    _pendingEmail = email;
    _pendingOriginalId = originalUserId;
    _pendingSourceId = _adapter.currentUserId;
    _verificationStarted = false;
    return _persistPendingApproval();
  }

  static Future<bool> _persistPendingApproval() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(
        _pendingApprovalMarker,
        jsonEncode(<String, Object?>{
          'email': _pendingEmail,
          'originalUserId': _pendingOriginalId,
          'sourceUserId': _pendingSourceId,
          'verificationStarted': _verificationStarted,
        }),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> beginAccountVerification() async {
    if (!_accountOperationActive ||
        !_pendingApproval ||
        _pendingEmail == null) {
      return false;
    }
    _verificationStarted = true;
    // This must succeed BEFORE verifyOTP can replace the SDK's saved session.
    return _persistPendingApproval();
  }

  static Future<bool> approveAuthTransaction({
    required String email,
    required String userId,
    required bool allowLocalUpload,
    required bool Function() identityStillVerified,
  }) async {
    if (!allowLocalUpload ||
        !_accountOperationActive ||
        !_pendingApproval ||
        !_verificationStarted ||
        _pendingEmail != email ||
        userId.isEmpty ||
        !_adapter.hasValidSession ||
        _adapter.currentUserId != userId ||
        (_pendingOriginalId != null && _pendingOriginalId != userId) ||
        !identityStillVerified()) {
      return false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_identityMarker, userId)) return false;
      if (!identityStillVerified() ||
          !_adapter.hasValidSession ||
          _adapter.currentUserId != userId) {
        return false;
      }
      if (!await prefs.remove(_pendingApprovalMarker)) return false;
      _knownUserId = userId;
      _pendingEmail = null;
      _pendingOriginalId = null;
      _pendingSourceId = null;
      _pendingApproval = false;
      _verificationStarted = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> cancelUnverifiedAccountRequest() async {
    if (!_accountOperationActive ||
        !_pendingApproval ||
        _verificationStarted ||
        _adapter.currentUserId != _pendingSourceId) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_pendingApprovalMarker)) return false;
    _pendingApproval = false;
    _pendingEmail = null;
    _pendingOriginalId = null;
    _pendingSourceId = null;
    return true;
  }

  @visibleForTesting
  static void resetIdentityStateForTesting() {
    _knownUserId = null;
    _pendingEmail = null;
    _pendingOriginalId = null;
    _pendingSourceId = null;
    _pendingApproval = false;
    _verificationStarted = false;
    _accountOperationActive = false;
    _identityStateLoaded = false;
    _identityStateLoad = null;
  }

  static Future<void> _rememberIdentity(String? userId) async {
    if (userId == null || userId.isEmpty) {
      throw StateError('Missing cloud identity');
    }
    final prefs = await SharedPreferences.getInstance();
    final previous = _knownUserId ?? prefs.getString(_identityMarker);
    if (previous != null && previous != userId) {
      _knownUserId = previous;
      unawaited(
        DiagnosticLogService.instance.record('cloud', 'auth_identity_mismatch'),
      );
      throw StateError('Cloud identity changed; explicit recovery required');
    }
    if (!await prefs.setString(_identityMarker, userId)) {
      throw StateError('Could not persist original cloud identity');
    }
    _knownUserId = userId;
  }

  static Future<bool?> _hasPersistedIdentityOrLocalHistory() async {
    if (_knownUserId != null) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getString(_identityMarker) ?? '').isNotEmpty) return true;
      final directory = await getApplicationDocumentsDirectory();
      await for (final entity in directory.list()) {
        if (entity is File && isUserHistoryFile(entity.path)) return true;
      }
    } catch (_) {
      return null;
    }
    return false;
  }

  @visibleForTesting
  static bool isUserHistoryFile(String path) {
    final name = path.split('/').last;
    return (name.endsWith('.md') &&
            (name.startsWith('Jeff_') || name.startsWith('jeff_notes_'))) ||
        (name.startsWith('shadow_draft_') && name.endsWith('.json')) ||
        RegExp(r'^rec_\d+\.wav$').hasMatch(name);
  }

  @visibleForTesting
  static void setAuthAdapterForTesting(
    SupabaseAuthAdapter? adapter, {
    Duration waitTimeout = const Duration(seconds: 15),
    bool resetState = true,
  }) {
    _testAuthAdapter = adapter;
    if (resetState) {
      _authenticationInFlight = null;
      resetIdentityStateForTesting();
    }
    _authWaitTimeout = waitTimeout;
  }
}
