import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jeff_notes/services/cloud_account_service.dart';
import 'package:jeff_notes/services/file_sync_agent.dart';
import 'package:jeff_notes/services/supabase_config.dart';

class _EmailAuth implements CloudAccountAuthAdapter {
  final sdkSessionInstalled = Completer<void>();
  final finishVerification = Completer<void>();
  @override
  String? userId;
  @override
  String? email;
  @override
  bool isAnonymous = false;
  @override
  bool emailConfirmed = false;
  @override
  bool hasValidSession = false;
  @override
  Future<void> signInExistingEmail(String email) async {}
  @override
  Future<void> updateEmail(String email) async =>
      throw StateError('Not binding');
  @override
  Future<void> verifyEmailChange(String email, String token) async =>
      throw StateError('Not binding');
  @override
  Future<void> verifyEmailSignIn(String value, String token) async {
    // Like GoTrue, the SDK session/event is updated before verifyOTP returns.
    userId = 'original-ipad-cloud-user';
    email = value;
    hasValidSession = emailConfirmed = true;
    sdkSessionInstalled.complete();
    await finishVerification.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'quarantined stale SDK session can explicitly recover the known email',
    () async {
      SharedPreferences.setMockInitialValues({
        'supabase_last_authenticated_user_id': 'original-ipad-cloud-user',
      });
      SupabaseConfig.setAuthAdapterForTesting(null);
      final auth = _EmailAuth()
        ..userId = 'stale-sdk-user'
        ..hasValidSession = true;
      final account = CloudAccountService.forTesting(auth);
      await account.refreshStatus();
      expect(SupabaseConfig.hasValidSession, isFalse);
      expect(await account.requestSignIn('owner@example.com'), isTrue);
      final verifying = account.verify(code: '123456', allowLocalUpload: true);
      await auth.sdkSessionInstalled.future;
      auth.finishVerification.complete();
      expect(await verifying, isTrue);
      expect(SupabaseConfig.currentUserIdOrNull, 'original-ipad-cloud-user');
      account.dispose();
      SupabaseConfig.setAuthAdapterForTesting(null);
    },
  );
  for (final invalid in [
    'email',
    'anonymous',
    'expired',
    'unconfirmed',
    'missing-user',
  ]) {
    test(
      'unapproved $invalid SDK identity cannot be adopted on restart',
      () async {
        SharedPreferences.setMockInitialValues({});
        SupabaseConfig.setAuthAdapterForTesting(null);
        final auth = _EmailAuth();
        final account = CloudAccountService.forTesting(auth);
        expect(await account.requestSignIn('owner@example.com'), isTrue);
        final verifying = account.verify(
          code: '123456',
          allowLocalUpload: true,
        );
        await auth.sdkSessionInstalled.future;
        switch (invalid) {
          case 'email':
            auth.email = 'different@example.com';
          case 'anonymous':
            auth.isAnonymous = true;
          case 'expired':
            auth.hasValidSession = false;
          case 'unconfirmed':
            auth.emailConfirmed = false;
          case 'missing-user':
            auth.userId = null;
        }
        auth.finishVerification.complete();
        expect(await verifying, isFalse);
        expect(SupabaseConfig.hasValidSession, isFalse);
        expect(SupabaseConfig.knownUserId, isNull);
        SupabaseConfig.resetIdentityStateForTesting();
        expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
        expect(SupabaseConfig.hasPendingApproval, isTrue);
        account.dispose();
        SupabaseConfig.setAuthAdapterForTesting(null);
      },
    );
  }
  test(
    'phone files upload only after the iPad identity is explicitly approved',
    () async {
      SharedPreferences.setMockInitialValues({
        'supabase_last_authenticated_user_id': 'old-phone-identity',
      });
      SupabaseConfig.setAuthAdapterForTesting(null);
      final directory = await Directory.systemTemp.createTemp(
        'jeff_email_upload_',
      );
      final file = File(
        '${directory.path}/Jeff_Notes_20260830_123456_789_123456.md',
      );
      await file.writeAsString(
        'Pending phone note stays local until approval.',
      );
      final auth = _EmailAuth();
      final account = CloudAccountService.forTesting(auth);
      final uploaded = <Map<String, dynamic>>[];
      final sync = FileSyncAgent.forTesting(
        authenticatedUser: () async => SupabaseConfig.currentUserIdOrNull,
        archiveUpload: (payload) async {
          uploaded.add(payload);
          return payload;
        },
        documentsDirectory: () async => directory,
      );
      try {
        expect(await account.requestSignIn('owner@example.com'), isTrue);
        final verifying = account.verify(
          code: '123456',
          allowLocalUpload: true,
        );
        await auth.sdkSessionInstalled.future;
        expect(auth.hasValidSession, isTrue);
        expect(SupabaseConfig.hasValidSession, isFalse);
        expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
        await sync.syncNow();
        expect(uploaded, isEmpty);
        expect(SupabaseConfig.knownUserId, 'old-phone-identity');

        auth.finishVerification.complete();
        expect(await verifying, isTrue);
        expect(SupabaseConfig.currentUserIdOrNull, 'original-ipad-cloud-user');
        await sync.syncNow();
        await sync.syncNow();
        expect(uploaded, hasLength(1));
        expect(uploaded.single['user_id'], 'original-ipad-cloud-user');
        expect(
          await file.readAsString(),
          'Pending phone note stays local until approval.',
        );
      } finally {
        if (!auth.finishVerification.isCompleted)
          auth.finishVerification.complete();
        account.dispose();
        SupabaseConfig.setAuthAdapterForTesting(null);
        await directory.delete(recursive: true);
      }
    },
  );
}
