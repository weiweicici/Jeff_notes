import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailingPreferencesStore extends SharedPreferencesStorePlatform {
  final Map<String, Object> data = <String, Object>{};
  String? failSetKey;
  String? failRemoveKey;
  int failedRemovals = 0;

  @override
  Future<Map<String, Object>> getAll() async => Map.of(data);

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == failSetKey) return false;
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (key == failRemoveKey) {
      failedRemovals++;
      return false;
    }
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }
}

class _FakeAuthAdapter implements SupabaseAuthAdapter {
  @override
  String? currentUserId;
  @override
  bool hasSession;
  @override
  bool hasValidSession = false;
  int refreshCalls = 0;
  int anonymousCalls = 0;
  Future<String?> Function()? refresh;

  _FakeAuthAdapter({this.currentUserId, this.hasSession = false});

  @override
  Future<String?> refreshSession() async {
    refreshCalls++;
    return refresh?.call();
  }

  @override
  Future<String?> signInAnonymously() async {
    anonymousCalls++;
    currentUserId = 'new-anonymous-user';
    hasValidSession = true;
    hasSession = true;
    return currentUserId;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SupabaseConfig.setAuthAdapterForTesting(null);
  });

  tearDown(() => SupabaseConfig.setAuthAdapterForTesting(null));

  test('known identity persistence failure fails closed', () async {
    final store = _FailingPreferencesStore()
      ..failSetKey = 'flutter.supabase_last_authenticated_user_id';
    SharedPreferencesStorePlatform.instance = store;
    final fake = _FakeAuthAdapter(currentUserId: 'original-user')
      ..hasValidSession = true;
    SupabaseConfig.setAuthAdapterForTesting(fake);
    expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
    expect(SupabaseConfig.hasValidSession, isFalse);
  });

  test('pending marker removal failure remains blocked after reload', () async {
    final store = _FailingPreferencesStore();
    SharedPreferencesStorePlatform.instance = store;
    final fake = _FakeAuthAdapter(currentUserId: 'original-user')
      ..hasValidSession = true;
    SupabaseConfig.setAuthAdapterForTesting(fake);
    await SupabaseConfig.runAccountOperation(() async {
      expect(
        await SupabaseConfig.beginAuthTransaction(
          email: 'bound@example.com',
          originalUserId: 'original-user',
        ),
        isTrue,
      );
      expect(await SupabaseConfig.beginAccountVerification(), isTrue);
      store.failRemoveKey = 'flutter.supabase_pending_identity_approval';
      expect(
        await SupabaseConfig.approveAuthTransaction(
          email: 'bound@example.com',
          userId: 'original-user',
          allowLocalUpload: true,
          identityStillVerified: () => true,
        ),
        isFalse,
      );
    });
    expect(
      store.data.keys,
      contains('flutter.supabase_pending_identity_approval'),
    );
    expect(SupabaseConfig.authTransactionActive, isTrue);
    expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
    expect(store.failedRemovals, 1);
    SharedPreferences.setMockInitialValues({
      for (final entry in store.data.entries)
        entry.key.substring('flutter.'.length): entry.value,
    });
    SupabaseConfig.setAuthAdapterForTesting(fake);
    expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
    expect(SupabaseConfig.pendingApprovalEmail, 'bound@example.com');
    expect(SupabaseConfig.hasValidSession, isFalse);
  });

  for (final failure in ['identity_write', 'pending_remove']) {
    test(
      'email login $failure failure stays quarantined across restart',
      () async {
        final store = _FailingPreferencesStore()
          ..data['flutter.supabase_last_authenticated_user_id'] =
              'old-phone-user';
        SharedPreferencesStorePlatform.instance = store;
        final fake = _FakeAuthAdapter();
        SupabaseConfig.setAuthAdapterForTesting(fake);
        await SupabaseConfig.runAccountOperation(() async {
          expect(
            await SupabaseConfig.beginAuthTransaction(
              email: 'owner@example.com',
            ),
            isTrue,
          );
          expect(await SupabaseConfig.beginAccountVerification(), isTrue);
          fake.currentUserId = 'verified-ipad-user';
          fake.hasValidSession = true;
          fake.hasSession = true;
          if (failure == 'identity_write') {
            store.failSetKey = 'flutter.supabase_last_authenticated_user_id';
          } else {
            store.failRemoveKey = 'flutter.supabase_pending_identity_approval';
          }
          expect(
            await SupabaseConfig.approveAuthTransaction(
              email: 'owner@example.com',
              userId: 'verified-ipad-user',
              allowLocalUpload: true,
              identityStillVerified: () => true,
            ),
            isFalse,
          );
        });
        expect(SupabaseConfig.hasValidSession, isFalse);
        // Rebuild BOTH the preferences cache and auth coordinator from the
        // persisted backing only. Failed in-memory plugin writes are discarded.
        SharedPreferences.setMockInitialValues({
          for (final entry in store.data.entries)
            entry.key.substring('flutter.'.length): entry.value,
        });
        SupabaseConfig.setAuthAdapterForTesting(fake);
        expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
        expect(SupabaseConfig.hasValidSession, isFalse);
        expect(SupabaseConfig.pendingApprovalEmail, 'owner@example.com');
        expect(fake.anonymousCalls, 0);
      },
    );
  }

  test(
    'refresh failure never creates a replacement anonymous identity',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeAuthAdapter(
        currentUserId: 'original-user',
        hasSession: true,
      );
      fake.refresh = () async => throw StateError('transient failure');
      SupabaseConfig.setAuthAdapterForTesting(fake);

      expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
      expect(fake.refreshCalls, 1);
      expect(fake.anonymousCalls, 0);
    },
  );

  test(
    'concurrent authentication recovery is single flight and preserves user',
    () async {
      SharedPreferences.setMockInitialValues({});
      final gate = Completer<void>();
      final fake = _FakeAuthAdapter(
        currentUserId: 'original-user',
        hasSession: true,
      );
      fake.refresh = () async {
        await gate.future;
        fake.hasValidSession = true;
        return 'original-user';
      };
      SupabaseConfig.setAuthAdapterForTesting(fake);

      final first = SupabaseConfig.ensureAuthenticated();
      final second = SupabaseConfig.ensureAuthenticated();
      gate.complete();

      expect(await Future.wait([first, second]), [true, true]);
      expect(fake.refreshCalls, 1);
      expect(fake.anonymousCalls, 0);
    },
  );

  test(
    'refresh that clears session cannot fall through to anonymous sign-in',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeAuthAdapter(
        currentUserId: 'original-user',
        hasSession: true,
      );
      fake.refresh = () async {
        fake.currentUserId = null;
        fake.hasSession = false;
        return null;
      };
      SupabaseConfig.setAuthAdapterForTesting(fake);

      expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
      expect(fake.anonymousCalls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('supabase_last_authenticated_user_id'),
        'original-user',
      );
      // The next call sees no SDK session, but still must not make a new user.
      expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
      expect(fake.anonymousCalls, 0);
    },
  );

  test('refresh returning a different user is rejected', () async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeAuthAdapter(
      currentUserId: 'original-user',
      hasSession: true,
    );
    fake.refresh = () async {
      fake.currentUserId = 'different-user';
      fake.hasValidSession = true;
      return 'different-user';
    };
    SupabaseConfig.setAuthAdapterForTesting(fake);

    expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
    expect(fake.anonymousCalls, 0);
    // A mismatched refreshed session must not be adopted on the next call.
    expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
  });

  test('caller timeout does not start a second underlying refresh', () async {
    SharedPreferences.setMockInitialValues({});
    final gate = Completer<String?>();
    final fake = _FakeAuthAdapter(
      currentUserId: 'original-user',
      hasSession: true,
    );
    fake.refresh = () async {
      final user = await gate.future;
      fake.hasValidSession = true;
      return user;
    };
    SupabaseConfig.setAuthAdapterForTesting(
      fake,
      waitTimeout: const Duration(milliseconds: 10),
    );
    expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
    expect(fake.refreshCalls, 1);
    final retry = SupabaseConfig.ensureAuthenticated();
    gate.complete('original-user');
    expect(await retry, isTrue);
    expect(fake.refreshCalls, 1);
    expect(fake.anonymousCalls, 0);
  });

  test(
    'diagnostic log and bundled references are not previous user history',
    () {
      expect(
        SupabaseConfig.isUserHistoryFile('/docs/jeff_notes_diagnostic.log'),
        isFalse,
      );
      expect(
        SupabaseConfig.isUserHistoryFile(
          '/docs/ultimate_grammar_quick_reference.md',
        ),
        isFalse,
      );
      expect(
        SupabaseConfig.isUserHistoryFile(
          '/docs/Jeff_Notes_20260829_123456_789_123456.md',
        ),
        isTrue,
      );
      expect(
        SupabaseConfig.isUserHistoryFile('/docs/shadow_draft_session.json'),
        isTrue,
      );
      expect(
        SupabaseConfig.isUserHistoryFile('/docs/rec_1788065000000.wav'),
        isTrue,
      );
    },
  );

  test('missing session with local identity marker is blocked', () async {
    SharedPreferences.setMockInitialValues({
      'supabase_last_authenticated_user_id': 'original-user',
    });
    final fake = _FakeAuthAdapter();
    SupabaseConfig.setAuthAdapterForTesting(fake);

    expect(await SupabaseConfig.ensureAuthenticated(), isFalse);
    expect(fake.anonymousCalls, 0);
  });
}
