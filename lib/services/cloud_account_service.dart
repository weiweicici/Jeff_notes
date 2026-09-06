import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'diagnostic_log_service.dart';
import 'supabase_config.dart';

enum CloudAccountAction {
  bindAnonymousEmail,
  signInExistingEmail,
  verifyEmailChange,
  verifyEmailSignIn,
}

class CloudAccountSnapshot {
  final String? userId, email, knownUserId, pendingEmail, errorMessage;
  final bool isAnonymous, valid, hasKnownIdentity, authInProgress;
  final CloudAccountAction? pendingAction;
  final DateTime? resendAvailableAt;
  final bool canCancelRequest;
  const CloudAccountSnapshot({
    this.userId,
    this.email,
    this.knownUserId,
    this.pendingEmail,
    this.errorMessage,
    this.isAnonymous = false,
    this.valid = false,
    this.hasKnownIdentity = false,
    this.authInProgress = false,
    this.pendingAction,
    this.resendAvailableAt,
    this.canCancelRequest = false,
  });
}

/// Tests replace only the SDK boundary, never the production approval gate.
abstract interface class CloudAccountAuthAdapter {
  String? get userId;
  String? get email;
  bool get isAnonymous;
  bool get emailConfirmed;
  bool get hasValidSession;
  Future<void> updateEmail(String email);
  Future<void> signInExistingEmail(String email);
  Future<void> verifyEmailChange(String email, String token);
  Future<void> verifyEmailSignIn(String email, String token);
}

class _SupabaseCloudAccountAuthAdapter implements CloudAccountAuthAdapter {
  SupabaseClient get _client => SupabaseConfig.client;
  @override
  String? get userId => _client.auth.currentUser?.id;
  @override
  String? get email => _client.auth.currentUser?.email;
  @override
  bool get isAnonymous => _client.auth.currentUser?.isAnonymous ?? false;
  @override
  bool get emailConfirmed => _client.auth.currentUser?.emailConfirmedAt != null;
  @override
  bool get hasValidSession {
    final session = _client.auth.currentSession;
    return session != null && !session.isExpired;
  }

  @override
  Future<void> updateEmail(String email) async {
    await _client.auth.updateUser(UserAttributes(email: email));
  }

  @override
  Future<void> signInExistingEmail(String email) async {
    await _client.auth.signInWithOtp(email: email, shouldCreateUser: false);
  }

  @override
  Future<void> verifyEmailChange(String email, String token) async {
    await _client.auth.verifyOTP(
      type: OtpType.emailChange,
      email: email,
      token: token,
    );
  }

  @override
  Future<void> verifyEmailSignIn(String email, String token) async {
    await _client.auth.verifyOTP(
      type: OtpType.email,
      email: email,
      token: token,
    );
  }
}

class _AccountTestRecoveryAdapter implements SupabaseAuthAdapter {
  final CloudAccountAuthAdapter account;
  _AccountTestRecoveryAdapter(this.account);
  @override
  String? get currentUserId => account.userId;
  @override
  bool get hasSession => account.userId != null;
  @override
  bool get hasValidSession => account.hasValidSession;
  @override
  Future<String?> refreshSession() async =>
      hasValidSession ? currentUserId : null;
  @override
  Future<String?> signInAnonymously() async =>
      throw StateError('No anonymous registration in account tests');
}

class CloudAccountService extends ChangeNotifier {
  static final CloudAccountService instance = CloudAccountService._();
  final CloudAccountAuthAdapter _adapter;
  final Duration _waitTimeout, _resendCooldown;
  String? _errorMessage;
  bool _authInProgress = false, _disposed = false;
  bool _committingApproval = false;
  DateTime? _resendAvailableAt;
  CloudAccountService._()
    : _adapter = _SupabaseCloudAccountAuthAdapter(),
      _waitTimeout = const Duration(seconds: 30),
      _resendCooldown = const Duration(seconds: 60);

  @visibleForTesting
  CloudAccountService.forTesting(
    CloudAccountAuthAdapter adapter, {
    Duration waitTimeout = const Duration(seconds: 30),
    Duration resendCooldown = const Duration(seconds: 60),
    bool installRecoveryAdapter = true,
  }) : _adapter = adapter,
       _waitTimeout = waitTimeout,
       _resendCooldown = resendCooldown {
    if (installRecoveryAdapter) {
      // This constructor is itself testing-only; use the same global gate.
      // ignore: invalid_use_of_visible_for_testing_member
      SupabaseConfig.setAuthAdapterForTesting(
        _AccountTestRecoveryAdapter(adapter),
        resetState: false,
      );
    }
  }

  CloudAccountSnapshot get snapshot {
    String? userId, email;
    var anonymous = false;
    try {
      userId = _adapter.userId;
      email = _adapter.email;
      anonymous = _adapter.isAnonymous;
    } catch (_) {
      /* SDK may be uninitialized in an offline/widget run. */
    }
    final pendingEmail = SupabaseConfig.pendingApprovalEmail;
    return CloudAccountSnapshot(
      userId: userId,
      email: email,
      isAnonymous: anonymous,
      valid: !_authInProgress && SupabaseConfig.hasValidSession,
      knownUserId: SupabaseConfig.knownUserId,
      hasKnownIdentity: SupabaseConfig.knownUserId != null,
      authInProgress: _authInProgress,
      pendingEmail: pendingEmail,
      pendingAction: pendingEmail == null
          ? null
          : SupabaseConfig.pendingApprovalOriginalId == null
          ? CloudAccountAction.verifyEmailSignIn
          : CloudAccountAction.verifyEmailChange,
      errorMessage: _errorMessage,
      resendAvailableAt: _resendAvailableAt,
      canCancelRequest:
          pendingEmail != null && !SupabaseConfig.verificationStarted,
    );
  }

  Future<void> refreshStatus() async {
    try {
      await SupabaseConfig.loadIdentityState();
      // Opening account settings must not create a fresh anonymous account.
      // Only attempt restoration when the SDK still has an existing user.
      if (!SupabaseConfig.authTransactionActive &&
          !_authInProgress &&
          _adapter.userId != null) {
        await SupabaseConfig.ensureAuthenticated();
      }
    } catch (_) {
      _errorMessage = '无法读取原云账号状态；本地文件未改动';
    }
    _notify();
  }

  Future<bool> requestBind(String email) => _request(email, bind: true);
  Future<bool> requestSignIn(String email) => _request(email, bind: false);
  Future<bool> _request(String email, {required bool bind}) async {
    final normalized = _normalizeEmail(email);
    if (normalized == null) return _fail('请输入有效邮箱地址');
    if (_resendAvailableAt != null &&
        DateTime.now().isBefore(_resendAvailableAt!)) {
      return _fail('邮件请求间隔至少一分钟，请稍后重试');
    }
    return _run((active) async {
      final pending = SupabaseConfig.hasPendingApproval;
      final originalId = pending
          ? SupabaseConfig.pendingApprovalOriginalId
          : bind
          ? _adapter.userId
          : null;
      if (pending &&
          (SupabaseConfig.pendingApprovalEmail != normalized ||
              (originalId != null) != bind)) {
        return _fail('请先完成当前邮箱验证，或取消尚未验证的请求');
      }
      if (bind) {
        if (!_adapter.hasValidSession ||
            originalId == null ||
            _adapter.userId != originalId ||
            (!pending && originalId != SupabaseConfig.knownUserId) ||
            (!pending && !_adapter.isAnonymous)) {
          return _fail('原匿名云会话无效，请先恢复 iPad 上的原账号');
        }
      } else if (!pending &&
          _adapter.hasValidSession &&
          _adapter.userId == SupabaseConfig.knownUserId) {
        return _fail('当前已有有效账号，不能直接替换');
      }
      if (!active()) return false;
      if (!await SupabaseConfig.beginAuthTransaction(
        email: normalized,
        originalUserId: originalId,
      )) {
        return _fail('无法安全保存认证请求；本地笔记尚未上传');
      }
      if (!active()) return false;
      _resendAvailableAt = DateTime.now().add(_resendCooldown);
      if (bind) {
        await _adapter.updateEmail(normalized);
      } else {
        await _adapter.signInExistingEmail(normalized);
      }
      return active();
    }, failureMessage: '邮件请求失败：请检查网络、发送限制及后台邮箱设置；首次使用请先在 iPad 绑定');
  }

  Future<bool> verify({
    required String code,
    required bool allowLocalUpload,
  }) async {
    if (!allowLocalUpload) return _fail('请先明确同意将待传笔记归入此邮箱');
    if (!RegExp(r'^\d{6,10}$').hasMatch(code)) return _fail('验证码应为 6 到 10 位数字');
    return _run((active) async {
      final email = SupabaseConfig.pendingApprovalEmail;
      final originalId = SupabaseConfig.pendingApprovalOriginalId;
      if (email == null) return _fail('没有待验证的邮箱请求');
      if (!await SupabaseConfig.beginAccountVerification() || !active()) {
        return _fail('无法安全保存验证状态，待传笔记仍留在本机');
      }
      if (originalId != null) {
        await _adapter.verifyEmailChange(email, code);
      } else {
        await _adapter.verifyEmailSignIn(email, code);
      }
      final userId = _adapter.userId;
      bool verified() =>
          active() &&
          userId != null &&
          userId.isNotEmpty &&
          _adapter.userId == userId &&
          _adapter.hasValidSession &&
          !_adapter.isAnonymous &&
          _adapter.emailConfirmed &&
          _adapter.email?.trim().toLowerCase() == email &&
          (originalId == null || originalId == userId);
      if (!verified()) return _fail('身份验证未通过，上传仍暂停；请重新获取验证码');
      // Once local commit starts, report its actual result. A timeout cannot
      // race the final durable marker removal and report a false failure.
      _committingApproval = true;
      final approved = await SupabaseConfig.approveAuthTransaction(
        email: email,
        userId: userId!,
        allowLocalUpload: allowLocalUpload,
        identityStillVerified: verified,
      );
      if (!approved) return _fail('未能安全保存云账号，上传仍暂停；请重试验证');
      unawaited(
        DiagnosticLogService.instance.record('cloud', 'account_approved'),
      );
      return true;
    }, failureMessage: '验证码验证失败，请检查验证码、网络或重新获取验证码');
  }

  Future<bool> cancelPendingRequest() => _run((active) async {
    final cancelled = await SupabaseConfig.cancelUnverifiedAccountRequest();
    return cancelled || _fail('已开始身份验证，不能取消保护；请完成原邮箱验证');
  }, failureMessage: '取消失败，原账号和本地文件未改动');

  Future<bool> _run(
    Future<bool> Function(bool Function() active) operation, {
    required String failureMessage,
  }) {
    if (_authInProgress) return Future.value(_fail('认证正在进行，请稍候'));
    _authInProgress = true;
    _committingApproval = false;
    _errorMessage = null;
    var expired = false;
    _notify();
    final raw =
        SupabaseConfig.runAccountOperation(() async {
              if (expired) return false;
              return operation(() => !expired);
            })
            .catchError((Object error) {
              _errorMessage = failureMessage;
              unawaited(
                DiagnosticLogService.instance.record(
                  'cloud',
                  'account_request_failed',
                  fields: {'errorType': error.runtimeType},
                ),
              );
              return false;
            })
            .whenComplete(() {
              _authInProgress = false;
              _notify();
            });
    // A caller timeout cannot cancel the SDK Future or release its mutex.
    // Late SDK responses remain quarantined instead of silently approving.
    return raw.timeout(
      _waitTimeout,
      onTimeout: () {
        if (_committingApproval) return raw;
        expired = true;
        _errorMessage = '认证等待超时，上传仍暂停；请求结束后可重试';
        _notify();
        return false;
      },
    );
  }

  void clearError() {
    _errorMessage = null;
    _notify();
  }

  bool _fail(String message) {
    _errorMessage = message;
    _notify();
    return false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static String? _normalizeEmail(String value) {
    final normalized = value.trim().toLowerCase();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)
        ? normalized
        : null;
  }
}
