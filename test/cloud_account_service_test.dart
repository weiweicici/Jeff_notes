import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/cloud_account_service.dart';
import 'package:jeff_notes/services/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAccountAdapter implements CloudAccountAuthAdapter {
  String? user = 'anonymous-id';
  String? mail;
  bool anonymous = true;
  bool valid = true;
  bool confirmed = false;
  String? updatedEmail;
  String? verifiedEmail;
  String? verifiedCode;
  int signInCalls = 0;
  int verifyCalls = 0;
  Completer<void>? verifyGate;
  bool mutateIdentityOnVerify = false;

  @override
  String? get userId => user;
  @override
  String? get email => mail;
  @override
  bool get isAnonymous => anonymous;
  @override
  bool get emailConfirmed => confirmed;
  @override
  bool get hasValidSession => valid;

  @override
  Future<void> updateEmail(String email) async => updatedEmail = email;
  @override
  Future<void> signInExistingEmail(String email) async {
    signInCalls++;
  }

  @override
  Future<void> verifyEmailChange(String email, String token) async {
    verifyCalls++;
    if (verifyGate != null) await verifyGate!.future;
    verifiedEmail = email;
    verifiedCode = token;
    mail = email;
    confirmed = true;
    anonymous = false;
    if (mutateIdentityOnVerify) user = 'different-user';
  }

  @override
  Future<void> verifyEmailSignIn(String email, String token) async {
    verifiedEmail = email;
    verifiedCode = token;
    user = 'existing-user';
    mail = email;
    anonymous = false;
    confirmed = true;
    valid = true;
  }
}

class _RefreshAdapter implements SupabaseAuthAdapter {
  final _FakeAccountAdapter account;
  final Completer<void> gate;
  final void Function() onRefresh;
  _RefreshAdapter(this.account, this.gate, this.onRefresh);
  @override
  String? get currentUserId => account.userId;
  @override
  bool get hasSession => account.userId != null;
  @override
  bool get hasValidSession => account.hasValidSession;
  @override
  Future<String?> refreshSession() async {
    onRefresh();
    await gate.future;
    account.valid = true;
    return account.userId;
  }

  @override
  Future<String?> signInAnonymously() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SupabaseConfig.setAuthAdapterForTesting(null);
  });

  tearDown(() {
    SupabaseConfig.setAuthAdapterForTesting(null);
  });

  test(
    'bind sends email change for original anonymous user and keeps id',
    () async {
      final fake = _FakeAccountAdapter();
      final service = CloudAccountService.forTesting(fake);

      expect(await service.requestBind(' Test@Example.com '), isTrue);
      expect(fake.updatedEmail, 'test@example.com');
      expect(
        await service.verify(code: '123456', allowLocalUpload: true),
        isTrue,
      );
      expect(fake.verifiedEmail, 'test@example.com');
      expect(fake.user, 'anonymous-id');
    },
  );

  test('verification consent false performs no SDK verification', () async {
    final fake = _FakeAccountAdapter();
    final service = CloudAccountService.forTesting(fake);
    expect(await service.requestBind('test@example.com'), isTrue);
    expect(
      await service.verify(code: '123456', allowLocalUpload: false),
      isFalse,
    );
    expect(fake.verifyCalls, 0);
  });

  test(
    'auth gate blocks business session while SDK verification emits events',
    () async {
      final fake = _FakeAccountAdapter()..verifyGate = Completer<void>();
      final service = CloudAccountService.forTesting(fake);
      expect(await service.requestBind('test@example.com'), isTrue);
      final verifying = service.verify(code: '123456', allowLocalUpload: true);
      await Future<void>.delayed(Duration.zero);
      expect(SupabaseConfig.authTransactionActive, isTrue);
      expect(SupabaseConfig.hasValidSession, isFalse);
      fake.verifyGate!.complete();
      expect(await verifying, isTrue);
    },
  );

  test(
    'changed identity during binding verification remains quarantined',
    () async {
      final fake = _FakeAccountAdapter()..mutateIdentityOnVerify = true;
      final service = CloudAccountService.forTesting(fake);
      expect(await service.requestBind('test@example.com'), isTrue);
      expect(
        await service.verify(code: '123456', allowLocalUpload: true),
        isFalse,
      );
      expect(SupabaseConfig.hasPendingApproval, isTrue);
      expect(SupabaseConfig.hasValidSession, isFalse);
    },
  );

  test('pending verification marker survives an in-memory reset', () async {
    final fake = _FakeAccountAdapter();
    final service = CloudAccountService.forTesting(fake);
    expect(await service.requestBind('test@example.com'), isTrue);
    SupabaseConfig.resetIdentityStateForTesting();
    await SupabaseConfig.loadIdentityState();
    expect(SupabaseConfig.pendingApprovalEmail, 'test@example.com');
    expect(SupabaseConfig.authTransactionActive, isTrue);
  });

  test(
    'verification timeout keeps SDK result quarantined and blocks retry',
    () async {
      final fake = _FakeAccountAdapter()..verifyGate = Completer<void>();
      final service = CloudAccountService.forTesting(
        fake,
        waitTimeout: const Duration(milliseconds: 10),
      );
      expect(await service.requestBind('test@example.com'), isTrue);
      final first = await service.verify(
        code: '123456',
        allowLocalUpload: true,
      );
      expect(first, isFalse);
      expect(fake.verifyCalls, 1);
      expect(SupabaseConfig.hasPendingApproval, isTrue);
      fake.user = 'late-different-user';
      fake.verifyGate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(SupabaseConfig.hasPendingApproval, isTrue);
      expect(SupabaseConfig.hasValidSession, isFalse);
      expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
      expect(fake.verifyCalls, 1);
    },
  );

  test(
    'automatic refresh flight prevents interactive SDK operation from racing',
    () async {
      final fake = _FakeAccountAdapter()
        ..user = 'original-user'
        ..valid = false;
      fake.valid = false;
      final refreshGate = Completer<void>();
      var refreshCalls = 0;
      final recovery = _RefreshAdapter(fake, refreshGate, () => refreshCalls++);
      SupabaseConfig.setAuthAdapterForTesting(recovery);
      final refresh = SupabaseConfig.ensureAuthenticated();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final service = CloudAccountService.forTesting(
        fake,
        installRecoveryAdapter: false,
        waitTimeout: const Duration(milliseconds: 20),
      );
      expect(await service.requestBind('test@example.com'), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      expect(fake.updatedEmail, isNull);
      expect(refreshCalls, 1);
      refreshGate.complete();
      await refresh;
    },
  );

  test('existing valid account cannot be replaced by email sign-in', () async {
    final fake = _FakeAccountAdapter()..anonymous = false;
    final service = CloudAccountService.forTesting(fake);

    expect(await service.requestSignIn('known@example.com'), isFalse);
    expect(fake.signInCalls, 0);
  });

  test(
    'email sign-in uses existing-user OTP and locks pending email',
    () async {
      final fake = _FakeAccountAdapter()
        ..user = null
        ..valid = false;
      final service = CloudAccountService.forTesting(fake);

      expect(await service.requestSignIn('Known@Example.com'), isTrue);
      expect(service.snapshot.pendingEmail, 'known@example.com');
      expect(
        await service.verify(code: '12345', allowLocalUpload: true),
        isFalse,
      );
      expect(
        await service.verify(code: '123456', allowLocalUpload: true),
        isTrue,
      );
      expect(fake.verifiedEmail, 'known@example.com');
    },
  );
}
