import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/cloud_identity_guard.dart';
import 'package:jeff_notes/services/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth implements SupabaseAuthAdapter {
  @override
  String? currentUserId;
  @override
  bool hasSession;
  @override
  bool hasValidSession;

  _FakeAuth({
    this.currentUserId,
    this.hasSession = false,
    this.hasValidSession = false,
  });

  @override
  Future<String?> refreshSession() async => currentUserId;

  @override
  Future<String?> signInAnonymously() async => currentUserId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => SupabaseConfig.setAuthAdapterForTesting(null));

  test(
    'guard follows fake auth identity and rejects a switched account',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeAuth();
      SupabaseConfig.setAuthAdapterForTesting(fake);
      expect(CloudIdentityGuard.capture(), isNull);

      fake.currentUserId = 'user-a';
      fake.hasSession = true;
      fake.hasValidSession = true;
      await SupabaseConfig.ensureAuthenticated();
      expect(CloudIdentityGuard.capture(), 'user-a');
      expect(CloudIdentityGuard.stillCurrent('user-a'), isTrue);

      fake.currentUserId = 'user-b';
      expect(CloudIdentityGuard.capture(), isNull);
      expect(CloudIdentityGuard.stillCurrent('user-a'), isFalse);
    },
  );

  test(
    'guard remains closed while an authentication transaction is pending',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeAuth(
        currentUserId: 'original-user',
        hasSession: true,
        hasValidSession: true,
      );
      SupabaseConfig.setAuthAdapterForTesting(fake);
      expect(await SupabaseConfig.ensureAuthenticated(), isTrue);
      final started = await SupabaseConfig.runAccountOperation(
        () => SupabaseConfig.beginAuthTransaction(
          email: 'new@example.com',
          originalUserId: 'original-user',
        ),
      );
      expect(started, isTrue);
      expect(CloudIdentityGuard.capture(), isNull);
    },
  );
}
